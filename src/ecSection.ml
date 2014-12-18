(* --------------------------------------------------------------------
 * Copyright (c) - 2012-2014 - IMDEA Software Institute and INRIA
 * Distributed under the terms of the CeCILL-C license
 * -------------------------------------------------------------------- *)

(* -------------------------------------------------------------------- *)
open EcUtils
open EcSymbols
open EcPath
open EcTypes
open EcDecl
open EcModules

module Sid  = EcIdent.Sid
module Mid  = EcIdent.Mid
module MSym = EcSymbols.Msym

(* -------------------------------------------------------------------- *)
exception NoSectionOpened

type lvl = [`Local | `Global] * [`Axiom | `Lemma]

type locals = {
  lc_env       : EcEnv.env;
  lc_name      : symbol option;
  lc_lemmas    : (path * lvl) list * lvl Mp.t;
  lc_modules   : Sp.t;
  lc_abstracts : (EcIdent.t * (module_type * mod_restr)) list * Sid.t;
  lc_items     : EcTheory.ctheory_item list;
}

let env_of_locals (lc : locals) = lc.lc_env

let items_of_locals (lc : locals) = lc.lc_items

let is_local who p (lc : locals) =
  match who with
  | `Lemma  -> Mp.find_opt p (snd lc.lc_lemmas) |> omap fst = Some `Local
  | `Module -> Sp.mem p lc.lc_modules

let rec is_mp_local mp (lc : locals) =
  let toplocal =
    match mp.m_top with
    | `Local _ -> false
    | `Concrete (p, _) -> is_local `Module p lc
  in
    toplocal || (List.exists (is_mp_local^~ lc) mp.m_args)

let rec is_mp_abstract mp (lc : locals) =
  let toplocal =
    match mp.m_top with
    | `Concrete _ -> false
    | `Local i -> Sid.mem i (snd lc.lc_abstracts)
  in
    toplocal || (List.exists (is_mp_abstract^~ lc) mp.m_args)

let rec on_mpath_ty cb (ty : ty) =
  match ty.ty_node with
  | Tunivar _        -> ()
  | Tvar    _        -> ()
  | Tglob mp         -> cb mp
  | Ttuple tys       -> List.iter (on_mpath_ty cb) tys
  | Tconstr (_, tys) -> List.iter (on_mpath_ty cb) tys
  | Tfun (ty1, ty2)  -> List.iter (on_mpath_ty cb) [ty1; ty2]

let on_mpath_pv cb (pv : prog_var)=
  cb pv.pv_name.x_top

let on_mpath_lp cb (lp : lpattern) =
  match lp with
  | LSymbol (_, ty) -> on_mpath_ty cb ty
  | LTuple  xs      -> List.iter (fun (_, ty) -> on_mpath_ty cb ty) xs
  | LRecord (_, xs) -> List.iter (on_mpath_ty cb |- snd) xs

let rec on_mpath_expr cb (e : expr) =
  let cbrec = on_mpath_expr cb in

  let fornode () =
    match e.e_node with
    | Eint   _            -> ()
    | Elocal _            -> ()
    | Evar   _            -> ()
    | Eop    (_, tys)     -> List.iter (on_mpath_ty cb) tys
    | Eapp   (e, es)      -> List.iter cbrec (e :: es)
    | Elet   (lp, e1, e2) -> on_mpath_lp cb lp; List.iter cbrec [e1; e2]
    | Etuple es           -> List.iter cbrec es
    | Eproj  (e,_)        -> cbrec e
    | Eif    (e1, e2, e3) -> List.iter cbrec [e1; e2; e3]
    | Elam   (xs, e)      ->
        List.iter (fun (_, ty) -> on_mpath_ty cb ty) xs;
        cbrec e
  in
    on_mpath_ty cb e.e_ty;  fornode ()

let on_mpath_lv cb (lv : lvalue) =
  let for1 (pv, ty) = on_mpath_pv cb pv; on_mpath_ty cb ty in

    match lv with
    | LvVar   pv  -> for1 pv
    | LvTuple pvs -> List.iter for1 pvs

    | LvMap ((_, pty), pv, e, ty) ->
        List.iter (on_mpath_ty cb) pty;
        on_mpath_ty   cb ty;
        on_mpath_pv   cb pv;
        on_mpath_expr cb e

