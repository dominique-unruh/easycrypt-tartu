(* -------------------------------------------------------------------- *)
open EcUtils
open EcParsetree
open EcLocation
open EcIdent
open EcSymbols
open EcPath
open EcTypes
open EcFol
open EcEnv
open EcMatching
open EcReduction
open EcCoreGoal
open EcBaseLogic

module ER  = EcReduction
module TTC = EcProofTyping

(* -------------------------------------------------------------------- *)
exception InvalidProofTerm

type side = [`Left|`Right]

(* -------------------------------------------------------------------- *)
module LowApply = struct
  type ckenv = [`Tc of rtcenv | `Hyps of LDecl.hyps * proofenv]

  (* ------------------------------------------------------------------ *)
  let hyps_of_ckenv = function
    | `Hyps hyps -> (fst hyps)
    | `Tc   tc   -> RApi.tc_hyps tc

  (* ------------------------------------------------------------------ *)
  let rec check_pthead (pt : pt_head) (tc : ckenv) =
    match pt with
    | PTCut f -> begin
        match tc with
        | `Hyps  _ -> (PTCut f, f)
        | `Tc   tc ->
            (* cut - create a dedicated subgoal *)
            let handle = RApi.newgoal tc f in (PTHandle handle, f)
    end

    | PTHandle hd -> begin
        let subgoal =
          match tc with
          | `Hyps tc -> FApi.get_pregoal_by_id hd (snd tc)
          | `Tc   tc -> RApi.tc_get_pregoal_by_id hd tc
        in
        (* proof reuse - fetch corresponding subgoal*)
        if subgoal.g_hyps !=(*φ*) hyps_of_ckenv tc then
          raise InvalidProofTerm;
        (pt, subgoal.g_concl)
    end

    | PTLocal x -> begin
        let hyps = hyps_of_ckenv tc in
        try  (pt, LDecl.lookup_hyp_by_id x hyps)
        with LDecl.Ldecl_error _ -> raise InvalidProofTerm
    end

    | PTGlobal (p, tys) ->
        (* FIXME: poor API ==> poor error recovery *)
        let env = LDecl.toenv (hyps_of_ckenv tc) in
        (pt, EcEnv.Ax.instanciate p tys env)

  (* ------------------------------------------------------------------ *)
  and check (mode : [`Intro | `Elim]) (pt : proofterm) (tc : ckenv) =
    let hyps = hyps_of_ckenv tc in
    let env  = LDecl.toenv hyps in

    let rec check_args (sbt, ax, nargs) args =
      match args with
      | [] -> (Fsubst.f_subst sbt ax, List.rev nargs)

      | arg :: args ->
          let ((sbt, ax), narg) = check_arg (sbt, ax) arg in
          check_args (sbt, ax, narg :: nargs) args

    and check_arg (sbt, ax) arg =
      let check_binder (x, xty) f =
        let xty = Fsubst.gty_subst sbt xty in

        match xty, arg with
        | GTty xty, PAFormula arg ->
            if not (EcReduction.EqTest.for_type env xty arg.f_ty) then
              raise InvalidProofTerm;
            (Fsubst.f_bind_local sbt x arg, f)

        | GTmem _, PAMemory m ->
            (Fsubst.f_bind_mem sbt x m, f)

        | GTmodty (emt, restr), PAModule (mp, mt) -> begin
          (* FIXME: poor API ==> poor error recovery *)
          try
            EcTyping.check_modtype_with_restrictions env mp mt emt restr;
            EcPV.check_module_in env mp emt;
            (Fsubst.f_bind_mod sbt x mp, f)
          with _ -> raise InvalidProofTerm
        end

        | _ -> raise InvalidProofTerm
      in

      match mode with
      | `Elim -> begin
          match TTC.destruct_product hyps ax, arg with
          | Some (`Imp (f1, f2)), PASub subpt when mode = `Elim ->
              let f1    = Fsubst.f_subst sbt f1 in
              let subpt =
                match subpt with
                | None       -> { pt_head = PTCut f1; pt_args = []; }
                | Some subpt -> subpt
              in
              let subpt, subax = check mode subpt tc in
                if not (EcReduction.is_conv hyps f1 subax) then
                  raise InvalidProofTerm;
                ((sbt, f2), PASub (Some subpt))

          | Some (`Forall (x, xty, f)), _ ->
              (check_binder (x, xty) f, arg)

          | _, _ ->
              if Fsubst.is_subst_id sbt then
                raise InvalidProofTerm;
              check_arg (Fsubst.f_subst_id, Fsubst.f_subst sbt ax) arg
      end

      | `Intro -> begin
          match TTC.destruct_exists hyps ax with
          | Some (`Exists (x, xty, f)) -> (check_binder (x, xty) f, arg)
          | None ->
              if Fsubst.is_subst_id sbt then
                raise InvalidProofTerm;
              check_arg (Fsubst.f_subst_id, Fsubst.f_subst sbt ax) arg
      end
    in

    let (nhd, ax) = check_pthead pt.pt_head tc in
    let ax, nargs = check_args (Fsubst.f_subst_id, ax, []) pt.pt_args in

    ({ pt_head = nhd; pt_args = nargs }, ax)
end

(* -------------------------------------------------------------------- *)
let t_admit (tc : tcenv1) =
  FApi.close (FApi.tcenv_of_tcenv1 tc) VAdmit

(* -------------------------------------------------------------------- *)
let t_fail (tc : tcenv1) =
  tc_error !!tc ~who:"fail" "explicit call to [fail]"

(* -------------------------------------------------------------------- *)
let t_id (tc : tcenv1) =
  FApi.tcenv_of_tcenv1 tc

(* -------------------------------------------------------------------- *)
let t_change (fp : form) (tc : tcenv1) =
  let hyps, concl = FApi.tc1_flat tc in
  if not (EcReduction.is_conv hyps fp concl) then
    raise InvalidGoalShape;
  FApi.mutate1 tc (fun hd -> VConv (hd, Sid.empty)) fp

(* -------------------------------------------------------------------- *)
let t_simplify_with_info (ri : reduction_info) (tc : tcenv1) =
  let hyps, concl = FApi.tc1_flat tc in
  let concl = EcReduction.simplify ri hyps concl in
  FApi.xmutate1 tc (fun hd -> VConv (hd, Sid.empty)) [concl]

(* -------------------------------------------------------------------- *)
let t_simplify ?(delta=true) (tc : tcenv1) =
  let ri = if delta then full_red else nodelta in
  t_simplify_with_info ri tc

