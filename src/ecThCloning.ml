(* --------------------------------------------------------------------
 * Copyright (c) - 2012-2014 - IMDEA Software Institute and INRIA
 * Distributed under the terms of the CeCILL-C license
 * -------------------------------------------------------------------- *)

(* ------------------------------------------------------------------ *)
open EcUtils
open EcSymbols
open EcLocation
open EcParsetree
open EcDecl
open EcModules
open EcTheory

module Mp = EcPath.Mp

(* ------------------------------------------------------------------ *)
type ovkind =
| OVK_Type
| OVK_Operator
| OVK_Predicate
| OVK_Theory
| OVK_Lemma

type clone_error =
| CE_DupOverride    of ovkind * qsymbol
| CE_UnkOverride    of ovkind * qsymbol
| CE_CrtOverride    of ovkind * qsymbol
| CE_TypeArgMism    of ovkind * qsymbol
| CE_OpIncompatible of qsymbol
| CE_PrIncompatible of qsymbol

exception CloneError of EcEnv.env * clone_error

let clone_error env error =
  raise (CloneError (env, error))

(* -------------------------------------------------------------------- *)
let string_of_ovkind = function
  | OVK_Type      -> "type"
  | OVK_Operator  -> "operator"
  | OVK_Predicate -> "predicate"
  | OVK_Theory    -> "theory"
  | OVK_Lemma     -> "lemma/axiom"

(* -------------------------------------------------------------------- *)
type axclone = {
  axc_axiom : symbol * EcDecl.axiom;
  axc_path  : EcPath.path;
  axc_env   : EcEnv.env;
  axc_tac   : EcParsetree.ptactic_core option;
}

(* -------------------------------------------------------------------- *)
let pp_clone_error fmt _env error =
  let msg x = Format.fprintf fmt x in

  match error with
  | CE_DupOverride (kd, x) ->
      msg "the %s `%s' is instantiate twice"
        (string_of_ovkind kd) (string_of_qsymbol x)

  | CE_UnkOverride (kd, x) ->
      msg "unknown %s `%s'"
        (string_of_ovkind kd) (string_of_qsymbol x)

  | CE_CrtOverride (kd, x) ->
      msg "cannot instantiate the _concrete_ %s `%s'"
        (string_of_ovkind kd) (string_of_qsymbol x)

  | CE_TypeArgMism (kd, x) ->
      msg "type argument mismatch for %s `%s'"
        (string_of_ovkind kd) (string_of_qsymbol x)

  | CE_OpIncompatible x ->
      msg "operator `%s' body is not compatible with its declaration"
        (string_of_qsymbol x)

  | CE_PrIncompatible x ->
      msg "predicate `%s' body is not compatible with its declaration"
        (string_of_qsymbol x)

let () =
  let pp fmt exn =
    match exn with
    | CloneError (env, e) -> pp_clone_error fmt env e
    | _ -> raise exn
  in
    EcPException.register pp

(* ------------------------------------------------------------------ *)
type evclone = {
  evc_types  : (ty_override located) Msym.t;
  evc_ops    : (op_override located) Msym.t;
  evc_preds  : (pr_override located) Msym.t;
  evc_lemmas : evlemma;
  evc_ths    : evclone Msym.t;
}

and evlemma = {
  ev_global  : (ptactic_core option) option;
  ev_bynames : (ptactic_core option) Msym.t;
}

let evc_empty =
  let evl = { ev_global = None; ev_bynames = Msym.empty; } in
    { evc_types  = Msym.empty;
      evc_ops    = Msym.empty;
      evc_preds  = Msym.empty;
      evc_lemmas = evl;
      evc_ths    = Msym.empty; }

let rec evc_update (upt : evclone -> evclone) (nm : symbol list) (evc : evclone) =
  match nm with
  | []      -> upt evc
  | x :: nm ->
      let ths =
        Msym.change
          (fun sub -> Some (evc_update upt nm (odfl evc_empty sub)))
          x evc.evc_ths
      in
        { evc with evc_ths = ths }

let rec evc_get (nm : symbol list) (evc : evclone) =
  match nm with
  | []      -> Some evc
  | x :: nm ->
      match Msym.find_opt x evc.evc_ths with
      | None     -> None
      | Some evc -> evc_get nm evc

(* -------------------------------------------------------------------- *)
exception Incompatible