let rec on_mpath_instr cb (i : instr)=
  match i.i_node with
  | Sasgn   _ -> ()
  | Srnd    _ -> ()
  | Sassert _ -> ()
  | Sabstract _ -> ()

  | Scall (_, f, _) -> cb f.x_top
  | Sif (_, s1, s2) -> List.iter (on_mpath_stmt cb) [s1; s2]
  | Swhile (_, s)   -> on_mpath_stmt cb s


and on_mpath_stmt cb (s : stmt) =
  List.iter (on_mpath_instr cb) s.s_node

let on_mpath_lcmem cb m =
    cb (EcMemory.lmt_xpath m).x_top;
    Msym.iter (fun _ (_,ty) -> on_mpath_ty cb ty) (EcMemory.lmt_bindings m)

let on_mpath_memenv cb (m : EcMemory.memenv) =
  match snd m with
  | None    -> ()
  | Some lm -> on_mpath_lcmem cb lm

let rec on_mpath_modty cb mty =
  List.iter (fun (_, mty) -> on_mpath_modty cb mty) mty.mt_params;
  List.iter cb mty.mt_args

let on_mpath_binding cb b =
  match b with
  | EcFol.GTty    ty        -> on_mpath_ty cb ty
  | EcFol.GTmodty (mty, (rx,r)) ->
    on_mpath_modty cb mty;
    Sx.iter (fun x -> cb x.x_top) rx;
    Sm.iter cb r
  | EcFol.GTmem   None      -> ()
  | EcFol.GTmem   (Some m)  -> on_mpath_lcmem cb m

let on_mpath_bindings cb b =
  List.iter (fun (_, b) -> on_mpath_binding cb b) b

let rec on_mpath_form cb (f : EcFol.form) =
  let cbrec = on_mpath_form cb in

  let rec fornode () =
    match f.EcFol.f_node with
    | EcFol.Fint      _            -> ()
    | EcFol.Flocal    _            -> ()
    | EcFol.Fquant    (_, b, f)    -> on_mpath_bindings cb b; cbrec f
    | EcFol.Fif       (f1, f2, f3) -> List.iter cbrec [f1; f2; f3]
    | EcFol.Flet      (_, f1, f2)  -> List.iter cbrec [f1; f2]
    | EcFol.Fop       (_, ty)      -> List.iter (on_mpath_ty cb) ty
    | EcFol.Fapp      (f, fs)      -> List.iter cbrec (f :: fs)
    | EcFol.Ftuple    fs           -> List.iter cbrec fs
    | EcFol.Fproj     (f,_)        -> cbrec f
    | EcFol.Fpvar     (pv, _)      -> on_mpath_pv  cb pv
    | EcFol.Fglob     (mp, _)      -> cb mp
    | EcFol.FhoareF   hf           -> on_mpath_hf  cb hf
    | EcFol.FhoareS   hs           -> on_mpath_hs  cb hs
    | EcFol.FequivF   ef           -> on_mpath_ef  cb ef
    | EcFol.FequivS   es           -> on_mpath_es  cb es
    | EcFol.FeagerF   eg           -> on_mpath_eg  cb eg
    | EcFol.FbdHoareS bhs          -> on_mpath_bhs cb bhs
    | EcFol.FbdHoareF bhf          -> on_mpath_bhf cb bhf
    | EcFol.Fpr       pr           -> on_mpath_pr  cb pr

  and on_mpath_hf cb hf =
    on_mpath_form cb hf.EcFol.hf_pr;
    on_mpath_form cb hf.EcFol.hf_po;
    cb hf.EcFol.hf_f.x_top

  and on_mpath_hs cb hs =
    on_mpath_form cb hs.EcFol.hs_pr;
    on_mpath_form cb hs.EcFol.hs_po;
    on_mpath_stmt cb hs.EcFol.hs_s;
    on_mpath_memenv cb hs.EcFol.hs_m

  and on_mpath_ef cb ef =
    on_mpath_form cb ef.EcFol.ef_pr;
    on_mpath_form cb ef.EcFol.ef_po;
    cb ef.EcFol.ef_fl.x_top;
    cb ef.EcFol.ef_fr.x_top

  and on_mpath_es cb es =
    on_mpath_form cb es.EcFol.es_pr;
    on_mpath_form cb es.EcFol.es_po;
    on_mpath_stmt cb es.EcFol.es_sl;
    on_mpath_stmt cb es.EcFol.es_sr;
    on_mpath_memenv cb es.EcFol.es_ml;
    on_mpath_memenv cb es.EcFol.es_mr

  and on_mpath_eg cb eg =
    on_mpath_form cb eg.EcFol.eg_pr;
    on_mpath_form cb eg.EcFol.eg_po;
    cb eg.EcFol.eg_fl.x_top;
    cb eg.EcFol.eg_fr.x_top;
    on_mpath_stmt cb eg.EcFol.eg_sl;
    on_mpath_stmt cb eg.EcFol.eg_sr;

  and on_mpath_bhf cb bhf =
    on_mpath_form cb bhf.EcFol.bhf_pr;
    on_mpath_form cb bhf.EcFol.bhf_po;
    on_mpath_form cb bhf.EcFol.bhf_bd;
    cb bhf.EcFol.bhf_f.x_top

  and on_mpath_bhs cb bhs =
    on_mpath_form cb bhs.EcFol.bhs_pr;
    on_mpath_form cb bhs.EcFol.bhs_po;
    on_mpath_form cb bhs.EcFol.bhs_bd;
    on_mpath_stmt cb bhs.EcFol.bhs_s;
    on_mpath_memenv cb bhs.EcFol.bhs_m

  and on_mpath_pr cb pr =
    cb pr.EcFol.pr_fun.x_top;
    List.iter (on_mpath_form cb) [pr.EcFol.pr_event; pr.EcFol.pr_args]

  in
    on_mpath_ty cb f.EcFol.f_ty; fornode ()