(* -------------------------------------------------------------------- *)
let t_clears xs tc =
  let (hyps, concl) = FApi.tc1_flat tc in

  if not (Mid.set_disjoint xs concl.f_fv) then
    let x () = (Sid.elements (Mid.set_inter xs concl.f_fv), None) in
    raise (ClearError (lazy (x ())))
  else

  let hyps =
    try  LDecl.clear xs hyps
    with LDecl.Ldecl_error (LDecl.CanNotClear(id1, id2)) ->
      raise (ClearError (lazy ([id1], Some id2)))
  in

  FApi.mutate (!@tc) (fun hd -> VConv (hd, xs)) ~hyps concl

(* -------------------------------------------------------------------- *)
let t_clear x tc =
  t_clears (Sid.singleton x) tc

(* -------------------------------------------------------------------- *)
let t_clears xs tc =
  t_clears (Sid.of_list xs) tc

(* -------------------------------------------------------------------- *)
module LowIntro = struct
  let valid_value_name (x : symbol) = x = "_" || EcIo.is_sym_ident x
  let valid_mod_name   (x : symbol) = x = "_" || EcIo.is_mod_ident x
  let valid_mem_name   (x : symbol) = x = "_" || EcIo.is_mem_ident x

  type kind = [`Value | `Module | `Memory]

  let tc_no_product (pe : proofenv) ?loc () =
    tc_error pe ?loc "nothing to introduce"

  let check_name_validity pe kind x : unit =
    let ok =
      match kind with
      | `Value  -> valid_value_name (tg_val x)
      | `Module -> valid_mod_name   (tg_val x)
      | `Memory -> valid_mem_name   (tg_val x)
    in
      if not ok then
        tc_error pe ?loc:(tg_tag x) "invalid name: %s" (tg_val x)
end

(* -------------------------------------------------------------------- *)
let t_intros (ids : ident mloc list) (tc : tcenv1) =
  let add_local id sbt x gty =
    let gty = Fsubst.gty_subst sbt gty in
    let name = tg_map EcIdent.name id in
    let id   = tg_val id in

    match gty with
    | GTty ty ->
        LowIntro.check_name_validity !!tc `Value name;
        (LD_var (ty, None), Fsubst.f_bind_local sbt x (f_local id ty))
    | GTmem me ->
        LowIntro.check_name_validity !!tc `Memory name;
        (LD_mem me, Fsubst.f_bind_mem sbt x id)
    | GTmodty (i, r) ->
        LowIntro.check_name_validity !!tc `Module name;
        (LD_modty (i, r), Fsubst.f_bind_mod sbt x (EcPath.mident id))
  in

  let add_ld id ld hyps =
    EcLocation.set_oloc
      (tg_tag id)
      (fun () -> LDecl.add_local (tg_val id) ld hyps) ()
  in

  let rec intro1 ((hyps, concl), sbt) id =
    match EcFol.sform_of_form concl with
    | SFquant (Lforall, (x, gty), lazy concl) ->
        let (ld, sbt) = add_local id sbt x gty in
        let hyps = add_ld id ld hyps in
        (hyps, concl), sbt

    | SFimp (prem, concl) ->
        let prem = Fsubst.f_subst sbt prem in
        let hyps = add_ld id (LD_hyp prem) hyps in
        (hyps, concl), sbt

    | SFlet (LSymbol (x, xty), xe, concl) ->
        let xty  = sbt.fs_ty xty in
        let xe   = Fsubst.f_subst sbt xe in
        let sbt  = Fsubst.f_bind_local sbt x (f_local (tg_val id) xty) in
        let hyps = add_ld id (LD_var (xty, Some xe)) hyps in
        (hyps, concl), sbt

    | _ when sbt !=(*φ*) Fsubst.f_subst_id ->
        let concl = Fsubst.f_subst sbt concl in
        intro1 ((hyps, concl), Fsubst.f_subst_id) id

    | _ ->
        match h_red_opt full_red hyps concl with
        | None       -> LowIntro.tc_no_product !!tc ?loc:(tg_tag id) ()
        | Some concl -> intro1 ((hyps, concl), sbt) id
  in

  let tc  = FApi.tcenv_of_tcenv1 tc in
  let sbt = Fsubst.f_subst_id in
  let (hyps, concl), sbt = List.fold_left intro1 (FApi.tc_flat tc, sbt) ids in
  let concl = Fsubst.f_subst sbt concl in
  let (tc, hd) = FApi.newgoal tc ~hyps concl in
  FApi.close tc (VIntros (hd, List.map tg_val ids))

(* -------------------------------------------------------------------- *)
type iname  = [`Symbol of symbol      | `Ident of EcIdent.t     ]
type inames = [`Symbol of symbol list | `Ident of EcIdent.t list]

(* -------------------------------------------------------------------- *)
let t_intro_i (id : EcIdent.t) (tc : tcenv1) =
  t_intros [notag id] tc

(* -------------------------------------------------------------------- *)
let t_intro_s (id : iname) (tc : tcenv1) =
  match id with
  | `Symbol x -> t_intro_i (EcIdent.create x) tc
  | `Ident  x -> t_intro_i x tc

(* -------------------------------------------------------------------- *)
let t_intros_i (ids : EcIdent.t list) (tc : tcenv1) =
  t_intros (List.map notag ids) tc

(* -------------------------------------------------------------------- *)
let t_intros_s (ids : inames) (tc : tcenv1) =
  match ids with
  | `Symbol x -> t_intros_i (List.map EcIdent.create x) tc
  | `Ident  x -> t_intros_i x tc

(* -------------------------------------------------------------------- *)
let t_intros_i_1 (ids : EcIdent.t list) (tc : tcenv1) =
  FApi.as_tcenv1 (t_intros_i ids tc)

(* -------------------------------------------------------------------- *)
let t_intros_i_seq ?(clear = false) ids tt tc =
  let tt = if clear then FApi.t_seq tt (t_clears ids) else tt in
  FApi.t_focus tt (t_intros_i ids tc)

(* -------------------------------------------------------------------- *)
let t_intros_s_seq ids tt tc =
  FApi.t_focus tt (t_intros_s ids tc)

(* -------------------------------------------------------------------- *)
let tt_apply (pt : proofterm) (tc : tcenv) =
  let (hyps, concl) = FApi.tc_flat tc in
  let tc, (pt, ax)  =
    RApi.to_pure (fun tc -> LowApply.check `Elim pt (`Tc tc)) tc in

  if not (EcReduction.is_conv hyps concl ax) then
    raise InvalidGoalShape;
  FApi.close tc (VApply pt)

(* -------------------------------------------------------------------- *)
let tt_apply_hyp (x : EcIdent.t) ?(args = []) ?(sk = 0) tc =
  let pt =
    let args = (List.map paformula args) @ (List.create sk (PASub None)) in
    { pt_head = PTLocal x; pt_args = args; } in

  tt_apply pt tc

(* -------------------------------------------------------------------- *)
let tt_apply_s (p : path) tys ?(args = []) ?(sk = 0) tc =
  let pt =
    let args = (List.map paformula args) @ (List.create sk (PASub None)) in
    { pt_head = PTGlobal (p, tys); pt_args = args; } in

  tt_apply pt tc

(* -------------------------------------------------------------------- *)
let tt_apply_hd (hd : handle) ?(args = []) ?(sk = 0) tc =
  let pt =
    let args = (List.map paformula args) @ (List.create sk (PASub None)) in
    { pt_head = PTHandle hd; pt_args = args; } in

  tt_apply pt tc

(* -------------------------------------------------------------------- *)
let t_apply (pt : proofterm) (tc : tcenv1) =
  tt_apply pt (FApi.tcenv_of_tcenv1 tc)

(* -------------------------------------------------------------------- *)
let t_apply_hyp (x : EcIdent.t) ?args ?sk tc =
  tt_apply_hyp x ?args ?sk (FApi.tcenv_of_tcenv1 tc)

(* -------------------------------------------------------------------- *)
let t_hyp (x : EcIdent.t) tc =
  t_apply_hyp x ~args:[] ~sk:0 tc

(* -------------------------------------------------------------------- *)
let t_apply_s (p : path) (tys : ty list) ?args ?sk tc =
  tt_apply_s p tys ?args ?sk (FApi.tcenv_of_tcenv1 tc)

(* -------------------------------------------------------------------- *)
let t_apply_hd (hd : handle) ?args ?sk tc =
  tt_apply_hd hd ?args ?sk (FApi.tcenv_of_tcenv1 tc)

(* -------------------------------------------------------------------- *)
let t_generalize_hyps ?(clear = false) ids tc =
  let env, hyps, concl = FApi.tc1_eflat tc in

  let rec for1 (s, bds, args) id =
    match LDecl.ld_subst s (LDecl.lookup_by_id id hyps) with
    | LD_var (ty, _) ->
        let x    = EcIdent.fresh id in
        let s    = Fsubst.f_bind_local s id (f_local x ty) in
        let bds  = `Forall (x, GTty ty) :: bds in
        let args = PAFormula (f_local id ty) :: args in
        (s, bds, args)

    | LD_mem mt ->
      let x    = EcIdent.fresh id in
      let s    = Fsubst.f_bind_mem s id x in
      let bds  = `Forall (x, GTmem mt) :: bds in
      let args = PAMemory id :: args in
      (s, bds, args)

    | LD_modty (mt,r) ->
      let x    = EcIdent.fresh id in
      let s    = Fsubst.f_bind_mod s id (EcPath.mident x) in
      let mp   = EcPath.mident id in
      let sig_ = (EcEnv.Mod.by_mpath mp env).EcModules.me_sig in
      let bds  = `Forall (x, GTmodty (mt, r)) :: bds in
      let args = PAModule (mp, sig_) :: args in
      (s, bds, args)

    | LD_hyp f ->
        let bds  = `Imp f :: bds in
        let args = palocal id :: args in
        (s, bds, args)

    | LD_abs_st _ ->
        raise InvalidGoalShape

  in

  let (s, bds, args) = (Fsubst.f_subst_id, [], []) in
  let (s, bds, args) = List.fold_left for1 (s, bds, args) ids in

  let ff =
    List.fold_right
      (fun bd ff ->
        match bd with
        | `Forall (x, xty) -> f_forall [x, xty] ff
        | `Imp    pre      -> f_imp pre ff)
      bds (Fsubst.f_subst s concl) in

  let pt = { pt_head = PTCut ff; pt_args = List.rev args; } in
  let tc = t_apply pt tc in

  if clear then FApi.t_onall (t_clears ids) tc else tc

let t_generalize_hyp ?clear id tc =
  t_generalize_hyps ?clear [id] tc

(* -------------------------------------------------------------------- *)
module LowAssumption = struct
  (* ------------------------------------------------------------------ *)
  let gen_find_in_hyps test hyps f =
    let test (_, lk) =
      match lk with
      | LD_hyp f' -> test hyps f f'
      | _         -> false
    in
      fst (List.find test (LDecl.tohyps hyps).h_local)

  (* ------------------------------------------------------------------ *)
  let t_gen_assumption tests tc =
    let (hyps, concl) = FApi.tc1_flat tc in

    let hyp =
      try
        List.find_map
          (fun test ->
            try  Some (gen_find_in_hyps test hyps concl)
            with Not_found -> None)
          tests
      with Not_found -> tc_error !!tc "no assumption"
    in
    FApi.t_internal (t_hyp hyp) tc
end

(* -------------------------------------------------------------------- *)
let t_assumption mode (tc : tcenv1) =
  let convs =
    match mode with
    | `Alpha -> [EcReduction.is_alpha_eq]
    | `Conv  -> [EcReduction.is_alpha_eq; EcReduction.is_conv]
  in
    LowAssumption.t_gen_assumption convs tc

(* -------------------------------------------------------------------- *)
let t_cut (fp : form) (tc : tcenv1) =
  let concl = FApi.tc1_goal tc in
  t_apply_s EcCoreLib.p_cut_lemma [] ~args:[fp; concl] ~sk:2 tc

(* -------------------------------------------------------------------- *)
let t_cutdef (pt : proofterm) (fp : form) (tc : tcenv1) =
  FApi.t_first (t_apply pt) (t_cut fp tc)

(* -------------------------------------------------------------------- *)
let t_true (tc : tcenv1) =
  t_apply_s EcCoreLib.p_true_intro [] tc

(* -------------------------------------------------------------------- *)
let t_reflex_s (f : form) (tc : tcenv1) =
  t_apply_s EcCoreLib.p_eq_refl [f.f_ty] ~args:[f] tc

let t_reflex ?reduce (tc : tcenv1) =
  let t_reflex_r (fp : form) (tc : tcenv1) =
    match sform_of_form fp with
    | SFeq (f1, _f2) -> t_reflex_s f1 tc
    | _ -> raise TTC.NoMatch
  in
    TTC.t_lazy_match ?reduce t_reflex_r tc

(* -------------------------------------------------------------------- *)
let t_symmetry_s f1 f2 tc =
  t_apply_s EcCoreLib.p_eq_sym [f1.f_ty] ~args:[f1; f2] tc

let t_symmetry ?reduce (tc : tcenv1) =
  let t_symmetry_r (fp : form) (tc : tcenv1) =
    match sform_of_form fp with
    | SFeq (f1, f2) -> t_symmetry_s f1 f2 tc
    | _ -> raise TTC.NoMatch
  in
    TTC.t_lazy_match ?reduce t_symmetry_r tc

(* -------------------------------------------------------------------- *)
let t_transitivity_s f1 f2 f3 tc =
  t_apply_s EcCoreLib.p_eq_trans [f1.f_ty] ~args:[f1; f2; f3] ~sk:2 tc

let t_transitivity ?reduce f2 (tc : tcenv1) =
  let t_transitivity_r (fp : form) (tc : tcenv1) =
    match sform_of_form fp with
    | SFeq (f1, f3) -> t_transitivity_s f1 f2 f3 tc
    | _ -> raise TTC.NoMatch
  in
    TTC.t_lazy_match ?reduce t_transitivity_r tc

(* -------------------------------------------------------------------- *)
let t_exists_intro_s (args : pt_arg list) (tc : tcenv1) =
  let hyps = FApi.tc1_hyps tc in
  let pt = { pt_head = PTHandle (FApi.tc1_handle tc);
             pt_args = args; } in
  let ax = snd (LowApply.check `Intro pt (`Hyps (hyps, !!tc))) in
  FApi.xmutate1 tc (`Exists args) [ax]

(* -------------------------------------------------------------------- *)
let t_or_intro_s (b : bool) (side : side) (f1, f2 : form pair) (tc : tcenv1) =
  let p =
    match side, b with
    | `Left , true  -> EcCoreLib.p_ora_intro_l
    | `Right, true  -> EcCoreLib.p_ora_intro_r
    | `Left , false -> EcCoreLib.p_or_intro_l
    | `Right, false -> EcCoreLib.p_or_intro_r
  in
  t_apply_s p [] ~args:[f1; f2] ~sk:1 tc

let t_or_intro ?reduce (side : side) (tc : tcenv1) =
  let t_or_intro_r (fp : form) (tc : tcenv1) =
    match sform_of_form fp with
    | SFor (b, (left, right)) -> t_or_intro_s b side (left, right) tc
    | _ -> raise TTC.NoMatch
  in
    TTC.t_lazy_match ?reduce t_or_intro_r tc

let t_left  ?reduce tc = t_or_intro ?reduce `Left  tc
let t_right ?reduce tc = t_or_intro ?reduce `Right tc

(* -------------------------------------------------------------------- *)
let t_and_intro_s (b : bool) (f1, f2 : form pair) (tc : tcenv1) =
  let p = if b then EcCoreLib.p_anda_intro else EcCoreLib.p_and_intro in
  t_apply_s p [] ~args:[f1; f2] ~sk:2 tc

let t_and_intro ?reduce (tc : tcenv1) =
  let t_and_intro_r (fp : form) (tc : tcenv1) =
    match sform_of_form fp with
    | SFand (b, (left, right)) -> t_and_intro_s b (left, right) tc
    | _ -> raise TTC.NoMatch
  in
    TTC.t_lazy_match ?reduce t_and_intro_r tc

(* -------------------------------------------------------------------- *)
let t_iff_intro_s (f1, f2 : form pair) (tc : tcenv1) =
  t_apply_s EcCoreLib.p_iff_intro [] ~args:[f1; f2] ~sk:2 tc

let t_iff_intro ?reduce (tc : tcenv1) =
  let t_iff_intro_r (fp : form) (tc : tcenv1) =
    match sform_of_form fp with
    | SFiff (f1, f2) -> t_iff_intro_s (f1, f2) tc
    | _ -> raise TTC.NoMatch
  in
    TTC.t_lazy_match ?reduce t_iff_intro_r tc

(* -------------------------------------------------------------------- *)
let gen_tuple_intro tys =
  let var ty name i =
    let var = EcIdent.create (Printf.sprintf "%s%d" name (i+1)) in
    (var, f_local var ty) in

  let eq i ty =
    let (x, fx) = var ty "x" i in
    let (y, fy) = var ty "y" i in
    ((x, fx), (y, fy), f_eq fx fy) in

  let eqs   = List.mapi eq tys in
  let concl = f_eq (f_tuple (List.map (snd |- proj3_1) eqs))
                   (f_tuple (List.map (snd |- proj3_2) eqs)) in
  let concl = f_imps (List.map proj3_3 eqs) concl in
  let concl =
    let bindings =
      let for1 ((x, fx), (y, fy), _) bindings =
        (x, GTty fx.f_ty) :: (y, GTty fy.f_ty) :: bindings in
      List.fold_right for1 eqs [] in
    f_forall bindings concl
  in

  concl

(* -------------------------------------------------------------------- *)
let pf_gen_tuple_intro tys hyps pe =
  let fp = gen_tuple_intro tys in
  FApi.newfact pe (VExtern (`TupleCongr tys, [])) hyps fp

(* -------------------------------------------------------------------- *)
let t_tuple_intro_s (fs : form pair list) (tc : tcenv1) =
  let tc  = RApi.rtcenv_of_tcenv1 tc in
  let tys = List.map (fun f -> (fst f).f_ty) fs in
  let hd  = RApi.bwd_of_fwd (pf_gen_tuple_intro tys (RApi.tc_hyps tc)) tc in
  let fs  = List.flatten (List.map (fun (x, y) -> [x; y]) fs) in

  RApi.of_pure_u (tt_apply_hd hd ~args:fs ~sk:(List.length tys)) tc;
  RApi.tcenv_of_rtcenv tc

let t_tuple_intro ?reduce (tc : tcenv1) =
  let t_tuple_intro_r (fp : form) (tc : tcenv1) =
    match sform_of_form fp with
    | SFeq (f1, f2) when is_tuple f1 && is_tuple f2 ->
        let fs = List.combine (destr_tuple f1) (destr_tuple f2) in
        t_tuple_intro_s fs tc
    | _ -> raise TTC.NoMatch
  in
    TTC.t_lazy_match ?reduce t_tuple_intro_r tc

(* -------------------------------------------------------------------- *)
let t_elim_r ?(reduce = true) txs tc =
  match sform_of_form (FApi.tc1_goal tc) with
  | SFimp (f1, f2) ->
      let rec aux f1 =
        let sf1 = sform_of_form f1 in

        match
          List.pick (fun tx ->
              try  Some (tx (f1, sf1) f2 tc)
              with TTC.NoMatch -> None)
            txs
        with
        | Some gs -> gs
        | None    ->
            if not reduce then raise InvalidGoalShape;
            match h_red_opt full_red (FApi.tc1_hyps tc) f1 with
            | None    -> raise InvalidGoalShape
            | Some f1 -> aux f1
      in
        aux f1

    | _ -> raise InvalidGoalShape

(* -------------------------------------------------------------------- *)
let t_elim_false_r ((_, sf) : form * sform) concl tc =
  match sf with
  | SFfalse -> t_apply_s EcCoreLib.p_false_elim [] ~args:[concl] tc
  | _ -> raise TTC.NoMatch

let t_elim_false tc = t_elim_r [t_elim_false_r] tc

(* --------------------------------------------------------------------- *)
let t_elim_and_r ((_, sf) : form * sform) concl tc =
  match sf with
  | SFand (b, (a1, a2)) ->
      let p = if b then EcCoreLib.p_anda_elim else EcCoreLib.p_and_elim in
      t_apply_s p [] ~args:[a1; a2; concl] ~sk:1 tc
  | _ -> raise TTC.NoMatch

let t_elim_and goal = t_elim_r [t_elim_and_r] goal

(* --------------------------------------------------------------------- *)
let t_elim_or_r ((_, sf) : form * sform) concl tc =
  match sf with
  | SFor (b, (a1, a2)) ->
      let p = if b then EcCoreLib.p_ora_elim else EcCoreLib.p_or_elim  in
      t_apply_s p [] ~args:[a1; a2; concl] ~sk:2 tc
  | _ -> raise TTC.NoMatch

let t_elim_or tc = t_elim_r [t_elim_or_r] tc

(* --------------------------------------------------------------------- *)
let t_elim_iff_r ((_, sf) : form * sform) concl tc =
  match sf with
  | SFiff (a1, a2) ->
      t_apply_s EcCoreLib.p_iff_elim [] ~args:[a1; a2; concl] ~sk:1 tc
  | _ -> raise TTC.NoMatch

let t_elim_iff tc = t_elim_r [t_elim_iff_r] tc

(* -------------------------------------------------------------------- *)
let t_elim_if_r ((_, sf) : form * sform) concl tc =
  match sf with
  | SFif (a1, a2, a3) ->
      t_apply_s EcCoreLib.p_if_elim [] ~args:[a1; a2; a3; concl] ~sk:2 tc
  | _ -> raise TTC.NoMatch

let t_elim_if tc = t_elim_r [t_elim_if_r] tc

(* -------------------------------------------------------------------- *)
let gen_tuple_eq_elim (tys : ty list) : form =
  let p  = EcIdent.create "p" in
  let fp = f_local p tbool in

  let var ty name i =
    let var = EcIdent.create (Printf.sprintf "%s%d" name (i+1)) in
    (var, f_local var ty) in

  let eq i ty =
    let (x, fx) = var ty "x" i in
    let (y, fy) = var ty "y" i in
    ((x, fx), (y, fy), f_eq fx fy) in

  let eqs   = List.mapi eq tys in
  let concl = f_eq (f_tuple (List.map (snd |- proj3_1) eqs))
                   (f_tuple (List.map (snd |- proj3_2) eqs)) in
  let concl = f_imps [f_imps (List.map proj3_3 eqs) fp; concl] fp in
  let concl =
    let bindings =
      let for1 ((x, fx), (y, fy), _) bindings =
        (x, GTty fx.f_ty) :: (y, GTty fy.f_ty) :: bindings in
      List.fold_right for1 eqs [] in
    f_forall bindings concl
  in

  f_forall [(p, GTty tbool)] concl

(* -------------------------------------------------------------------- *)
let pf_gen_tuple_eq_elim tys hyps pe =
  let fp = gen_tuple_eq_elim tys in
  FApi.newfact pe (VExtern (`TupleEqElim tys, [])) hyps fp

(* -------------------------------------------------------------------- *)
let t_elim_eq_tuple_r ((_, sf) : form * sform) concl tc =
  match sf with
  | SFeq (a1, a2) when is_tuple a1 && is_tuple a2 ->
      let tc   = RApi.rtcenv_of_tcenv1 tc in
      let hyps = RApi.tc_hyps tc in
      let fs   = List.combine (destr_tuple a1) (destr_tuple a2) in
      let tys  = List.map (f_ty |- fst) fs in
      let hd   = RApi.bwd_of_fwd (pf_gen_tuple_eq_elim tys hyps) tc in
      let args = List.flatten (List.map (fun (x, y) -> [x; y]) fs) in
      let args = concl :: args in

      RApi.of_pure_u (tt_apply_hd hd ~args ~sk:1) tc;
      RApi.tcenv_of_rtcenv tc

  | _ -> raise TTC.NoMatch

let t_elim_eq_tuple goal = t_elim_r [t_elim_eq_tuple_r] goal

(* -------------------------------------------------------------------- *)
let t_elim_exists_r ((f, _) : form * sform) concl tc =
  match f.f_node with
  | Fquant (Lexists, bd, body) ->
      let newc = f_forall bd (f_imp body concl) in
      let tc   = FApi.mutate1 tc (fun hd -> VExtern (`Exists, [hd])) newc in
      FApi.tcenv_of_tcenv1 tc
  | _ -> raise TTC.NoMatch

let t_elim_exists tc = t_elim_r [t_elim_exists_r] tc

(* -------------------------------------------------------------------- *)
let t_elim_default_r = [
  t_elim_false_r;
  t_elim_and_r;
  t_elim_or_r;
  t_elim_iff_r;
  t_elim_if_r;
  t_elim_eq_tuple_r;
  t_elim_exists_r;
]

let t_elim ?reduce tc = t_elim_r ?reduce t_elim_default_r tc

(* -------------------------------------------------------------------- *)
let t_elim_hyp h tc =
  (* FIXME: exception? *)
  let f  = LDecl.lookup_hyp_by_id h (FApi.tc1_hyps tc) in
  let pt = { pt_head = PTLocal h; pt_args = []; } in
  FApi.t_seq (t_cutdef pt f) t_elim tc

(* -------------------------------------------------------------------- *)
(* FIXME: document this function ! *)
let t_elimT_form (ind : proofterm) ?(sk = 0) (f : form) (tc : tcenv1) =
  let tc    = FApi.tcenv_of_tcenv1 tc in
  let _, ax =
    snd (RApi.to_pure (fun tc -> LowApply.check `Elim ind (`Tc tc)) tc) in

  let hyps, concl = FApi.tc_flat tc in
  let env = LDecl.toenv hyps in

  let rec skip i a f =
    match i, EcFol.sform_of_form f with
    | Some i, _ when i <= 0 -> (a, f)
    | Some i, SFimp (_, f2) -> skip (Some (i-1)) (a+1) f2
    | None  , SFimp (_, f2) -> skip None (a+1) f2
    | Some _, _ -> raise InvalidGoalShape
    | None  , _ -> (a, f)
  in

  let (pr, prty, ax) =
    match sform_of_form ax with
    | SFquant (Lforall, (pr, GTty prty), lazy ax) -> (pr, prty, ax)
    | _ -> raise InvalidGoalShape
  in

  if not (EqTest.for_type env prty (tfun f.f_ty tbool)) then
    raise InvalidGoalShape;

  let (aa1, ax) = skip None 0 ax in

  let (x, _xty, ax) =
    match sform_of_form ax with
    | SFquant (Lforall, (x, GTty xty), lazy ax) -> (x, xty, ax)
    | _ -> raise InvalidGoalShape
  in

  let (aa2, ax) =
    let rec doit ax aa =
      match TTC.destruct_product hyps ax with
      | Some (`Imp (f1, f2)) when Mid.mem pr f1.f_fv -> doit f2 (aa+1)
      | _ -> (aa, ax)
    in
      doit ax 0
  in

  let pf =
    let (_, concl) = skip (Some sk) 0 concl in
    let (z, concl) = EcProofTerm.pattern_form ~name:(EcIdent.name x) hyps ~ptn:f concl in
      Fsubst.f_subst_local pr (f_lambda [(z, GTty f.f_ty)] concl) ax
  in

  let pf_inst = Fsubst.f_subst_local x f pf in

  let (aa3, sk) =
    let rec doit pf_inst (aa, sk) =
      if   EcReduction.is_conv hyps pf_inst concl
      then (aa, sk)
      else
        match TTC.destruct_product hyps pf_inst with
        | Some (`Imp (_, f2)) -> doit f2 (aa+1, sk+1)
        | _ -> raise InvalidGoalShape
    in
      doit pf_inst (0, sk)
  in

  let pf   = f_lambda [(x, GTty f.f_ty)] (snd (skip (Some sk) 0 pf)) in
  let args =
    (PAFormula pf :: (List.create aa1 (PASub None)) @
     PAFormula  f :: (List.create (aa2+aa3) (PASub None))) in
  let pt   = { ind with pt_args = ind.pt_args @ args; } in

  (* FIXME: put first goal last *)
  FApi.t_focus (t_apply pt) tc

(* -------------------------------------------------------------------- *)
let t_elimT_form_global p ?(typ = []) ?sk f tc =
  let pt = { pt_head = PTGlobal (p, typ); pt_args = []; } in
  t_elimT_form pt f ?sk tc

(* -------------------------------------------------------------------- *)
let gen_tuple_elim (tys : ty list) : form =
  let var i ty =
    let var = EcIdent.create (Printf.sprintf "%s%d" "x" (i+1)) in
    (var, f_local var ty) in

  let tty  = ttuple tys in
  let p    = EcIdent.create "p" in
  let fp   = f_local p (tfun tty tbool) in
  let t    = EcIdent.create "t" in
  let ft   = f_local t tty in
  let vars = List.mapi var tys in
  let tf   = f_tuple (List.map snd vars) in

  let indh = f_app fp [tf] tbool in
  let indh = f_imp (f_eq ft tf) indh in
  let indh = f_forall (List.map (snd_map (fun f -> GTty f.f_ty)) vars) indh in

  let concl = f_forall [] (f_imp indh (f_app fp [ft] tbool)) in
  let concl = f_forall [t, GTty tty] concl in
  let concl = f_forall [p, GTty (tfun tty tbool)] concl in

  concl

(* -------------------------------------------------------------------- *)
let pf_gen_tuple_elim tys hyps pe =
  let fp = gen_tuple_elim tys in
  FApi.newfact pe (VExtern (`TupleElim tys, [])) hyps fp

(* -------------------------------------------------------------------- *)
let t_elimT_ind mode (tc : tcenv1) =
  let env, hyps, concl = FApi.tc1_eflat tc in

  match sform_of_form concl with
  | SFquant (Lforall, (x, GTty ty), _) -> begin
      match EcEnv.Ty.scheme_of_ty mode ty env with
      | None -> raise InvalidGoalShape
      | Some (p, typ) ->
          let id   = LDecl.fresh_id hyps (EcIdent.name x) in
          let elim = t_elimT_form_global p ~typ (f_local id ty) in

            FApi.t_seqs
              [t_intros_i_seq ~clear:true [id] elim;
               t_simplify_with_info EcReduction.beta_red]
              tc
    end

  | _ -> raise InvalidGoalShape

(* -------------------------------------------------------------------- *)
let t_case fp tc = t_elimT_form_global EcCoreLib.p_case_eq_bool fp tc

(* -------------------------------------------------------------------- *)
let t_split (tc : tcenv1) =
  let t_split_r (fp : form) (tc : tcenv1) =
    let hyps, concl = FApi.tc1_flat tc in

    match sform_of_form fp with
    | SFtrue ->
        t_true tc
    | SFand (b, (f1, f2)) ->
        t_and_intro_s b (f1, f2) tc
    | SFiff (f1, f2) ->
        t_iff_intro_s (f1, f2) tc
    | SFeq (f1, f2) when EcReduction.is_conv hyps f1 f2 ->
        t_reflex_s f1 tc
    | SFeq (f1, f2) when is_tuple f1 && is_tuple f2 ->
        let fs = List.combine (destr_tuple f1) (destr_tuple f2) in
        t_tuple_intro_s fs tc
    | SFif (cond, _, _) ->
        (* FIXME: simplify goal *)
        let tc = if f_equal concl fp then tc else t_change fp tc in
        let tc = t_case cond tc in
          tc
    | _ -> raise TTC.NoMatch
  in
    TTC.t_lazy_match t_split_r tc

(* -------------------------------------------------------------------- *)
type rwspec = [`LtoR|`RtoL] * ptnpos option

(* -------------------------------------------------------------------- *)
let t_rewrite (pt : proofterm) (s, pos) (tc : tcenv1) =
  let tc = RApi.rtcenv_of_tcenv1 tc in
  let (env, hyps, concl) = RApi.tc_eflat tc in
  let (pt, ax) = LowApply.check `Elim pt (`Tc tc) in

  let (left, right) =
    match sform_of_form ax with
    | SFeq  (f1, f2) -> (f1, f2)
    | SFiff (f1, f2) -> (f1, f2)

    | _ when s = `LtoR && ER.EqTest.for_type env ax.f_ty tbool ->
        (ax, f_true)

    | _ -> raise InvalidProofTerm
  in

  let (left, right) =
    match s with
    | `LtoR -> (left , right)
    | `RtoL -> (right, left )
  in

  let change f =
    if not (EcReduction.is_conv hyps f left) then
      raise InvalidGoalShape;
    right
  in

  let newconcl =
    let pos =
      pos |> ofdfl (fun () -> FPosition.select_form hyps None left concl) in

    try  FPosition.map pos change concl
    with InvalidPosition -> raise InvalidGoalShape
  in

  let hd   = RApi.newgoal tc newconcl in
  let rwpt = { rpt_proof = pt; rpt_occrs = pos; } in

  RApi.close tc (VRewrite (hd, rwpt));
  RApi.tcenv_of_rtcenv tc

(* -------------------------------------------------------------------- *)
let t_rewrite_hyp (id : EcIdent.t) pos (tc : tcenv1) =
  let pt = { pt_head = PTLocal id; pt_args = []; } in
  t_rewrite pt pos tc

(* -------------------------------------------------------------------- *)
type vsubst = [
  | `Local of EcIdent.t
  | `Glob  of EcPath.mpath * EcMemory.memory
  | `PVar  of EcTypes.prog_var * EcMemory.memory
]

(* -------------------------------------------------------------------- *)
type subst_kind = {
  sk_local : bool;
  sk_pvar  : bool;
  sk_glob  : bool;
}

let  full_subst_kind = { sk_local = true ; sk_pvar  = true ; sk_glob  = true ; }
let empty_subst_kind = { sk_local = false; sk_pvar  = false; sk_glob  = false; }

(* -------------------------------------------------------------------- *)
module LowSubst = struct
  (* ------------------------------------------------------------------ *)
  let default_subst_kind = full_subst_kind

  (* ------------------------------------------------------------------ *)
  let is_member_for_subst ?kind env var f =
    let kind = odfl default_subst_kind kind in

    match f.f_node, var with
    (* Substitution of logical variables *)
    | Flocal x, None when kind.sk_local ->
        Some (`Local x)

    | Flocal x, Some (`Local y) when kind.sk_local && id_equal x y ->
        Some (`Local x)

    (* Substitution of program variables *)
    | Fpvar (pv, m), None when kind.sk_pvar -> Some (`PVar (pv, m))
    | Fpvar (pv, m), Some (`PVar (pv', m')) when kind.sk_pvar ->
        let pv  = EcEnv.NormMp.norm_pvar env pv  in
        let pv' = EcEnv.NormMp.norm_pvar env pv' in

        if   EcTypes.pv_equal pv pv' && EcMemory.mem_equal m m'
        then Some (`PVar (pv, m))
        else None

    (* Substitution of globs *)
    | Fglob (mp, m), None when kind.sk_glob -> Some (`Glob (mp, m))
    | Fglob (mp, m), Some (`Glob (mp', m')) when kind.sk_glob ->
        let gl  = EcEnv.NormMp.norm_glob env m  mp  in
        let gl' = EcEnv.NormMp.norm_glob env m' mp' in

        if   EcFol.f_equal gl gl'
        then Some (`Glob (mp, m))
        else None

    | _, _ -> None

  (* ------------------------------------------------------------------ *)
  let is_eq_for_subst ?kind hyps var (f1, f2) =
    let env = LDecl.toenv hyps in

    let var =
      match is_member_for_subst ?kind env var f1 with
      | Some var -> Some (var, f2)
      | None ->
        match is_member_for_subst ?kind env var f2 with
        | Some var -> Some (var, f1)
        | None -> None
    in

    match var with
    | None -> None

    (* Substitution of logical variables *)
    | Some ((`Local x, f) as aout) ->
      let f = simplify { no_red with delta_h = None } hyps f in
      if Mid.mem x f.f_fv then None else Some aout

    (* Substitution of program variables *)
    | Some ((`PVar (pv, m), f) as aout) ->
        let f  = simplify { no_red with delta_h = None } hyps f in
        let fv = EcPV.PV.fv env m f in
        if EcPV.PV.mem_pv env pv fv then None else Some aout

    (* Substitution of globs *)
    | Some ((`Glob (mp, m), f) as aout) ->
        let f  = simplify { no_red with delta_h = None } hyps f in
        let fv = EcPV.PV.fv env m f in
        if EcPV.PV.mem_glob env mp fv then None else Some aout

  (* ------------------------------------------------------------------ *)
  let build_subst env var f =
    match var with
    | `Local x ->
        let subst = Fsubst.f_subst_local x f in
        let check tg = Mid.mem x tg.f_fv in
        (subst, check)

    | `PVar (pv, m) ->
        let subst = EcPV.PVM.add env pv m f EcPV.PVM.empty in
        let check _tg = true in
        (EcPV.PVM.subst env subst, check)

    | `Glob (mp, m) ->
        let subst = EcPV.PVM.add_glob env mp m f EcPV.PVM.empty in
        let check _tg = true in
        (EcPV.PVM.subst env subst, check)
end

(* -------------------------------------------------------------------- *)
let t_subst ?kind ?var ?eqid (tc : tcenv1) =
  let env, hyps, concl = FApi.tc1_eflat tc in

  let subst1 (subst, check) moved (id, lk) =
    let check tg =
      check tg || not (Mid.disjoint (fun _ _ _ -> false) tg.f_fv moved) in

    match lk with
    | LD_var (_ty, None) ->
        `Pre (id, lk)

    | LD_var (ty, Some body) ->
        if   check body
        then `Post (id, LD_var (ty, Some (subst body)))
        else `Pre  (id, LD_var (ty, Some body))

    | LD_hyp hform ->
        if   check hform
        then `Post (id, LD_hyp (subst hform))
        else `Pre  (id, LD_hyp hform)

    | LD_mem    _ -> `Pre (id, lk)
    | LD_modty  _ -> `Pre (id, lk)
    | LD_abs_st _ -> `Pre (id, lk)
  in

  let eqs =
    eqid
      |> omap  (fun id -> [id, LD_hyp (LDecl.lookup_hyp_by_id id hyps)])
      |> ofdfl (fun () -> (LDecl.tohyps hyps).h_local)
  in

  let try1 eq =
    match eq with
    | id, LD_hyp f when is_eq_or_iff f -> begin
        let dosubst (var, f) =
          let subst, check = LowSubst.build_subst env var f in

          let post, (id', _), pre =
            try  List.find_split (id_equal id |- fst) (LDecl.tohyps hyps).h_local
            with Not_found -> assert false
          in

          assert (id_equal id id');

          let pre, hpost, _ =
            List.fold_right
              (fun h (pre, hpost, moved) ->
                assert (not (id_equal (fst h) id));
                match h, var with
                | (x, _), _ ->
                  match subst1 (subst, check) moved h with
                  | `Pre  (id, lk) -> ((id, lk) :: pre, hpost, moved)
                  | `Post (id, lk) ->
                      match lk with
                      | LD_var (_, _) -> (pre, (id, lk) :: hpost, Sid.add x moved)
                      | _             -> (pre, (id, lk) :: hpost, moved))
              pre ([], [], Sid.empty) in

          let post =
            List.fold_right
              (fun h post ->
                assert (not (id_equal (fst h) id));
                match subst1 (subst, check) Sid.empty h with
                | `Pre (id, lk) | `Post (id, lk) -> (id, lk) :: post)
              post [] in

          let concl' = subst concl in
          let hyps'  = hpost @ post @ pre in
          let hyps'  =
            LDecl.init (LDecl.baseenv hyps)
              ~locals:hyps' (LDecl.tohyps hyps).h_tvar in

          let clear  =
            match var with
            | `Local x -> begin
              match LDecl.lookup_by_id x hyps with
              | LD_var (_, None) -> t_clear x
              | _ -> t_id
            end
            | _ -> t_id
          in

          FApi.t_focus clear (FApi.xmutate1_hyps tc `Subst [hyps', concl'])
        in

        try
          LowSubst.is_eq_for_subst ?kind hyps var (destr_eq_or_iff f) |> omap dosubst
        with EcPV.MemoryClash -> None
    end

    | _ -> None
  in

  try  List.find_map try1 eqs
  with Not_found -> raise InvalidGoalShape

(* -------------------------------------------------------------------- *)
type pgoptions = EcParsetree.ppgoptions

let default_progress_options = {
  ppgo_split = true;
  ppgo_solve = true;
  ppgo_subst = true;
}

let t_progress ?options (tt : FApi.backward) (tc : tcenv1) =
  let options = odfl default_progress_options options in
  let tt = if options.ppgo_solve then FApi.t_or (t_assumption `Alpha) tt else tt in

  let t_progress_subst ?eqid =
    let sk1 = { empty_subst_kind with sk_local = true ; } in
    let sk2 = {  full_subst_kind with sk_local = false; } in
    FApi.t_or (t_subst ~kind:sk1 ?eqid) (t_subst ~kind:sk2 ?eqid)
  in

  (* Entry of progress: simplify goal, and chain with progress *)
  let rec entry tc = FApi.t_seq (t_simplify ~delta:false) aux0 tc

  (* Progress (level 0): try to apply use tactic, chain with level 1. *)
  and aux0 tc = FApi.t_seq (FApi.t_try tt) aux1 tc

  (* Progress (level 1): intro/elim top-level assumption *)
  and aux1 tc =
    let hyps, concl = FApi.tc1_flat tc in

    match sform_of_form concl with
    | SFquant (Lforall, _, _) ->
      let bd  = fst (destr_forall concl) in
      let ids = List.map (EcIdent.name |- fst) bd in
      let ids = LDecl.fresh_ids hyps ids in
      FApi.t_seq (t_intros_i ids) aux0 tc

    | SFlet (LTuple fs, f1, _) ->
      let tys    = List.map snd fs in
      let tc, hd = FApi.bwd1_of_fwd (pf_gen_tuple_elim tys hyps) tc in
      let pt     = { pt_head = PTHandle hd; pt_args = []; } in
      FApi.t_seq (t_elimT_form pt f1) aux0 tc

    | SFimp (_, _) -> begin
      let id = LDecl.fresh_id hyps "H" in

      match t_intros_i_seq [id] tt tc with
      | tc when FApi.tc_done tc -> tc
      | _ ->
          let iffail tc =
            let ts =
              if   options.ppgo_subst
              then FApi.t_try (t_progress_subst ~eqid:id)
              else t_id
            in
              t_intros_i_seq [id] (FApi.t_seq ts entry) tc

          and elims = [
            t_elim_false_r;
            t_elim_exists_r;
            t_elim_and_r;
            t_elim_eq_tuple_r] in

          FApi.t_switch (t_elim_r ~reduce:false elims) ~ifok:aux0 ~iffail tc
    end

    | _ when options.ppgo_split ->
        FApi.t_try (FApi.t_seq t_split aux0) tc

    | _ -> t_id tc

  in entry tc

