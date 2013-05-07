(* ------------------------------------------------------------------ *)
open EcUtils
open EcSymbols
open EcLocation
open EcParsetree
open EcDecl
open EcModules
open EcTheory

(* ------------------------------------------------------------------ *)
type ovkind =
| OVK_Type
| OVK_Operator
| OVK_Predicate

type clone_error =
| CE_DupOverride    of ovkind * symbol
| CE_UnkOverride    of ovkind * symbol
| CE_CrtOverride    of ovkind * symbol
| CE_TypeArgMism    of ovkind * symbol
| CE_OpIncompatible of symbol
| CE_PrIncompatible of symbol

exception CloneError of EcEnv.env * clone_error

let clone_error env error =
  raise (CloneError (env, error))

(* -------------------------------------------------------------------- *)
let string_of_ovkind = function
  | OVK_Type      -> "type"
  | OVK_Operator  -> "operator"
  | OVK_Predicate -> "predicate"

(* -------------------------------------------------------------------- *)
let pp_clone_error fmt _env error =
  let msg x = Format.fprintf fmt x in

  match error with
  | CE_DupOverride (kd, x) ->
      msg "the %s `%s' is instantiate twice"
        (string_of_ovkind kd) x

  | CE_UnkOverride (kd, x) ->
      msg "unknown %s `%s'"
        (string_of_ovkind kd) x

  | CE_CrtOverride (kd, x) ->
      msg "cannot instantiate the _concrete_ %s `%s'"
        (string_of_ovkind kd) x

  | CE_TypeArgMism (kd, x) ->
      msg "type argument mismatch for %s `%s'"
        (string_of_ovkind kd) x

  | CE_OpIncompatible x ->
      msg "operator `%s' body is not compatible with its declaration" x

  | CE_PrIncompatible x ->
      msg "predicate `%s' body is not compatible with its declaration" x

let () =
  let pp fmt exn =
    match exn with
    | CloneError (env, e) -> pp_clone_error fmt env e
    | _ -> raise exn
  in
    EcPException.register pp

(* ------------------------------------------------------------------ *)
type evclone = {
  evc_types : (ty_override located) Msym.t;
  evc_ops   : (op_override located) Msym.t;
  evc_preds : (pr_override located) Msym.t;
}

let evc_empty = {
  evc_types = Msym.empty;
  evc_ops   = Msym.empty;
  evc_preds = Msym.empty;
}

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
    if not (EcReduction.equal_type env rty nty) then
      raise Incompatible

let ty_compatible env t1 t2 =
  try  ty_compatible env t1 t2; true
  with Incompatible -> false