let rec on_mpath_module cb (me : module_expr) =
  match me.me_body with
  | ME_Alias (_, mp)  -> cb mp
  | ME_Structure st   -> on_mpath_mstruct cb st
  | ME_Decl (mty, sm) -> on_mpath_mdecl cb (mty, sm)

and on_mpath_mdecl cb (mty,(rx,r)) =
  on_mpath_modty cb mty;
  Sx.iter (fun x -> cb x.x_top) rx;
  Sm.iter cb r

and on_mpath_mstruct cb st =
  List.iter (on_mpath_mstruct1 cb) st.ms_body

and on_mpath_mstruct1 cb item =
  match item with
  | MI_Module   me -> on_mpath_module cb me
  | MI_Variable x  -> on_mpath_ty cb x.v_type
  | MI_Function f  -> on_mpath_fun cb f

and on_mpath_fun cb fun_ =
  on_mpath_fun_sig  cb fun_.f_sig;
  on_mpath_fun_body cb fun_.f_def

and on_mpath_fun_sig cb fsig =
  on_mpath_ty cb fsig.fs_arg;
  on_mpath_ty cb fsig.fs_ret

and on_mpath_fun_body cb fbody =
  match fbody with
  | FBalias xp -> cb xp.x_top
  | FBdef fdef -> on_mpath_fun_def cb fdef
  | FBabs oi   -> on_mpath_fun_oi  cb oi

and on_mpath_fun_def cb fdef =
  List.iter (fun v -> on_mpath_ty cb v.v_type) fdef.f_locals;
  on_mpath_stmt cb fdef.f_body;
  fdef.f_ret |> oiter (on_mpath_expr cb);
  on_mpath_uses cb fdef.f_uses

and on_mpath_uses cb uses =
  List.iter (fun x -> cb x.x_top) uses.us_calls;
  Sx.iter   (fun x -> cb x.x_top) uses.us_reads;
  Sx.iter   (fun x -> cb x.x_top) uses.us_writes

and on_mpath_fun_oi cb oi =
  List.iter (fun x -> cb x.x_top) oi.oi_calls

exception UseLocal

let check_use_local lc mp =
  if is_mp_local mp lc then
    raise UseLocal

let check_use_local_or_abs lc mp =
  if is_mp_local mp lc || is_mp_abstract mp lc then
    raise UseLocal

let form_use_local f lc =
  try  on_mpath_form (check_use_local lc) f; false
  with UseLocal -> true