let ty_compatible env (rtyvars, rty) (ntyvars, nty) =
  if List.length rtyvars <> List.length ntyvars then
    raise Incompatible;
  let s =
    EcIdent.Mid.of_list
      (List.map2
         (fun a1 a2 -> (a1, EcTypes.tvar a2))
         rtyvars ntyvars)
  in

  let nty = EcTypes.Tvar.subst s nty in
    if not (EcReduction.EqTest.for_type env rty nty) then
      raise Incompatible

let ty_compatible env t1 t2 =
  try  ty_compatible env t1 t2; true
  with Incompatible -> false

(* -------------------------------------------------------------------- *)
let clone (scenv : EcEnv.env) (thcl : theory_cloning) =
  let cpath = EcEnv.root scenv in

  let opath, oth = EcEnv.Theory.lookup (unloc thcl.pthc_base) scenv in
  let name  = odfl (EcPath.basename opath) (thcl.pthc_name |> omap unloc) in
  let npath = EcPath.pqname cpath name in
  let subst = EcSubst.add_path EcSubst.empty opath npath in

  let (genproofs, ovrds) =
    let rec do1 (proofs, evc) ({ pl_loc = l; pl_desc = ((nm, x) as name) }, ovrd) =
      let xpath = EcPath.pappend opath (EcPath.fromqsymbol name) in

        match ovrd with
        | PTHO_Type ((tyargs, _, _) as tyd) -> begin
            match EcEnv.Ty.by_path_opt xpath scenv with
            | None ->
                clone_error scenv (CE_UnkOverride (OVK_Type, name));
            | Some { EcDecl.tyd_type = `Concrete _ } ->
                clone_error scenv (CE_CrtOverride (OVK_Type, name));
            | Some refty ->
                if List.length refty.tyd_params <> List.length tyargs then
                  clone_error scenv (CE_TypeArgMism (OVK_Type, name))
          end;
          let evc =
            evc_update
              (fun evc ->
                if Msym.mem x evc.evc_types then
                  clone_error scenv (CE_DupOverride (OVK_Type, name));
                { evc with evc_types = Msym.add x (mk_loc l tyd) evc.evc_types })
              nm evc
          in
            (proofs, evc)

        | PTHO_Op opd -> begin
            match EcEnv.Op.by_path_opt xpath scenv with
            | None
            | Some { op_kind = OB_pred _ } ->
                clone_error scenv (CE_UnkOverride (OVK_Operator, name));
            | Some { op_kind = OB_oper (Some _) } ->
                clone_error scenv (CE_CrtOverride (OVK_Operator, name));
            | _ -> ()
          end;
          let evc =
            evc_update
              (fun evc ->
                if Msym.mem x evc.evc_ops then
                  clone_error scenv (CE_DupOverride (OVK_Operator, name));
                { evc with evc_ops = Msym.add x (mk_loc l opd) evc.evc_ops })
              nm evc
          in
            (proofs, evc)

        | PTHO_Pred pr -> begin
            match EcEnv.Op.by_path_opt xpath scenv with
            | None
            | Some { op_kind = OB_oper _ } ->
                clone_error scenv (CE_UnkOverride (OVK_Predicate, name));
            | Some { op_kind = OB_pred (Some _) } ->
                clone_error scenv (CE_CrtOverride (OVK_Predicate, name));
            | _ -> ()
          end;
          let evc =
            evc_update
              (fun evc ->
                if Msym.mem x evc.evc_preds then
                  clone_error scenv (CE_DupOverride (OVK_Predicate, name));
                { evc with evc_preds = Msym.add x (mk_loc l pr) evc.evc_preds })
              nm evc
          in
            (proofs, evc)

        | PTHO_Theory xsth ->
            let dth =
              match EcEnv.Theory.by_path_opt xpath scenv with
              | None -> clone_error scenv (CE_UnkOverride (OVK_Theory, name))
              | Some th -> th
            in

            let sp =
              match EcEnv.Theory.lookup_opt (unloc xsth) scenv with
              | None -> clone_error scenv (CE_UnkOverride (OVK_Theory, unloc xsth))
              | Some (sp, _) -> sp
            in

            let xsth = let xsth = EcPath.toqsymbol sp in (fst xsth @ [snd xsth]) in
            let xdth = nm @ [x] in

            let rec doit prefix (proofs, evc) dth =
              match dth with
              | CTh_type (x, ({ tyd_type = `Abstract _ } as otyd)) ->
                  (* FIXME: TC HOOK *)
                  let params = List.map (EcIdent.name |- fst) otyd.tyd_params in
                  let params = List.map (mk_loc l) params in
                  let tyd    =
                    match List.map (fun a -> mk_loc l (PTvar a)) params with
                    | [] -> PTnamed (mk_loc l (xsth @ prefix, x))
                    | pt -> PTapp   (mk_loc l (xsth @ prefix, x), pt)
                  in
                  let tyd  = mk_loc l tyd in
                  let ovrd = PTHO_Type (params, tyd, `Alias) in
                    do1 (proofs, evc) (mk_loc l (xdth @ prefix, x), ovrd)

              | CTh_operator (x, ({ op_kind = OB_oper None } as oopd)) ->
                  (* FIXME: TC HOOK *)
                  let params = List.map (EcIdent.name |- fst) oopd.op_tparams in
                  let params = List.map (mk_loc l) params in
                  let ovrd   = {
                    opov_tyvars = Some params;
                    opov_args   = [];
                    opov_retty  = mk_loc l PTunivar;
                    opov_body   =
                      let sym = mk_loc l (xsth @ prefix, x) in
                      let tya = List.map (fun a -> mk_loc l (PTvar a)) params in
                        mk_loc l (PEident (sym, Some (mk_loc l (TVIunamed tya))));
                  } in
                    do1 (proofs, evc) (mk_loc l (xdth @ prefix, x), PTHO_Op (ovrd, `Alias))

              | CTh_operator (x, ({ op_kind = OB_pred None } as oprd)) ->
                  (* FIXME: TC HOOK *)
                  let params = List.map (EcIdent.name |- fst) oprd.op_tparams in
                  let params = List.map (mk_loc l) params in
                  let ovrd   = {
                    prov_tyvars = Some params;
                    prov_args   = [];
                    prov_body   =
                      let sym = mk_loc l (xsth @ prefix, x) in
                      let tya = List.map (fun a -> mk_loc l (PTvar a)) params in
                        mk_loc l (PFident (sym, Some (mk_loc l (TVIunamed tya))));
                  } in
                    do1 (proofs, evc) (mk_loc l (xdth @ prefix, x), PTHO_Pred ovrd)

              | CTh_axiom (x, ({ ax_spec = Some _; ax_kind = `Axiom; } as ax)) ->
                  (* FIXME: TC HOOK *)
                  let params = List.map (EcIdent.name |- fst) ax.ax_tparams in
                  let params = List.map (mk_loc l) params in
                  let params = List.map (fun a -> mk_loc l (PTvar a)) params in

                  let tc = FPNamed (mk_loc l (xsth @ prefix, x),
                                    Some (mk_loc l (TVIunamed params))) in
                  let tc = Papply (`Apply ([`Explicit, { fp_kind = tc; fp_args = []}], `Exact)) in
                  let tc = mk_loc l (Plogic tc) in
                  let pr = { pthp_mode   = `Named (mk_loc l (xdth @ prefix, x));
                             pthp_tactic = Some tc }
                  in
                    (pr :: proofs, evc)

              | CTh_theory (x, dth) ->
                  List.fold_left (doit (prefix @ [x])) (proofs, evc) dth.cth_struct

              | CTh_export _ ->
                  (proofs, evc)

              | _ -> clone_error scenv (CE_CrtOverride (OVK_Theory, name))
            in
              List.fold_left (doit []) (proofs, evc) dth.cth_struct
    in
      List.fold_left do1 ([], evc_empty) thcl.pthc_ext
  in

  let ovrds =
    let do1 evc prf =
      let xpath name = EcPath.pappend opath (EcPath.fromqsymbol name) in

      match prf.pthp_mode with
      | `All name -> begin
          let (name, dname) =
            match name with
            | None -> ([], ([], "<current>"))
            | Some name ->
                match EcEnv.Theory.by_path_opt (xpath (unloc name)) scenv with
                | None   -> clone_error scenv (CE_UnkOverride (OVK_Theory, unloc name))
                | Some _ -> let (nm, name) = unloc name in (nm @ [name], (nm, name))
          in

          let update1 evc =
            match evc.evc_lemmas.ev_global with
            | Some (Some _) ->
                clone_error scenv (CE_DupOverride (OVK_Theory, dname))
            | _ ->
                let evl = evc.evc_lemmas in
                let evl = { evl with ev_global = Some prf.pthp_tactic } in
                  { evc with evc_lemmas = evl }
          in
            evc_update update1 name evc
      end

      | `Named name -> begin
          let name = unloc name in

          match EcEnv.Ax.by_path_opt (xpath name) scenv with
          | None -> clone_error scenv (CE_UnkOverride (OVK_Lemma, name))
          | Some ax ->

              if ax.ax_kind <> `Axiom || ax.ax_spec = None then
                clone_error scenv (CE_CrtOverride (OVK_Lemma, name));

              let update1 evc =
                match Msym.find_opt (snd name) evc.evc_lemmas.ev_bynames with
                | Some (Some _) ->
                    clone_error scenv (CE_DupOverride (OVK_Lemma, name))
                | _ ->
                    let map = evc.evc_lemmas.ev_bynames in
                    let map = Msym.add (snd name) prf.pthp_tactic map in
                    let evl = { evc.evc_lemmas with ev_bynames = map } in
                      { evc with evc_lemmas = evl }
              in
                evc_update update1 (fst name) evc
      end
    in
      List.fold_left do1 ovrds (genproofs @ thcl.pthc_prf)
  in

  let (proofs, nth) =
    let rec ovr1 prefix ovrds (subst, ops, proofs, scenv) item =
      let xpath x = EcPath.pappend opath (EcPath.fromqsymbol (prefix, x)) in

      match item with
      | CTh_type (x, otyd) -> begin
          match Msym.find_opt x ovrds.evc_types with
          | None ->
              let otyd = EcSubst.subst_tydecl subst otyd in
                (subst, ops, proofs, EcEnv.Ty.bind x otyd scenv)

          | Some { pl_desc = (nargs, ntyd, mode) } -> begin
            (* Already checked:
             *   1. type is abstract
             *   2. type argument count are equal *)
              (* FIXME: TC HOOK *)
              let nargs = List.map2
                            (fun (_, tc) x -> (EcIdent.create (unloc x), tc))
                            otyd.tyd_params nargs in
              let ue    = EcUnify.UniEnv.create (Some nargs) in
              let ntyd  = EcTyping.transty EcTyping.tp_tydecl scenv ue ntyd in

              match mode with
              | `Alias ->
                  let binding =
                    { tyd_params = nargs;
                      tyd_type   = `Concrete ntyd; }
                  in
                    (subst, ops, proofs, EcEnv.Ty.bind x binding scenv)

              | `Inline ->
                  let subst =
                    (* FIXME: TC HOOK *)
                    EcSubst.add_tydef subst (xpath x) (List.map fst nargs, ntyd)
                  in
                    (subst, ops, proofs, scenv)
          end
      end

      | CTh_operator (x, ({ op_kind = OB_oper None } as oopd)) -> begin
          match Msym.find_opt x ovrds.evc_ops with
          | None ->
              (subst, ops, proofs, EcEnv.Op.bind x (EcSubst.subst_op subst oopd) scenv)

          | Some { pl_desc = (opov, opmode); pl_loc = loc; } ->
              let (reftyvars, refty) =
                let refop = EcEnv.Op.by_path (xpath x) scenv in
                let refop = EcSubst.subst_op subst refop in
                  (refop.op_tparams, refop.op_ty)
              in

              let (newop, subst, alias) =
                let tp = opov.opov_tyvars |> omap (List.map (fun tv -> (tv, []))) in
                let ue = EcTyping.transtyvars scenv (loc, tp) in
                let tp = EcTyping.tp_relax in
                let (ty, body) =
                  let env     = scenv in
                  let codom   = EcTyping.transty tp env ue opov.opov_retty in
                  let env, xs = EcTyping.transbinding env ue opov.opov_args in
                  let body    = EcTyping.transexpcast env `InOp ue codom opov.opov_body in
                  let lam     = EcTypes.e_lam xs body in
                    (lam.EcTypes.e_ty, lam)
                in

                let uni     = EcTypes.Tuni.offun (EcUnify.UniEnv.close ue) in
                let body    = body |> EcTypes.e_mapty uni in
                let ty      = uni ty in
                let tparams = EcUnify.UniEnv.tparams ue in
                let newop   = mk_op tparams ty (Some (OP_Plain body)) in
                  match opmode with
                  | `Alias  ->
                      (newop, subst, true)

                  (* FIXME: TC HOOK *)
                  | `Inline ->
                      let subst =
                        EcSubst.add_opdef subst (xpath x)  (List.map fst tparams, body)
                      in
                        (newop, subst, false)
            in

            let (newtyvars, newty) = (newop.op_tparams, newop.op_ty) in
              (* FIXME: TC HOOK *)
              if not (ty_compatible scenv
                        (List.map fst reftyvars, refty)
                        (List.map fst newtyvars, newty))
              then
                clone_error scenv (CE_OpIncompatible (prefix, x));
              let ops = Mp.add (EcPath.fromqsymbol (prefix, x)) (newop, alias) ops in
                (subst, ops, proofs, if alias then EcEnv.Op.bind x newop scenv else scenv)
          end

      | CTh_operator (x, ({ op_kind = OB_pred None} as oopr)) -> begin
          match Msym.find_opt x ovrds.evc_preds with
          | None ->
              (subst, ops, proofs, EcEnv.Op.bind x (EcSubst.subst_op subst oopr) scenv)

          | Some { pl_desc = prov; pl_loc = loc; } ->
              let (reftyvars, refty) =
                let refpr = EcEnv.Op.by_path (xpath x) scenv in
                let refpr = EcSubst.subst_op subst refpr in
                  (refpr.op_tparams, refpr.op_ty)
              in

              let newpr =
                 let tp = prov.prov_tyvars |> omap (List.map (fun tv -> (tv, []))) in
                 let ue = EcTyping.transtyvars scenv (loc, tp) in
                 let body =
                   let env     = scenv in
                   let env, xs = EcTyping.transbinding env ue prov.prov_args in
                   let body    = EcTyping.trans_form_opt env ue prov.prov_body None in
                   let xs      = List.map (fun (x, ty) -> x, EcFol.GTty ty) xs in
                   let lam     = EcFol.f_lambda xs body in
                     lam
                 in

                 if reftyvars = [] then begin
                   try  EcUnify.unify scenv ue refty body.EcFol.f_ty
                   with EcUnify.UnificationFailure _ ->
                     clone_error scenv (CE_OpIncompatible (prefix, x))
                 end;

                 let uni     = EcUnify.UniEnv.close ue in
                 let body    = EcFol.Fsubst.uni uni body in
                 let tparams = EcUnify.UniEnv.tparams ue in
                   { op_tparams = tparams;
                     op_ty      = body.EcFol.f_ty;
                     op_kind    = OB_pred (Some body); }
              in

              let (newtyvars, newty) = (newpr.op_tparams, newpr.op_ty) in
                (* FIXME: TC HOOK *)
                if not (ty_compatible scenv
                          (List.map fst reftyvars, refty)
                          (List.map fst newtyvars, newty))
                then
                  clone_error scenv (CE_OpIncompatible (prefix, x));
                (subst, ops, proofs, EcEnv.Op.bind x newpr scenv)
        end

      | CTh_operator (x, oopd) ->
          let oopd = EcSubst.subst_op subst oopd in
            (subst, ops, proofs, EcEnv.Op.bind x oopd scenv)

      | CTh_axiom (x, ax) -> begin
          let ax = EcSubst.subst_ax subst ax in
          let (ax, proofs) =
            let doproof =
              match ax.ax_kind with
              | `Lemma -> None
              | `Axiom ->
                  match Msym.find_opt x (ovrds.evc_lemmas.ev_bynames) with
                  | Some pt -> Some pt
                  | None -> ovrds.evc_lemmas.ev_global
            in
              match doproof with
              | None     -> (ax, proofs)
              | Some pt  ->
                  let ax  = { ax with ax_kind = `Lemma } in
                  let axc = { axc_axiom = (x, ax);
                              axc_path  = EcPath.fromqsymbol (prefix, x);
                              axc_tac   = pt;
                              axc_env   = scenv; } in
                    (ax, axc :: proofs)
          in

            (subst, ops, proofs, EcEnv.Ax.bind x ax scenv)
      end

      | CTh_modtype (x, modty) ->
          let modty = EcSubst.subst_modsig subst modty in
            (subst, ops, proofs, EcEnv.ModTy.bind x modty scenv)

      | CTh_module me ->
          let me = EcSubst.subst_module subst me in
            (subst, ops, proofs, EcEnv.Mod.bind me.me_name me scenv)

      | CTh_theory (x, cth) -> begin
          let subovrds = Msym.find_opt x ovrds.evc_ths in
          let subovrds = EcUtils.odfl evc_empty subovrds in
          let (subst, ops, proofs, nth) =
            let subscenv = EcEnv.Theory.enter x scenv in
            let (subst, ops, proofs, subscenv) =
              List.fold_left
                (ovr1 (prefix @ [x]) subovrds)
                (subst, ops, proofs, subscenv) cth.cth_struct
            in
              (subst, ops, proofs, EcEnv.Theory.close subscenv)
          in
            (subst, ops, proofs, EcEnv.Theory.bind x nth scenv)
      end

      | CTh_export p ->
          (subst, ops, proofs, EcEnv.Theory.export (EcSubst.subst_path subst p) scenv)

      | CTh_baserw x ->
        (subst, ops, proofs, EcEnv.BaseRw.bind x scenv)

      | CTh_addrw (p,l) ->
        let p = EcSubst.subst_path subst p in
        let l = List.map (EcSubst.subst_path subst) l in
        (subst, ops, proofs, EcEnv.BaseRw.bind_addrw p l scenv)
        

      | CTh_instance ((typ, ty), tc) -> begin
          let module E = struct exception InvInstPath end in

          let forpath (p : EcPath.path) =
            match EcPath.getprefix opath p |> omap List.rev with
            | None | Some [] -> None
            | Some (x::px) ->
                let q = EcPath.fromqsymbol (List.rev px, x) in

                match Mp.find_opt q ops with
                | None ->
                    Some (EcPath.pappend npath q)
                | Some (op, alias) ->
                    match alias with
                    | true  -> Some (EcPath.pappend npath q)
                    | false ->
                        match op.EcDecl.op_kind with
                        | OB_pred _    -> assert false
                        | OB_oper None -> None
                        | OB_oper (Some (OP_Constr _))
                        | OB_oper (Some (OP_Record _))
                        | OB_oper (Some (OP_Proj   _))
                        | OB_oper (Some (OP_Fix    _))
                        | OB_oper (Some (OP_TC      )) ->
                            Some (EcPath.pappend npath q)
                        | OB_oper (Some (OP_Plain e)) ->
                            match e.EcTypes.e_node with
                            | EcTypes.Eop (r, _) -> Some r
                            | _ -> raise E.InvInstPath
          in

          let forpath p = odfl p (forpath p) in

          try
            let (typ, ty) = EcSubst.subst_genty subst (typ, ty) in
            let tc =
              let rec doring cr =
                { r_type  = EcSubst.subst_ty subst cr.r_type;
                  r_zero  = forpath cr.r_zero;
                  r_one   = forpath cr.r_one;
                  r_add   = forpath cr.r_add;
                  r_opp   = cr.r_opp |> omap forpath;
                  r_mul   = forpath cr.r_mul;
                  r_exp   = cr.r_exp |> omap forpath;
                  r_sub   = cr.r_sub |> omap forpath;
                  r_embed =
                    begin match cr.r_embed with
                    | `Direct  -> `Direct
                    | `Default -> `Default
                    | `Embed p -> `Embed (forpath p)
                    end;
                  r_kind = cr.r_kind; }

              and dofield cr =
                { f_ring = doring cr.f_ring;
                  f_inv  = forpath cr.f_inv;
                  f_div  = cr.f_div |> omap forpath; }
              in
                match tc with
                | `Ring    cr -> `Ring  (doring  cr)
                | `Field   cr -> `Field (dofield cr)
                | `General p  -> `General (forpath p)
            in
              (subst, ops, proofs, EcEnv.TypeClass.add_instance (typ, ty) tc scenv)

          with E.InvInstPath ->
            (subst, ops, proofs, scenv)
      end

      | CTh_typeclass (x, tc) ->
          let tc = EcSubst.subst_tc subst tc in
            (subst, ops, proofs, EcEnv.TypeClass.bind x tc scenv)

    in
      let scenv = EcEnv.Theory.enter name scenv in
      let _, _, proofs, scenv =
        List.fold_left
          (ovr1 [] ovrds) (subst, Mp.empty, [], scenv) oth.cth_struct
      in
        (List.rev proofs, EcEnv.Theory.close scenv)
  in
    (name, proofs, nth)