(* -------------------------------------------------------------------- *)
let t_logic_trivial (tc : tcenv1) =
  let seqs = [
    FApi.t_try (t_assumption `Conv);
    t_progress t_id;
    FApi.t_try (t_assumption `Conv);
    t_fail
  ]

  in
    FApi.t_internal (FApi.t_try (FApi.t_seqs seqs)) tc

(* -------------------------------------------------------------------- *)
let t_trivial (ott : FApi.backward option) (tc : tcenv1) =
  let tryassum  = FApi.t_try (t_assumption `Conv) in
  let tprogress = t_progress t_id in
  let subtc     = ott |> odfl t_id in
  let seqs      = [tryassum; tprogress; tryassum; subtc; t_logic_trivial; t_fail] in

  FApi.t_internal (FApi.t_try (FApi.t_seqs seqs)) tc

(* -------------------------------------------------------------------- *)
let t_congr (f1, f2) (args, ty) tc =
  let rec doit args ty tc =
    match args with
    | [] -> t_id tc

    | (a1, a2) :: args->
        let aty  = a1.f_ty in
        let m1   = f_app f1 (List.rev_map fst args) (tfun aty ty) in
        let m2   = f_app f2 (List.rev_map snd args) (tfun aty ty) in
        let tcgr = t_apply_s EcCoreLib.p_fcongr [ty; aty] ~args:[m2; a1; a2] ~sk:1 in

        let tsub tc =
          let fx   = EcIdent.create "f" in
          let fty  = tfun aty ty in
          let body = f_app (f_local fx fty) [a1] ty in
          let lam  = EcFol.f_lambda [(fx, GTty fty)] body in
            FApi.t_sub
              [doit args fty]
              (t_apply_s EcCoreLib.p_fcongr [ty; fty] ~args:[lam; m1; m2] ~sk:1 tc)
        in
          FApi.t_sub
            [tsub; tcgr]
            (t_transitivity (EcFol.f_app m2 [a1] ty) tc)
  in
  doit (List.rev args) ty tc

(* -------------------------------------------------------------------- *)
let t_smt ~strict hints pi tc =
  let error () =
    tc_error !!tc ~catchable:(not strict) "cannot prove goal" in

  let (_, concl) as goal = FApi.tc1_flat tc in

  match concl.f_node with
  | FequivF   _  | FequivS   _
  | FhoareF   _  | FhoareS   _
  | FbdHoareF _  | FbdHoareS _ -> error ()

  | _ ->
      try
        if EcEnv.check_goal hints pi goal then
          FApi.xmutate1 tc `Smt []
        else error ()
      with EcWhy3.CannotTranslate _ ->
        error ()