let module_use_local_or_abs m lc =
  try  on_mpath_module (check_use_local_or_abs lc) m; false
  with UseLocal -> true

let abstracts lc = lc.lc_abstracts

let generalize env lc (f : EcFol.form) =
  let axioms =
    List.pmap
      (fun (p, lvl) ->
         match lvl with `Global, `Axiom -> Some p | _ -> None)
      (fst lc.lc_lemmas)
  in

  match axioms with
  | [] ->
    let mods = Sid.of_list (List.map fst (fst lc.lc_abstracts)) in
      if   Mid.set_disjoint mods f.EcFol.f_fv
      then f
      else begin
        List.fold_right
          (fun (x, (mty, rt)) f ->
             match Mid.mem x f.EcFol.f_fv with
             | false -> f
             | true  -> EcFol.f_forall [(x, EcFol.GTmodty (mty, rt))] f)
          (fst lc.lc_abstracts) f
      end

  | _ ->
    let f =
      let do1 p f =
        let ax = EcEnv.Ax.by_path p env in
          EcFol.f_imp (oget ax.ax_spec) f
      in
          List.fold_right do1 axioms f in
    let f =
      let do1 (x, (mty, rt)) f =
        EcFol.f_forall [(x, EcFol.GTmodty (mty, rt))] f
      in
        List.fold_right do1 (fst lc.lc_abstracts) f
    in
      f

let elocals (env : EcEnv.env) (name : symbol option) : locals =
  { lc_env       = env;
    lc_name      = name;
    lc_lemmas    = ([], Mp.empty);
    lc_modules   = Sp.empty;
    lc_abstracts = ([], Sid.empty);
    lc_items     = []; }

type t = locals list

let initial : t = []

let in_section (cs : t) =
  match cs with [] -> false | _ -> true

let enter (env : EcEnv.env) (name : symbol option) (cs : t) : t =
  match List.ohead cs with
  | None    -> [elocals env name]
  | Some ec ->
    let ec =
      { ec with
          lc_items = [];
          lc_abstracts = ([], snd ec.lc_abstracts);
          lc_env = env;
          lc_name = name; }
    in
      ec :: cs

let exit (cs : t) =
  match cs with
  | [] -> raise NoSectionOpened
  | ec :: cs ->
      ({ ec with lc_items     = List.rev ec.lc_items;
                 lc_abstracts = fst_map List.rev ec.lc_abstracts;
                 lc_lemmas    = fst_map List.rev ec.lc_lemmas},
       cs)

let path (cs : t) : symbol option * path =
  match cs with
  | [] -> raise NoSectionOpened
  | ec :: _ -> (ec.lc_name, EcEnv.root ec.lc_env)

let opath (cs : t) =
  try Some (path cs) with NoSectionOpened -> None

let topenv (cs : t) : EcEnv.env =
  match List.rev cs with
  | [] -> raise NoSectionOpened
  | ec :: _ -> ec.lc_env

let locals (cs : t) : locals =
  match cs with
  | [] -> raise NoSectionOpened
  | ec :: _ -> ec

let olocals (cs : t) =
  try Some (locals cs) with NoSectionOpened -> None

let onactive (f : locals -> locals) (cs : t) =
  match cs with
  | []      -> raise NoSectionOpened
  | c :: cs -> (f c) :: cs

let add_local_mod (p : path) (cs : t) : t =
  onactive (fun ec -> { ec with lc_modules = Sp.add p ec.lc_modules }) cs

let add_lemma (p : path) (lvl : lvl) (cs : t) : t =
  onactive (fun ec ->
    let (axs, map) = ec.lc_lemmas in
      { ec with lc_lemmas = ((p, lvl) :: axs, Mp.add p lvl map) })
    cs

let add_item item (cs : t) : t =
  let doit ec = { ec with lc_items = item :: ec.lc_items } in
    onactive doit cs

let add_abstract id mt (cs : t) : t =
  let doit ec =
    match Sid.mem id (snd ec.lc_abstracts) with
    | true  -> assert false
    | false ->
        let (ids, set) = ec.lc_abstracts in
        let (ids, set) = ((id, mt) :: ids, Sid.add id set) in
          { ec with lc_abstracts = (ids, set) }
  in
    onactive doit cs