(* -------------------------------------------------------------------- *)
let clone (scenv : EcEnv.env) (thcl : theory_cloning) =
  let cpath = EcEnv.root scenv in

  let opath, oth = EcEnv.Theory.lookup (unloc thcl.pthc_base) scenv in
  let name  = odfl (EcPath.basename opath) (omap thcl.pthc_name unloc) in
  let npath = EcPath.pqname cpath name in
  let subst = EcSubst.add_path EcSubst.empty opath npath in

  let ovrds =
    let do1 evc (x, ovrd) =
      let { pl_loc = l; pl_desc = x; } = x in
        match ovrd with
        | PTHO_Type tyd -> begin
            if Msym.mem x evc.evc_types then
              clone_error scenv (CE_DupOverride (OVK_Type, x));
            match EcEnv.Ty.by_path_opt (EcPath.pqname opath x) scenv with
            | None ->
                clone_error scenv (CE_UnkOverride (OVK_Type, x));
            | Some { EcDecl.tyd_type = Some _ } ->
                clone_error scenv (CE_CrtOverride (OVK_Type, x));
            | Some refty ->
                if List.length refty.tyd_params <> List.length (fst tyd) then
                  clone_error scenv (CE_TypeArgMism (OVK_Type, x));
          end;
          { evc with evc_types = Msym.add x (mk_loc l tyd) evc.evc_types }

        | PTHO_Op opd -> begin
            if Msym.mem x evc.evc_ops then
              clone_error scenv (CE_DupOverride (OVK_Operator, x));
            match EcEnv.Op.by_path_opt (EcPath.pqname opath x) scenv with
            | None
            | Some { op_kind = OB_pred _ } ->
                clone_error scenv (CE_UnkOverride (OVK_Operator, x));
            | Some { op_kind = OB_oper (Some _) } ->
                clone_error scenv (CE_CrtOverride (OVK_Operator, x));
            | _ -> ()
          end;
          { evc with evc_ops = Msym.add x (mk_loc l opd) evc.evc_ops }

        | PTHO_Pred pr -> begin
            if Msym.mem x evc.evc_preds then
              clone_error scenv (CE_DupOverride (OVK_Predicate, x));
            match EcEnv.Op.by_path_opt (EcPath.pqname opath x) scenv with
            | None
            | Some { op_kind = OB_oper _ } ->
                clone_error scenv (CE_UnkOverride (OVK_Predicate, x));
            | Some { op_kind = OB_pred (Some _) } ->
                clone_error scenv (CE_CrtOverride (OVK_Predicate, x));
            | _ -> ()
          end;
          { evc with evc_preds = Msym.add x (mk_loc l pr) evc.evc_preds }
    in
      List.fold_left do1 evc_empty thcl.pthc_ext
  in

  let nth =
    let ovr1 scenv item =
      match item with
      | CTh_type (x, otyd) -> begin
          match Msym.find_opt x ovrds.evc_types with
          | None ->
              EcEnv.Ty.bind x (EcSubst.subst_tydecl subst otyd) scenv

          | Some { pl_desc = (nargs, ntyd) } ->
              (* Already checked:
               *   1. type is abstract
               *   2. type argument count are equal *)
              let nargs = List.map (EcIdent.create -| unloc) nargs in
              let ue    = EcUnify.UniEnv.create (Some nargs) in
              let ntyd  = EcTyping.transty EcTyping.tp_tydecl scenv ue ntyd in

              let binding =
                { tyd_params = nargs;
                  tyd_type   = Some ntyd; }
              in
                EcEnv.Ty.bind x binding scenv
      end

      | CTh_operator (x, ({ op_kind = OB_oper None } as oopd)) -> begin
          match Msym.find_opt x ovrds.evc_ops with
          | None ->
              EcEnv.Op.bind x (EcSubst.subst_op subst oopd) scenv

          | Some { pl_desc = opov; pl_loc = loc; } ->
              let newop =
                let ue = EcTyping.ue_for_decl scenv (loc, opov.opov_tyvars) in
                let tp = EcTyping.tp_relax in
                let (ty, body) =
                  let env     = scenv in
                  let codom   = EcTyping.transty tp env ue opov.opov_retty in 
                  let env, xs = EcTyping.transbinding env ue opov.opov_args in
                  let body    = EcTyping.transexpcast env ue codom opov.opov_body in
                  let lam     = EcTypes.e_lam xs body in
                    (lam.EcTypes.e_ty, Some lam)
                in
                let uni     = EcTypes.Tuni.subst (EcUnify.UniEnv.close ue) in
                let body    = omap body (EcTypes.e_mapty uni) in
                let ty      = uni ty in
                let tparams = EcUnify.UniEnv.tparams ue in
                  mk_op tparams ty body
              in

              let (reftyvars, refty) =
                let refop = EcEnv.Op.by_path (EcPath.pqname opath x) scenv in
                let refop = EcSubst.subst_op subst refop in
                  (refop.op_tparams, refop.op_ty)
              and (newtyvars, newty) =
                (newop.op_tparams, newop.op_ty)
              in
                if not (ty_compatible scenv (reftyvars, refty) (newtyvars, newty)) then
                  clone_error scenv (CE_OpIncompatible x);
                EcEnv.Op.bind x newop scenv
      end

      | CTh_operator (x, ({ op_kind = OB_pred None} as oopr)) -> begin
          match Msym.find_opt x ovrds.evc_preds with
          | None ->
              EcEnv.Op.bind x (EcSubst.subst_op subst oopr) scenv

          | Some { pl_desc = prov; pl_loc = loc; } ->
              let newpr =
                let ue = EcTyping.ue_for_decl scenv (loc, prov.prov_tyvars) in
                let (dom, body) =
                  let env     = scenv in
                  let env, xs = EcTyping.transbinding env ue prov.prov_args in
                  let body    = EcTyping.transformula env ue prov.prov_body in
                  let dom     = List.map snd xs in
                  let xs      = List.map (fun (x,ty) -> x, EcFol.GTty ty) xs in
                  let lam     = EcFol.f_lambda xs body in
                    (dom, lam)
                in
                let uni     = EcTypes.Tuni.subst (EcUnify.UniEnv.close ue) in
                let body    = EcFol.Fsubst.mapty uni body in
                let dom     = List.map uni dom in
                let tparams = EcUnify.UniEnv.tparams ue in
                  mk_pred tparams dom (Some body)
              in

              let (reftyvars, refty) =
                let refpr = EcEnv.Op.by_path (EcPath.pqname opath x) scenv in
                let refpr = EcSubst.subst_op subst refpr in
                  (refpr.op_tparams, refpr.op_ty)
              and (newtyvars, newty) =
                (newpr.op_tparams, newpr.op_ty)
              in
                if not (ty_compatible scenv (reftyvars, refty) (newtyvars, newty)) then
                  clone_error scenv (CE_OpIncompatible x);
                EcEnv.Op.bind x newpr scenv
        end

      | CTh_operator (x, oopd) ->
          EcEnv.Op.bind x (EcSubst.subst_op subst oopd) scenv

      | CTh_axiom (x, ax) ->
          EcEnv.Ax.bind x (EcSubst.subst_ax subst ax) scenv

      | CTh_modtype (x, modty) ->
          EcEnv.ModTy.bind x (EcSubst.subst_modsig subst modty) scenv

      | CTh_module me ->
          EcEnv.Mod.bind me.me_name (EcSubst.subst_module subst me) scenv

      | CTh_theory (x, cth) ->
          EcEnv.Theory.bindx x (EcSubst.subst_ctheory subst cth) scenv

      | CTh_export p ->               (* FIXME: subst in p? *)
          EcEnv.Theory.export p scenv
    in
      let scenv = EcEnv.Theory.enter name scenv in
      let scenv = List.fold_left ovr1 scenv oth.cth_struct in
        EcEnv.Theory.close scenv
  in
    (name, nth)