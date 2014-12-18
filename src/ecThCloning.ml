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
let clone (scenv : EcEnv.env) (thcl : theory_cloning) =
  let opath, oth = EcEnv.Theory.lookup (unloc thcl.pthc_base) scenv in
  let name = odfl (EcPath.basename opath) (thcl.pthc_name |> omap unloc) in

  let (genproofs, ovrds) =
    let rec do1 ?(cancrt = false) (proofs, evc) ({ pl_loc = l; pl_desc = ((nm, x) as name) }, ovrd) =
      let xpath = EcPath.pappend opath (EcPath.fromqsymbol name) in

        match ovrd with
        | PTHO_Type ((tyargs, _, _) as tyd) -> begin
            match EcEnv.Ty.by_path_opt xpath scenv with
            | None ->
                clone_error scenv (CE_UnkOverride (OVK_Type, name));
            | Some { EcDecl.tyd_type = `Concrete _ } when not cancrt ->
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
            | Some { op_kind = OB_oper (Some _) } when not cancrt ->
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
            | Some { op_kind = OB_pred (Some _) } when not cancrt ->
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
              | CTh_type (x, otyd) ->
                  (* FIXME: TC HOOK *)
                  let params = List.map (EcIdent.name |- fst) otyd.tyd_params in
                  let params = List.map (mk_loc l) params in
                  let tyd    =
                    match List.map (fun a -> mk_loc l (PTvar a)) params with
                    | [] -> PTnamed (mk_loc l (xsth @ prefix, x))
                    | pt -> PTapp   (mk_loc l (xsth @ prefix, x), pt)
                  in
                  let tyd  = mk_loc l tyd in
                  let ovrd = PTHO_Type (params, tyd, `Inline) in
                    do1 ~cancrt:true (proofs, evc) (mk_loc l (xdth @ prefix, x), ovrd)

              | CTh_operator (x, ({ op_kind = OB_oper _ } as oopd)) ->
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
                    do1 ~cancrt:true (proofs, evc) (mk_loc l (xdth @ prefix, x), PTHO_Op (ovrd, `Inline))

              | CTh_operator (x, ({ op_kind = OB_pred _ } as oprd)) ->
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
                    do1 ~cancrt:true (proofs, evc) (mk_loc l (xdth @ prefix, x), PTHO_Pred ovrd)

              | CTh_axiom (x, ({ ax_spec = Some _ } as ax)) ->
                  (* FIXME: TC HOOK *)
                if ax.ax_kind = `Axiom then
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
                else (proofs,evc)

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

  (name, (opath, oth), ovrds)
