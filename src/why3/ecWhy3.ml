(* --------------------------------------------------------------------
 * Copyright (c) - 2012-2015 - IMDEA Software Institute and INRIA
 * Distributed under the terms of the CeCILL-C license
 * -------------------------------------------------------------------- *)

(* ----------------------------------------------------------------------*)
open EcMaps
open Why3
open EcUtils
open EcSymbols
open EcIdent
open EcPath
open EcTypes
open EcBaseLogic
open EcDecl
open EcCoreFol
open EcModules
open EcTheory
open EcWhy3Conv

(* -------------------------------------------------------------------- *)
module Mp   = EcPath.Mp
module Mm   = EcPath.Mm
module Mx   = EcPath.Mx
module Msym = EcSymbols.Msym

(* -------------------------------------------------------------------- *)
exception CannotTranslate of string

(* ----------------------------------------------------------------------*)
type env = {
  logic_task : Task.task;
  env_ty     : ty_body Mp.t;
  env_op     : (Term.lsymbol * Term.lsymbol * Ty.tvsymbol list) Mp.t;
  env_proj   : Term.lsymbol Mint.t Mint.t; 
  env_ax     : Decl.prsymbol Mp.t;
  env_mp     : Term.lsymbol Mm.t;
  env_xpv    : Term.lsymbol Mx.t;
  env_xpf    : Term.lsymbol Mx.t;
  env_tv     : Ty.ty Mid.t;
  env_id     : Term.term Mid.t;
  env_w3     : (EcPath.path * Ty.tvsymbol list) Ident.Mid.t;
  env_lam    : Term.term Mta.t;
  env_rax    : EcPath.path Decl.Mpr.t;
}

and ty_body =
  Ty.tysymbol *
    [ `Plain
    | `Datatype of   (symbol * Term.lsymbol) list
    | `Record   of   (symbol * Term.lsymbol)
                   * (symbol * Term.lsymbol * Ty.ty) list ]

let ty_body_equal ((ty1, xi1) : ty_body) ((ty2, xi2) : ty_body) =
  let c_equal (c1, l1) (c2, l2) =
    sym_equal c1 c2 && Term.ls_equal l1  l2

  and r_equal (c1, l1, ty1) (c2, l2, ty2) =
       sym_equal c1 c2
    && Term.ls_equal l1 l2
    && Ty.ty_equal ty1 ty2
  in
    (Ty.ts_equal ty1 ty2)
      && match xi1, xi2 with
         | `Plain , `Plain ->
             true

         | `Datatype ls1, `Datatype ls2 ->
             List.all2 c_equal ls1 ls2

         | `Record ((c1, l1), fs1), `Record ((c2, l2), fs2) ->
                sym_equal c1 c2
             && Term.ls_equal l1  l2
             && List.all2 r_equal fs1 fs2

         | _, _ -> false

let w3_ls_true  = Term.fs_bool_true
let w3_ls_false = Term.fs_bool_false

let w3_ls_not, decl_not, spec_not =
  let ls =
    Term.create_fsymbol (Ident.id_fresh "Not") []
      (Ty.ty_func Ty.ty_bool Ty.ty_bool) in
  let decl = Decl.create_param_decl ls in
  let preid = Ident.id_fresh "b" in
  let id = Term.create_vsymbol preid Ty.ty_bool in
  let b = Term.t_var id in
  let f_app = Term.t_func_app (Term.t_app_infer ls []) b in
  let form =
    Term.t_forall_close [id] []
      (Term.t_iff (Term.t_equ f_app Term.t_bool_true)
         (Term.t_not (Term.t_equ b Term.t_bool_true))) in
  let pr = Decl.create_prsymbol (Ident.id_fresh "Not_spec") in
  let decl_spec = Decl.create_prop_decl Decl.Paxiom pr form in
  ls, decl, decl_spec

let mk_w3_opp2 s mk =
  let ls =
    Term.create_fsymbol (Ident.id_fresh s) []
     (Ty.ty_func Ty.ty_bool (Ty.ty_func Ty.ty_bool Ty.ty_bool)) in
  let decl = Decl.create_param_decl ls in
  let preid = Ident.id_fresh "b" in
  let id1 = Term.create_vsymbol preid Ty.ty_bool in
  let id2 = Term.create_vsymbol preid Ty.ty_bool in
  let b1 = Term.t_var id1 in
  let b2 = Term.t_var id2 in
  let f_app =
    Term.t_func_app (Term.t_func_app (Term.t_app_infer ls []) b1) b2 in
  let form =
    Term.t_forall_close [id1;id2] []
      (Term.t_iff (Term.t_equ f_app Term.t_bool_true)
         (mk (Term.t_equ b1 Term.t_bool_true)
            (Term.t_equ b2 Term.t_bool_true))) in
  let pr = Decl.create_prsymbol (Ident.id_fresh (s^"_spec")) in
  let decl_spec = Decl.create_prop_decl Decl.Paxiom pr form in
  ls, decl, decl_spec

let w3_ls_and, decl_and, spec_and = mk_w3_opp2 "ANDS" Term.t_and
let w3_ls_anda, decl_anda, spec_anda = mk_w3_opp2 "ANDA" Term.t_and_asym
let w3_ls_or, decl_or, spec_or = mk_w3_opp2 "ORS" Term.t_or
let w3_ls_ora, decl_ora, spec_ora = mk_w3_opp2 "ORA" Term.t_or_asym
let w3_ls_imp, decl_imp, spec_imp = mk_w3_opp2 "IMP" Term.t_implies
let w3_ls_iff, decl_iff, spec_iff = mk_w3_opp2 "IFF" Term.t_iff

let w3_ls_eq, decl_eq, spec_eq =
  let a  = Ty.create_tvsymbol (Ident.id_fresh "'a") in
  let ta = Ty.ty_var a in
  let ty = (Ty.ty_func ta (Ty.ty_func ta Ty.ty_bool)) in
  let ls = Term.create_fsymbol (Ident.id_fresh "EQ") [] ty in
  let decl = Decl.create_param_decl ls in
  let preid = Ident.id_fresh "x" in
  let id1 = Term.create_vsymbol preid ta in
  let id2 = Term.create_vsymbol preid ta in
  let b1 = Term.t_var id1 in
  let b2 = Term.t_var id2 in
  let f_app =
    Term.t_func_app (Term.t_func_app (Term.fs_app ls [] ty) b1) b2 in
  let form =
    Term.t_forall_close [id1;id2] []
      (Term.t_iff (Term.t_equ f_app Term.t_bool_true)
         (Term.t_equ b1 b2)) in
  let pr = Decl.create_prsymbol (Ident.id_fresh ("EQ_spec")) in
  let decl_spec = Decl.create_prop_decl Decl.Paxiom pr form in
  ls, decl, decl_spec

let ts_distr, fs_mu, distr_theory =
  let th  = Theory.create_theory (Ident.id_fresh "Distr") in
  let th  = Theory.use_export th Theory.bool_theory in
  let th  = Theory.use_export th Theory.highord_theory in
  let vta = Ty.create_tvsymbol (Ident.id_fresh "ta") in
  let ta  = Ty.ty_var vta in
  let tdistr = Ty.create_tysymbol (Ident.id_fresh "distr") [vta] None in
  let th  = Theory.add_ty_decl th tdistr in
  let mu  =
    Term.create_fsymbol (Ident.id_fresh "mu")
      [Ty.ty_app tdistr [ta]; Ty.ty_func ta Ty.ty_bool]
      Ty.ty_real in
  let th = Theory.add_param_decl th mu in
  tdistr, mu, Theory.close_theory th

let ty_distr t = Ty.ty_app ts_distr [t]

(* Special type for translation of glob, hoare, equiv and pr *)
(*
  type memory
(*  type name *)
  type mod 
  type 't var 
  type ('ta, 'tr) fun
  op app_mod : mod -> mod -> mod 
  op get_var : 't var -> memory -> 't
  op sem : ('ta,'tr) fun -> memory -> 'ta -> memory distr

translation of module :
  + abstract module M :
     we declare a type "tglob_M" which is the type of the global memory of the module
     we declare a logical symbol of type "tglob var", it is used of the translation of Fglob m
     we declare a logical symbol M : mod.
     for each function in the signature we declare a logical symbol of type
       mod -> ... -> mod -> (ta,tr) fun  
        where the number of mod correspond to the module parameter
              ta is the tuple type of arguments and tr is the result type
  + alias : nothing is done, alias are inlined
  + structure :
    we declare a logical symbol M : mod.
    for each variable a symbol of type var t
    foreach submodule N a symbol M.N of type mod -> mod -> mod -> mod
            where the number of mod correspond to the module parameter
    foreach function a symbol as for abstract module

translation of local variable 
  xpath -> var t

*)

let ts_mem = Ty.create_tysymbol (Ident.id_fresh "memory") [] None
let ty_mem = Ty.ty_app ts_mem []

let ts_mod = Ty.create_tysymbol (Ident.id_fresh "module") [] None
let ty_mod = Ty.ty_app ts_mod []

let ts_var = 
  let t = Ty.create_tvsymbol (Ident.id_fresh "t") in
  Ty.create_tysymbol (Ident.id_fresh "var") [t] None
let ty_var t = Ty.ty_app ts_var [t]

let ts_fun =
  let ta = Ty.create_tvsymbol (Ident.id_fresh "ta")
(*  and tr = Ty.create_tvsymbol (Ident.id_fresh "tr") *) in
  Ty.create_tysymbol (Ident.id_fresh "fun") [ta(*;tr*)] None
let ty_fun ta (* tr *) = Ty.ty_app ts_fun [ta (*; tr *)]

let fs_app_mod = 
  Term.create_fsymbol (Ident.id_fresh "app_mod") [ty_mod;ty_mod] ty_mod

let app_mod f m = 
  Term.fs_app fs_app_mod [f;m] ty_mod 

let fs_get_var = 
  let t = Ty.ty_var (Ty.create_tvsymbol (Ident.id_fresh "t")) in
  Term.create_fsymbol (Ident.id_fresh "get_var") [ty_var t;ty_mem] t
  
let get_var v m = 
  Term.t_app_infer fs_get_var [v;m] 

let fs_sem = 
  let ta = Ty.ty_var (Ty.create_tvsymbol (Ident.id_fresh "ta"))
(*  and tr = Ty.ty_var (Ty.create_tvsymbol (Ident.id_fresh "tr")) *) in
  let tf = Ty.ty_app ts_fun [ta (*; tr *)] in
  Term.create_fsymbol (Ident.id_fresh "sem") [tf;ty_mem;ta] (ty_distr ty_mem)

let getpr f mem args ev =
  let sem = Term.t_app_infer fs_sem [f;mem;args] in
  Term.t_app_infer fs_mu [sem;ev]

let add_decl_with_tuples task d =
  let ids = Ident.Mid.set_diff d.Decl.d_syms (Task.task_known task) in
  let add id s = match Ty.is_ts_tuple_id id with
    | Some n -> Stdlib.Sint.add n s
    | None -> s in
  let ixs = Ident.Sid.fold add ids Stdlib.Sint.empty in
  let add n task = Task.use_export task (Theory.tuple_theory n) in
  Task.add_decl (Stdlib.Sint.fold add ixs task) d

let initial_task =
  let task =
    List.fold_left Task.use_export None
      [Theory.builtin_theory;Theory.bool_theory;Theory.highord_theory;
       distr_theory] in
  let task =
    List.fold_left Task.add_decl task
      [decl_not; spec_not;
       decl_and; spec_and; decl_anda; spec_anda;
       decl_or; spec_or; decl_ora; spec_ora;
       decl_imp; spec_imp; decl_iff; spec_iff;
       decl_eq; spec_eq ] in
  let ts = [ts_mem; ts_mod; ts_var; ts_fun] in
  let add_ty_decl task ts =
    add_decl_with_tuples task (Decl.create_ty_decl ts) in
  let fs = [fs_app_mod; fs_get_var;fs_sem] in
  let add_param_decl task fs =
    add_decl_with_tuples task (Decl.create_param_decl fs) in
  let task = List.fold_left add_ty_decl task ts in
  List.fold_left add_param_decl task fs

let empty = {
    logic_task  = initial_task;
    env_ty      = Mp.empty;
    env_op      = Mp.empty;
    env_proj    = Mint.empty;
    env_ax      = Mp.empty;
    env_mp      = Mm.empty;
    env_xpv     = Mx.empty;
    env_xpf     = Mx.empty;
    env_tv      = Mid.empty;
    env_id      = Mid.empty;
    env_w3      = Ident.Mid.empty;
    env_lam     = Mta.empty;
    env_rax     = Decl.Mpr.empty;  }

(* ---------------------------------------------------------------------- *)
type rebinding_w3 = {
  rb_th   : Theory.theory;
  rb_decl : Decl.decl list;
  rb_ty   : ty_body Mp.t;
  rb_op   : (Term.lsymbol * Term.lsymbol * Ty.tvsymbol list) Mp.t;
  rb_ax   : Decl.prsymbol Mp.t;
  rb_w3   : (EcPath.path * Ty.tvsymbol list) Ident.Mid.t;
}

let rb_empty th = {
    rb_th     = th;
    rb_decl   = [];
    rb_ty     = Mp.empty;
    rb_op     = Mp.empty;
    rb_ax     = Mp.empty;
    rb_w3     = Ident.Mid.empty;
  }

type highorder_decl = (Term.lsymbol * Decl.decl * Decl.decl) option

type rebinding_item =
  | RBuse  of rebinding_w3
  | RBty   of EcPath.path * rbty_body * Decl.decl
  | RBop   of EcPath.path * (Term.lsymbol * Ty.tvsymbol list) * Decl.decl * highorder_decl
  | RBax   of EcPath.path * Decl.prsymbol * Decl.decl
  | RBmp   of EcPath.mpath * Term.lsymbol
  | RBxpf  of EcPath.xpath * Term.lsymbol
  | RBxpv  of EcPath.xpath * Term.lsymbol
  | RBfun  of Decl.decl * Decl.decl * Talpha.t * Term.term 
  | RBproj of int * int * Term.lsymbol * Decl.decl

and rbty_body =
  Ty.tysymbol *
    [ `Plain
    | `Datatype of   (symbol * Term.lsymbol * highorder_decl) list
    | `Record   of   (symbol * Term.lsymbol * highorder_decl)
                   * (symbol * Term.lsymbol * highorder_decl * Ty.ty) list ]

type rebinding = rebinding_item list

(* -------------------------------------------------------------------- *)
let ty_of_rbty ((ty, body) : rbty_body) : ty_body=
  let body =
    match body with
    | `Plain ->
        `Plain

    | `Datatype cs ->
        `Datatype (List.map (fun (c, ls, _) -> (c, ls)) cs)

    | `Record ((c, cls, _), fields) ->
        let fields = List.map (fun (f, ls, _, fty) -> (f, ls, fty)) fields in
          `Record ((c, cls), fields)
  in
    (ty, body)

(* -------------------------------------------------------------------- *)
let merge check k o1 o2 =
  match o1, o2 with
  | Some e1, Some e2 -> check k e1 e2; o1
  | _, None -> o1
  | None, _ -> o2

exception MergeW3Ty of EcPath.path * ty_body       * ty_body
exception MergeW3Op of EcPath.path * Term.lsymbol  * Term.lsymbol
exception MergeW3Ax of EcPath.path * Decl.prsymbol * Decl.prsymbol
exception MergeW3Id of Ident.ident * EcPath.path   * EcPath.path

let merge_ty =
  let check p t1 t2 =
    if not (ty_body_equal t1 t2) then raise (MergeW3Ty(p,t1,t2)) in
  Mp.merge (merge check)

let merge_op =
  let check p (t1,_,_) (t2,_,_) =
    if not (Term.ls_equal t1 t2) then raise (MergeW3Op(p,t1,t2)) in
  Mp.merge (merge check)

let merge_ax =
  let check p t1 t2 =
    if not (Decl.pr_equal t1 t2) then raise (MergeW3Ax(p,t1,t2)) in
  Mp.merge (merge check)

let merge_id =
  let check p (t1,_) (t2,_) =
    if not (EcPath.p_equal t1 t2) then raise (MergeW3Id(p,t1,t2)) in
  Ident.Mid.merge (merge check)

let mk_highorder_func ls =
  let targs = ls.Term.ls_args in
  let tres = ls.Term.ls_value in
  if targs = [] then None
  else
    let pid = Ident.id_fresh (ls.Term.ls_name.Ident.id_string ^ "_ho") in
    let codom = (odfl Ty.ty_bool tres) in
    let ty = List.fold_right Ty.ty_func ls.Term.ls_args codom in
    let ls' = Term.create_fsymbol pid [] ty in
    let decl' = Decl.create_param_decl ls' in
    let pid_spec = Ident.id_fresh (ls.Term.ls_name.Ident.id_string ^ "_ho_spec") in
    let pr = Decl.create_prsymbol pid_spec in
    let preid = Ident.id_fresh "x" in
    let params = List.map (Term.create_vsymbol preid) targs in
    let args = List.map Term.t_var params in
    let f_app' =
      List.fold_left Term.t_func_app (Term.fs_app ls' [] ty) args in
    let f_app = Term.t_app ls args tres in
    let spec =
      match tres with
      | None -> Term.t_iff (Term.t_equ f_app' Term.t_bool_true) f_app
      | Some _ -> Term.t_equ f_app' f_app in
    let spec = Term.t_forall_close params [] spec in
    let decl_s = Decl.create_prop_decl Decl.Paxiom pr spec in
    Some(ls',decl',decl_s)

let add_ts env path rbts decl =
  let ts = ty_of_rbty rbts in

  if Mp.mem path env.env_ty then begin
    assert (ty_body_equal ts (Mp.find path env.env_ty));
    env
  end else begin
    let add_extra_op env c ls odecl =
      let tvs   = (fst ts).Ty.ts_args in
      let cpath = EcPath.pqoname (EcPath.prefix path) c in
        match odecl with
        | None ->
            { env with env_op = Mp.add cpath (ls, ls, tvs) env.env_op }
            
        | Some (ls', dcl1, dcl2) ->
            List.fold_left
              (fun env dcl ->
                { env with logic_task = add_decl_with_tuples env.logic_task dcl })
              { env with env_op = Mp.add cpath (ls, ls', tvs) env.env_op }
              [dcl1; dcl2]
    in

    let env =
      { env with
          env_ty = Mp.add path ts env.env_ty;
          logic_task = add_decl_with_tuples env.logic_task decl; }
    in
      match snd rbts with
      | `Plain -> env
      | `Datatype ls -> begin
          let for1 env (c, ls, odecl) = add_extra_op env c ls odecl in
            List.fold_left for1 env ls
        end
      | `Record (ctor, fields) -> begin
          let for1 env (f, ls, odecl, _) = add_extra_op env f ls odecl in
          let env = List.fold_left for1 env fields in
            curry3 (add_extra_op env) ctor
        end
  end

let add_ls env path ls tparams decl odecl =
  let ls', add' =
    match odecl with
    | None -> ls, fun t -> t
    | Some(ls', decl', decl_s) ->
        ls', fun t ->
          let t = add_decl_with_tuples t decl' in
          add_decl_with_tuples t decl_s
  in
    { env with
        env_op = Mp.add path (ls,ls',tparams) env.env_op;
        logic_task = add' (add_decl_with_tuples env.logic_task decl); }

let add_mp env mp ls =
  let decl = Decl.create_param_decl ls in
  let add o = assert (o = None); Some ls in
  { env with
    env_mp = Mm.change add mp env.env_mp;
    logic_task = add_decl_with_tuples env.logic_task decl}

let add_xpv env xp ls =
  let decl = Decl.create_param_decl ls in
  let add o = assert (o = None); Some ls in
  { env with
    env_xpv = Mx.change add xp env.env_xpv;
    logic_task = add_decl_with_tuples env.logic_task decl}

let add_xpf env xp ls =
  let decl = Decl.create_param_decl ls in
  let add o = assert (o = None); Some ls in
  { env with
    env_xpf = Mx.change add xp env.env_xpf;
    logic_task = add_decl_with_tuples env.logic_task decl}

let add_pr env path pr decl =
  if Mp.mem path env.env_ax then
    (assert (Decl.pr_equal pr (Mp.find path env.env_ax)); env)
  else
    { env with
      env_ax = Mp.add path pr env.env_ax;
      env_rax = Decl.Mpr.add pr path env.env_rax;
      logic_task = add_decl_with_tuples env.logic_task decl }

let rebind_item env = function
  | RBuse w3 ->
      let task = Task.use_export env.logic_task w3.rb_th in
      let task = List.fold_left Task.add_decl task w3.rb_decl in
        { env with
            logic_task = task;
            env_ty     = merge_ty env.env_ty w3.rb_ty;
            env_op     = merge_op env.env_op w3.rb_op;
            env_ax     = merge_ax env.env_ax w3.rb_ax;
            env_w3     = merge_id env.env_w3 w3.rb_w3; }
  | RBty(p,ts,decl) -> add_ts env p ts decl
  | RBop(p,(ls,tvs),decl,odecl) -> add_ls env p ls tvs decl odecl
  | RBax(p,pr,decl) -> add_pr env p pr decl
  | RBmp(p,ls)      -> add_mp env p ls
  | RBxpv(p,ls)     -> add_xpv env p ls
  | RBxpf(p,ls)     -> add_xpf env p ls
  | RBfun(decl,sdecl, k, t) ->
      let task =
        List.fold_left add_decl_with_tuples
          env.logic_task [decl(*;decls*);sdecl] in
      { env with 
        env_lam = Mta.add k t env.env_lam;
        logic_task = task }
  | RBproj(n,p,ls,d) ->
    let task = add_decl_with_tuples env.logic_task d in
    let mn = try Mint.find n env.env_proj with Not_found -> Mint.empty in
    let ep = Mint.add n (Mint.add p ls mn) env.env_proj in
    { env with env_proj = ep; logic_task = task }
      
    

let rebind = List.fold_left rebind_item

(* ---------------------------------------------------------------------- *)
(* -----------------------  Import why3 theory -------------------------- *)
(* ---------------------------------------------------------------------- *)
type renaming_kind =
  | RDts
  | RDls
  | RDpr

type renaming_decl = (string list * renaming_kind * EcSymbols.symbol) list

let w3_id_string id = id.Ident.id_string

module Renaming = struct
  type renaming = {
      r_ts : EcSymbols.symbol Ty.Mts.t;
      r_ls : EcSymbols.symbol Term.Mls.t;
      r_pr : EcSymbols.symbol Decl.Mpr.t
    }

  let init rd th =
    let ns = th.Theory.th_export in
    let rec aux ts ls pr rd =
      match rd with
      | [] -> { r_ts = ts; r_ls = ls; r_pr = pr }
      | (p,RDts,id) :: rd ->
          let ts = Ty.Mts.add (Theory.ns_find_ts ns p) id ts in
          aux ts ls pr rd
      | (p,RDls,id) :: rd ->
          let ls = Term.Mls.add (Theory.ns_find_ls ns p) id ls in
          aux ts ls pr rd
      | (p,RDpr,id)::rd ->
          let pr = Decl.Mpr.add (Theory.ns_find_pr ns p) id pr in
          aux ts ls pr rd in
    aux Ty.Mts.empty Term.Mls.empty Decl.Mpr.empty rd

  let get_ts rn ts =
    try Ty.Mts.find ts rn.r_ts
    with _ ->
      let id = ts.Ty.ts_name in
        w3_id_string id

  let remove_infix s =
    let len = String.length s in
    if len < 7 then s else
    let inf = String.sub s 0 6 in
    if inf = "infix "  then String.sub s 6 (len - 6) else
    let prf = String.sub s 0 7 in
    if prf = "prefix " then String.sub s 7 (len - 7) else
    if s = "mixfix []" then EcCoreLib.s_get else
    if s = "mixfix [<-]" then EcCoreLib.s_set else
    s

  let get_ls rn ls =
    try Term.Mls.find ls rn.r_ls
    with _ ->
      let id = ls.Term.ls_name in
      let s  = remove_infix (w3_id_string id) in
        s

  let get_pr rn pr =
    try Decl.Mpr.find pr rn.r_pr
    with _ ->
      let id = pr.Decl.pr_name in
        w3_id_string id
end

module Wtvm = struct
  type t = EcIdent.t Ty.Mtv.t ref

  let create () = ref Ty.Mtv.empty

  let get tvm tv =
    try Ty.Mtv.find tv !tvm
    with _ ->
      let s = w3_id_string tv.Ty.tv_name in
      assert (String.length s <> 0);
      let s = if s.[0] = '\'' then s else String.concat "" ["\'"; s] in
      let id = EcIdent.create s in
      tvm := Ty.Mtv.add tv id !tvm;
      id

  let tparams tvm =
    List.map (fun x -> (x, Sp.empty)) (Ty.Mtv.values !tvm)
end

exception UnknownWhy3Ident of Ident.ident

let path_of_id env id =
  try Ident.Mid.find id env.env_w3
  with _ -> raise (UnknownWhy3Ident id)

let rec import_w3_ty env tvm ty =
  match ty.Ty.ty_node with
  | Ty.Tyvar v -> tvar (Wtvm.get tvm v)
  | Ty.Tyapp(t, args) ->
      let args = List.map (import_w3_ty env tvm) args in
      try
        let path,_ = path_of_id env t.Ty.ts_name in
        tconstr path args
      with e ->
        if Ty.is_ts_tuple t then ttuple args
        else if Ty.ts_equal t Ty.ts_func then
          let t1,t2 = List.hd2 args in
          tfun t1 t2
        else if Ty.ts_equal t Ty.ts_pred then
          let t1,t2 = List.hd args, tbool in
          tfun t1 t2
        else raise e

let add_w3_ty env p ty =
  { env with
      env_ty = Mp.add p (ty, `Plain) env.env_ty;
      env_w3 = Ident.Mid.add (ty.Ty.ts_name) (p, []) env.env_w3 }

let rbadd_w3_ty rb p ty =
  { rb with
      rb_ty = Mp.add p (ty, `Plain) rb.rb_ty;
      rb_w3 = Ident.Mid.add (ty.Ty.ts_name) (p,[]) rb.rb_w3 }

type zipper_elem =
  | Zenter of EcSymbols.symbol
  | Zdecl  of theory_item

and zipper = zipper_elem list

let import_w3_tydef rn path (env,rb,z) ty =
  let tvm = Wtvm.create () in
  let params = List.map (fun x -> Wtvm.get tvm x, Sp.empty) ty.Ty.ts_args in
  let def =
    match ty.Ty.ts_def |> omap (import_w3_ty env tvm) with
    | None    -> `Abstract Sp.empty
    | Some ty -> `Concrete ty
  in
  let eid = Renaming.get_ts rn ty in
  let td = { tyd_params = params; tyd_type = def } in
  let p = EcPath.pqname path eid in
  let env = add_w3_ty env p ty in
  let rb  = rbadd_w3_ty rb p ty in
    (env, rb, Zdecl (Th_type (eid, td)) :: z)

let force_bool codom =
  match codom with
  | None ->  EcTypes.tbool
  | Some t -> t

exception CannotTranslateW3Ec
exception UnboundLS of Term.lsymbol

let import_w3_quant = function
  | Term.Tforall -> Lforall
  | Term.Texists -> Lexists

let is_asym t =
  Ident.Slab.mem Term.asym_label t.Term.t_label

let import_w3_term env tvm =
  let memo = Ty.Hty.memo 37 (import_w3_ty env tvm) in
  let import_ty ty =
    match ty with
    | None -> EcTypes.tbool
    | Some t -> memo t in
  let add_local v vm =
    let id = EcIdent.create (w3_id_string v.Term.vs_name) in
    let ty = import_ty (Some v.Term.vs_ty) in
    (id,ty), Term.Mvs.add v id vm in
  let add_locals vs vm =
    let r = ref vm in
    let its = List.map (fun v -> let (d,vm) = add_local v !r in r := vm; d) vs in
    its, !r in
  let rec import vm t =
    match t.Term.t_node with
    | Term.Tvar v -> f_local (Term.Mvs.find v vm) (import_ty t.Term.t_ty)
    | Term.Tconst _ -> raise CannotTranslateW3Ec (* FIXME *)
    | Term.Tapp(f,wargs) ->
        let args = List.map (import vm) wargs in
        let import_ty = import_w3_ty env tvm in
        let wty = t.Term.t_ty in
        let codom = odfl tbool (wty |> omap import_ty) in
        begin try
          let p,tvs =
            try Ident.Mid.find f.Term.ls_name env.env_w3
            with _ -> raise (UnboundLS f) in
          let s = Term.ls_app_inst f wargs wty in
          let tys = List.map (fun vs -> import_ty (Ty.Mtv.find vs s)) tvs in
          let dom = List.map EcCoreFol.f_ty args in
          let op = f_op p tys (toarrow dom codom) in
          f_app op args codom
        with UnboundLS f as e ->
          if Term.is_fs_tuple f then f_tuple args
          else
            if Term.ls_equal f Term.fs_func_app then
              let (a1, a2) = List.hd2 args in
                f_app a1 [a2] codom
            else raise e
        end

    | Term.Tif(t1,t2,t3) ->
        let f1 = import vm t1 in
        let f2 = import vm t2 in
        let f3 = import vm t3 in
        f_if f1 f2 f3
    | Term.Tlet(e,tb) ->
        let f1 = import vm e in
        let v, t = Term.t_open_bound tb in
        let (id,_), vm = add_local v vm in
        let f2 = import vm t in
        f_let (LSymbol (id,f1.f_ty)) f1 f2
    | Term.Tcase _ -> raise CannotTranslateW3Ec (* FIXME : tuple *)
    | Term.Teps _ ->  raise CannotTranslateW3Ec
    | Term.Tquant(q,tq) ->
        let vs,_,t = Term.t_open_quant tq in
        let ids, vm = add_locals vs vm in
        let ids = List.map (fun (x, ty) -> (x, GTty ty)) ids in
        let f = import vm t in
        f_quant (import_w3_quant q) ids f
    | Term.Tbinop(op,t1,t2) ->
        let f1 = import vm t1 in
        let f2 = import vm t2 in
        begin match op with
        | Term.Tand     ->
            if is_asym t1 then f_anda f1 f2 else f_and f1 f2
        | Term.Tor      ->
            if is_asym t1 then f_ora f1 f2 else f_or f1 f2
        | Term.Timplies -> f_imp f1 f2
        | Term.Tiff     -> f_iff f1 f2
        end
    | Term.Tnot t -> f_not (import vm t)
    | Term.Ttrue  -> f_true
    | Term.Tfalse -> f_false in
  import_ty, add_locals, import

let add_w3_ls env p ls wparams odecl =
  let ls' = match odecl with None -> ls | Some (ls',_,_) -> ls' in
  { env with
    env_op = Mp.add p (ls,ls',wparams) env.env_op;
    env_w3 = Ident.Mid.add ls.Term.ls_name (p,wparams) env.env_w3 }

let rbadd_w3_ls rb p ls wparams odecl =
  let ls',rb_decl =
    match odecl with
    | None -> ls, rb.rb_decl
    | Some (ls',d',ds) -> ls', ds::d'::rb.rb_decl in
  { rb with
    rb_op = Mp.add p (ls,ls',wparams) rb.rb_op;
    rb_w3 = Ident.Mid.add ls.Term.ls_name (p,wparams) rb.rb_w3;
    rb_decl = rb_decl;
  }

let import_w3_ls rn path (env,rb,z) ls =
  let tvm = Wtvm.create () in
  let dom = List.map (import_w3_ty env tvm) ls.Term.ls_args in
  let codom =  ls.Term.ls_value |> omap (import_w3_ty env tvm) in
  let wparams = Ty.Stv.elements (Term.ls_ty_freevars ls) in
  let params = List.map (fun x -> Wtvm.get tvm x, Sp.empty) wparams in
  let eid = Renaming.get_ls rn ls in
  let op = mk_op params (toarrow dom (force_bool codom)) None in
  let p = EcPath.pqname path eid in
  let odecl = mk_highorder_func ls in
  let env = add_w3_ls env p ls wparams odecl in
  let rb  = rbadd_w3_ls rb p ls wparams odecl in
  env, rb, Zdecl (Th_operator (eid,op)) :: z

let import_w3_constructor rn path envld (ls, pls) =
  let envld = import_w3_ls rn path envld ls in
  List.fold_left (fun envld ols ->
    match ols with
    | Some ls -> import_w3_ls rn path envld ls
    | None -> envld) envld pls

let import_w3_constructors rn path =
  List.fold_left (import_w3_constructor rn path)

let add_w3_pr env p pr =
  { env with
    env_ax = Mp.add p pr env.env_ax;
    env_w3 = Ident.Mid.add (pr.Decl.pr_name) (p,[]) env.env_w3 }

let rbadd_w3_pr rb p pr =
  { rb with
    rb_ax = Mp.add p pr rb.rb_ax;
    rb_w3 = Ident.Mid.add (pr.Decl.pr_name) (p,[]) rb.rb_w3 }

let import_w3_pr rn path (env,rb,z as envld) k pr t =
  match k with
  | Decl.Plemma | Decl.Paxiom ->
      let eid = Renaming.get_pr rn pr in
      let tvm = Wtvm.create () in
      let _, _, import = import_w3_term env tvm in
      let spec =
        try Some (import Term.Mvs.empty t);
        with CannotTranslateW3Ec -> None in
      (* FIXME: assert unicity of string in [ax_tparams] *)
      let ax = {
        ax_tparams = Wtvm.tparams tvm;
        ax_spec = spec;
        ax_kind = if k = Decl.Plemma then `Lemma else `Axiom;
        ax_nosmt = false; } in
      let p = EcPath.pqname path eid in
      let env = add_w3_pr env p pr in
      let rb  = rbadd_w3_pr rb p pr in
      env, rb, Zdecl(Th_axiom (eid,ax)) :: z
  | Decl.Pgoal | Decl.Pskip -> envld


let import_decl rn path envld d =
  match d.Decl.d_node with
  | Decl.Dtype ty -> import_w3_tydef rn path envld ty
  | Decl.Ddata ddl ->
    let lty, lc = List.split ddl in
    let envld = List.fold_left (import_w3_tydef rn path) envld lty in
    List.fold_left (import_w3_constructors rn path) envld lc
  | Decl.Dparam ls -> import_w3_ls rn path envld ls
  | Decl.Dlogic lls ->
    let lls = List.map fst lls in
    List.fold_left (import_w3_ls rn path) envld lls
  | Decl.Dind _  -> envld  (* FIXME *)
  | Decl.Dprop (k,pr,t) -> import_w3_pr rn path envld k pr t

let import_decls rn path env rb decls =
  let rec diff ls ls' =
    match ls, ls' with
    | s::ls, s'::ls' when s = s' -> diff ls ls'
    | _, _ -> List.rev ls, ls' in
  let rec close accu ls path z =
    match ls, z, path.EcPath.p_node with
    | [], _, _ -> path, z
    | s::ls, Zenter id:: z, EcPath.Pqname(p,id') ->
        assert (s = id && sym_equal id id');
        close [] ls p (Zdecl (Th_theory (id, (accu, `Concrete))) :: z)
    | _s::_ls, Zenter _id:: _z, _ -> assert false
    | _, Zdecl d::z, _ -> close (d::accu) ls path z
    | _, [], _ -> assert false in
  let open_ ls path z =
    List.fold_left (fun (path, z) s ->
      EcPath.pqname path s, (Zenter s) :: z) (path, z) ls
  in

  let close_open ls ls' path z =
    let ls, ls' = diff ls ls' in
    let path, z = close [] ls path z in
    open_ ls' path z in
  let rec aux ls path (env,rb,z as envld) decls =
    match decls with
    | d::decls ->
        let ids = d.Decl.d_news in
        if Ident.Sid.is_empty ids then aux ls path envld decls
        else
          let id = Ident.Sid.choose ids in
          let (_,_,s) = Theory.restore_path id in
          let ls' = List.rev (List.tl (List.rev s)) in
          let path, z = close_open ls ls' path z in
          let envld = import_decl rn path (env,rb,z) d in
          aux ls' path envld decls
    | [] ->
        let final_close z =
          List.rev_map (function Zdecl d -> d | _ -> assert false) z in
        let _, z = close [] ls path z in
        (env,rb,final_close z) in
  aux [] path (env,rb,[]) decls

let import_w3 env path th rd =
  let rb = rb_empty th in
  let rn = Renaming.init rd th in
  let task = Task.use_export None th in
  let ths = Ident.Mid.remove th.Theory.th_name (Task.used_theories task) in
  let others = Task.used_symbols ths in
  let decls = Task.local_decls task others in
  let _env,rb,ld = import_decls rn path env rb decls in
  let rb = { rb with rb_decl = List.rev rb.rb_decl } in
  ld, RBuse rb

(* ----------------------------------------------------------------------- *)
(* ------------------------ Exporting to why3 ---------------------------- *)
(* ----------------------------------------------------------------------- *)
let preid id =
  Ident.id_fresh (EcIdent.name id)

let str_p p =
  Ident.id_fresh (String.map (fun c -> if c = '.' then '_' else c) p)


let preid_p p = str_p (EcPath.tostring p)
let preid_mp mp = str_p (EcPath.m_tostring mp)
let preid_xp xp = str_p (EcPath.x_tostring xp)

let create_tvsymbol id =
  Ty.create_tvsymbol (preid id)


(* ------------------------ Types -----------------------------------------*)
exception UnboundTypeVariable of EcIdent.t

let trans_pty env p =
  oget (Mp.find_opt p env.env_ty |> omap fst)

let trans_tv env id =
  match Mid.find_opt id env.env_tv with
  | None   -> raise (UnboundTypeVariable id)
  | Some x -> x

let trans_tglob env mp = 
  assert (mp.EcPath.m_args = []); (* tglob should have been normalized *)
  match mp.EcPath.m_top with
  | `Local id -> (try Mid.find id env.env_tv with _ -> assert false)
  | _ -> assert false (* tglob should have been normalized *)

let trans_glob env mp = 
  assert (mp.EcPath.m_args = []); (* tglob should have been normalized *)
  match mp.EcPath.m_top with
  | `Local id -> 
    (try Mid.find id env.env_id with _ -> 
      Format.eprintf "trans_glob %s@." (EcIdent.tostring id);
      assert false)
  | _ -> 
    Format.eprintf "trans_glob %s@." (EcPath.m_tostring mp);
    assert false (* tglob should have been normalized *)
  
let rec trans_ty env ty =
  match ty.ty_node with
  | Tglob mp -> trans_tglob env mp
  | Tunivar _ -> assert false
  | Tvar id -> trans_tv env id
  | Ttuple tys -> Ty.ty_tuple (trans_tys env tys)
  | Tconstr(p,tys) ->
      let id = trans_pty env p in
        Ty.ty_app id (trans_tys env tys)
  | Tfun(t1,t2) -> Ty.ty_func (trans_ty env t1) (trans_ty env t2)

and trans_tys env tys = List.map (trans_ty env) tys

let trans_typarams =
  let trans_tv env ((id, _) : ty_param) = (* FIXME: TC HOOK *)
    let tv = create_tvsymbol id in
    let add o = assert (o = None); Some (Ty.ty_var tv) in
    ({ env with env_tv = Mid.change add id env.env_tv }, tv)
  in
    List.map_fold trans_tv

let trans_tydecl env path td =
  let pid = preid_p path in
  let (env, tparams) = trans_typarams env td.tyd_params in

    match td.tyd_type with
    | `Abstract _ ->                    (* FIXME: TC HOOK *)
        let ts   = Ty.create_tysymbol pid tparams None in
        let decl = Decl.create_ty_decl ts in
          ((ts, `Plain), decl)

    | `Concrete ty ->
        let ty   = trans_ty env ty in
        let ts   = Ty.create_tysymbol pid tparams (Some ty) in
        let decl = Decl.create_ty_decl ts in
          ((ts, `Plain), decl)

    | `Datatype { tydt_ctors = cs } ->
         let ts   = Ty.create_tysymbol pid tparams None in
         let decl = Decl.create_ty_decl ts in
         let env  = add_ts env path (ts, `Plain) decl in
         let ncs  = List.length cs in

         let (cs, wcs) =
           let for1 (c, aty) =
             let cid  = preid_p (EcPath.pqname path c) in
             let aty  = aty |> List.map (trans_ty env) in
             let dom  = tconstr path (List.map (tvar |- fst) td.tyd_params) in
             let dom  = dom |> trans_ty env in
             let cls  = Term.create_lsymbol ~constr:ncs cid aty (Some dom) in
             let ocls = mk_highorder_func cls in
               ((c, cls, ocls), (cls, List.create (List.length aty) None))
           in
             List.split (List.map for1 cs)
         in
         let decl = Decl.create_data_decl [(ts, wcs)] in
           ((ts, `Datatype cs), decl)

    | `Record (_, fields) ->
        let ts     = Ty.create_tysymbol pid tparams None in
        let decl   = Decl.create_ty_decl ts in
        let env    = add_ts env path (ts, `Plain) decl in
        let myself = tconstr path (List.map (tvar |- fst) td.tyd_params) in
        let myself = myself |> trans_ty env in
        let ps     =
          let for1 (f, aty) =
            let fid  = preid_p (EcPath.pqname path f) in
            let aty  = trans_ty env aty in
            let pls  = Term.create_lsymbol fid [myself] (Some aty) in
            let opls = mk_highorder_func pls in
              (f, pls, opls, aty)
          in
            List.map for1 fields in

        let cid  = preid_p (EcPath.pqname path "$record") in
        let csym = Printf.sprintf "mk_%s" (EcPath.basename path) in
        let cls  = Term.create_lsymbol ~constr:1 cid (List.map proj4_4 ps) (Some myself) in
        let ocls = mk_highorder_func cls in
        let decl = Decl.create_data_decl [ts, [cls, List.map (some |- proj4_2) ps]] in

          ((ts, `Record ((csym, cls, ocls), ps)), decl)

(* --------------------------- Formulas ------------------------------- *)
let trans_lv env lv =
  match Mid.find_opt lv env.env_id with
  | None ->
      Printf.eprintf "cannot find %s\n%!" (EcIdent.tostring lv);
      assert false
  | Some x -> x

let trans_mp env p = try Mm.find p env.env_mp with _ -> assert false

let trans_xpv env p = try Mx.find p env.env_xpv with _ -> assert false
let trans_xpf env p = try Mx.find p env.env_xpf with _ -> assert false

let rm_mp_args mp = 
  EcPath.mpath mp.EcPath.m_top []

let is_top_mp mp = 
  match mp.EcPath.m_top with
  | `Local _ | `Concrete(_,None) -> true
  | `Concrete (_, Some _) -> false

let rec trans_mod env mp =
  let args = List.map (trans_mod env) mp.EcPath.m_args in
  let fs = trans_mp env (rm_mp_args mp) in
  if is_top_mp mp then List.fold_left app_mod (Term.fs_app fs [] ty_mod) args 
  else Term.fs_app fs args ty_mod

let rm_xp_args xp = 
  let mp = rm_mp_args xp.EcPath.x_top in
  EcPath.xpath mp xp.EcPath.x_sub

let trans_fun env xp targs =
  let args = List.map (trans_mod env) xp.EcPath.x_top.EcPath.m_args in
  let xp = rm_xp_args xp in
  let fs = trans_xpf env xp in
  Term.fs_app fs args (ty_fun targs)

let trans_pvloc env xp ty = 
  let args = List.map (trans_mod env) xp.EcPath.x_top.EcPath.m_args in
  let xp = rm_xp_args xp in
  let fs = trans_xpv env xp in
  Term.fs_app fs args (ty_var ty)

let trans_pv env pv ty mem =
  let xp = pv.pv_name in
  let mem = trans_lv env mem in
  let ty = trans_ty env ty in
  let v = 
    if is_loc pv then trans_pvloc env xp ty 
    else Term.fs_app (trans_xpv env xp) [] (ty_var ty) in
  get_var v mem 

let create_vsymbol id ty = Term.create_vsymbol (preid id) ty

let add_id env (id, ty) =
  let wid = create_vsymbol id ty in
  let add o = assert (o = None); Some (Term.t_var wid) in
  { env with env_id = Mid.change add id env.env_id }, wid

let add_ids env ids lty =
  assert (List.length lty = List.length ids);
  List.map_fold add_id env (List.combine ids lty)

let t_app p args ty =
  if p.Term.ls_value = None then Term.t_app p args None
  else Term.t_app p args (Some ty)

let prop_of_bool t =
  assert (Ty.oty_equal t.Term.t_ty (Some Ty.ty_bool));
  match t.Term.t_node with
  | Term.Tif(t1,t2,t3) when
      Term.t_equal t2 Term.t_bool_true &&
      Term.t_equal t3 Term.t_bool_false -> t1
  | _ ->
      if Term.t_equal t Term.t_bool_true then Term.t_true
      else if Term.t_equal t Term.t_bool_false then Term.t_false
      else Term.t_equ t Term.t_bool_true

let force_prop t =
  if t.Term.t_ty = None then t
  else prop_of_bool t

let bool_of_prop t =
  assert (t.Term.t_ty = None);
  match t.Term.t_node with
  | Term.Ttrue -> Term.t_bool_true
  | Term.Tfalse -> Term.t_bool_false
  | Term.Tapp(ls,[t;tt]) when
      Term.t_equal tt Term.t_bool_true &&
      Term.ls_equal ls Term.ps_equ -> t
  | _ ->
      Term.t_if t Term.t_bool_true Term.t_bool_false

let force_bool t = if t.Term.t_ty = None then bool_of_prop t else t

let mk_not args  =
  match args with
  | [e] -> Term.t_not e
  | _ -> assert false

let mk_pred2 f l =
  match l with
  | [e1;e2] -> f e1 e2
  | _ -> assert false

let mk_anda = mk_pred2 Term.t_and_asym
let mk_and = mk_pred2 Term.t_and
let mk_ora  = mk_pred2 Term.t_or_asym
let mk_or  = mk_pred2 Term.t_or
let mk_imp = mk_pred2 Term.t_implies
let mk_iff = mk_pred2 Term.t_iff
let mk_eq  = mk_pred2 Term.t_equ

let trans_op env p tys =
  match core_op_kind p with
  | Some (`True     ) -> ([],None), w3_ls_true, fun _ -> Term.t_true
  | Some (`False    ) -> ([],None), w3_ls_false, fun _ -> Term.t_false
  | Some (`Not      ) -> ([None],None), w3_ls_not, mk_not
  | Some (`And `Asym) -> ([None;None],None), w3_ls_anda, mk_anda
  | Some (`And `Sym ) -> ([None;None],None), w3_ls_and, mk_and
  | Some (`Or  `Asym) -> ([None;None],None), w3_ls_ora, mk_ora
  | Some (`Or  `Sym ) -> ([None;None],None), w3_ls_or, mk_or
  | Some (`Imp      ) -> ([None;None],None), w3_ls_imp, mk_imp
  | Some (`Iff      ) -> ([None;None],None), w3_ls_iff, mk_iff
  | Some (`Eq       ) ->
      let ty = trans_ty env (List.hd tys) in
      ([Some ty;Some ty],None), w3_ls_eq, mk_eq

  | _ ->
      let ls,ls', tvs =
        match Mp.find_opt p env.env_op with
        | None ->
            raise (CannotTranslate "trans_op")
        | Some x -> x in
      let mtv = 
        List.fold_left2 (fun mtv tv ty ->
          Ty.Mtv.add tv (trans_ty env ty) mtv) Ty.Mtv.empty
          tvs tys in
      let targs = List.map (fun t -> Some (Ty.ty_inst mtv t)) ls.Term.ls_args in
      let tres  =  ls.Term.ls_value |> omap (Ty.ty_inst mtv) in
      let mk args = Term.t_app ls args tres in
      (targs,tres), ls', mk

let apply_highorder f args =
  List.fold_left (fun f a -> Term.t_func_app f (force_bool a)) f args

let cast_arg a ty =
  match a.Term.t_ty, ty with
  | None, None -> a
  | None, Some _ -> force_bool a
  | Some _, None -> force_prop a
  | Some _,Some _ -> a

let cast_app mk args targs = mk (List.map2 cast_arg args targs)

let rec highorder_type targs tres =
  match targs with
  | [] -> odfl Ty.ty_bool tres
  | a::targs -> Ty.ty_func a (highorder_type targs tres)

let trans_app env p tys args =
  let (targs,tres), ls', mk = trans_op env p tys in
  let arity = List.length targs in
  let nargs = List.length args in
  if arity = nargs then cast_app mk args targs
  else if arity < nargs then
    let args1,args2 = List.take_n arity args in
    apply_highorder (cast_app mk args1 targs) args2
  else (* arity > nargs *)
    let targs = List.map (odfl Ty.ty_bool) targs in
    let fty = highorder_type targs tres in
    apply_highorder (Term.fs_app ls' [] fty) args

let destr_ty_tuple t =
  match t.Ty.ty_node with
  | Ty.Tyapp (ts, lt) -> assert (Ty.is_ts_tuple ts); lt
  | _ -> assert false

let merge_branches lb =
  if List.exists (fun b -> b.Term.t_ty = None) lb then List.map force_prop lb
  else lb

let trans_gty env gty =
  match gty with
  | GTty ty   -> env, trans_ty env ty
  | GTmodty _ -> raise (CannotTranslate "binding of module")
  | GTmem   mt -> 
    match mt with
    | None -> env, ty_mem 
    | Some lmt ->
      let xp = EcMemory.lmt_xpath lmt in 
      let tparams = List.map (fun _ -> ty_mod) xp.EcPath.x_top.EcPath.m_args in
      let xp = rm_xp_args xp in
      let add id (p,ty) env =
        match p with
        | Some _ -> env
        | None ->
          let ty = trans_ty env ty in
          let xp = EcPath.xqname xp id in
          if Mx.mem xp env.env_xpv then
            let ls = Mx.find xp env.env_xpv in
            assert (List.all2 Ty.ty_equal ls.Term.ls_args tparams);
            assert (Ty.oty_equal ls.Term.ls_value (Some (ty_var ty)));
            env
          else
            let ls = Term.create_fsymbol (preid_xp xp) tparams (ty_var ty) in
            let decl = Decl.create_param_decl ls in
            { env with
              env_xpv = Mx.add xp ls env.env_xpv;
              logic_task = add_decl_with_tuples env.logic_task decl } in
      let env = Msym.fold add (EcMemory.lmt_bindings lmt) env in
      env, ty_mem

let trans_gtys env gtys =
  List.map_fold trans_gty env gtys


let trans_form env f =
  let env = ref env in
  let save () = !env.env_id in
  let restore mid = env := { !env with env_id = mid} in
  let rb  = ref [] in
  
  let trans_proj n p = 
    let mn = 
      try Mint.find n !env.env_proj with Not_found -> Mint.empty in
    try Mint.find p mn with Not_found ->
      let tvs = 
        Array.init n (fun _ -> Ty.create_tvsymbol (Ident.id_fresh "a")) in
      let ts = Array.map Ty.ty_var tvs in
      let t = Ty.ty_tuple (Array.to_list ts) in
      let tp = ts.(p) in
      let pat = Array.map (fun t -> Term.pat_wild t) ts in
      let vp = Term.create_vsymbol (Ident.id_fresh "v") tp in
      pat.(p) <- Term.pat_var vp;
      let br =
        Term.t_close_branch 
          (Term.pat_app (Term.fs_tuple n) (Array.to_list pat) t) 
          (Term.t_var vp) in
      let va = Term.create_vsymbol (Ident.id_fresh "p") t in
      let body = Term.t_case (Term.t_var va) [ br ] in
      let s = Format.sprintf "proj%i_%i" n p in
      let ls = Term.create_lsymbol (Ident.id_fresh s) [t] (Some tp) in
      let decl = Decl.create_logic_decl [Decl.make_ls_defn ls [va] body ] in
      let mn = Mint.add p ls mn in
      env := {!env with
        logic_task = add_decl_with_tuples !env.logic_task decl;
        env_proj   = Mint.add n mn !env.env_proj
      };
      rb := RBproj(n,p,ls,decl)::!rb;
      ls in
        

  let rec trans_form f =
    match f.f_node with
    | Fquant(q,b,fq) ->
      let mid = save () in
      let ids, tys = List.split b in
      let env0, tys = trans_gtys !env tys in
      let env1, vs  = add_ids env0 ids tys in
      env := env1;
      let fq = trans_form fq in
      let res =
        match q with
        | Lforall -> Term.t_forall_close vs [] (force_prop fq)
        | Lexists -> Term.t_exists_close vs [] (force_prop fq)
        | Llambda -> trans_lambda vs fq in
      restore mid;
      res
    | Fif(f1,f2,f3) ->
      let f1 = trans_form f1 in
      let f2 = trans_form f2 in
      let f3 = trans_form f3 in
      let f2,f3 =
        match merge_branches [f2;f3] with
        | [f2;f3] -> f2, f3
        | _ -> assert false in
      Term.t_if_simp (force_prop f1) f2 f3

    | Flet(lp,f1,f2) ->
      let mid = save () in
      let f1 = trans_form_b f1 in
      let res = 
        match lp with
        | LSymbol (id,_) ->
          let env0, id = add_id !env (id, Term.t_type f1) in
          env := env0;
          let f2 = trans_form f2 in
          Term.t_let f1 (Term.t_close_bound id f2)
        | LTuple ids ->
            let ids = List.map fst ids in
            let t1 = Term.t_type f1 in
            let env0, ids = add_ids !env ids (destr_ty_tuple t1) in
            env := env0;
            let pat =
              Term.pat_app (Term.fs_tuple (List.length ids))
                (List.map Term.pat_var ids) t1 in
            let f2 = trans_form f2 in
            let br = Term.t_close_branch pat f2 in
            Term.t_case f1 [br]
        | LRecord (recp, fields) ->
            let ctor =
              match Mp.find_opt recp (!env).env_ty with
              | Some (_, `Record ((_, ctor), _)) -> ctor
              | _ -> assert false in
            let pat =
              let pat =
                List.map (fun (x, ty) ->
                  let ty = trans_ty !env ty in
                  let v  =
                    match x with
                    | None   -> None
                    | Some x ->
                        let env0, v = add_id !env (x, ty) in
                          env := env0; Some v
                  in
                    match v with
                    | None   -> Term.pat_wild ty
                    | Some v -> Term.pat_var v)
                  fields
              in
                Term.pat_app ctor pat (Term.t_type f1) in
            let f2 = trans_form f2 in
            let br = Term.t_close_branch pat f2 in
            Term.t_case f1 [br]
      in
        restore mid; res

    | Fint n ->
        let n = Number.ConstInt(Number.int_const_dec (string_of_int n)) in
        Term.t_const n

    | Flocal id -> trans_lv !env id

    | Fop(p,tys) -> trans_app !env p tys []

    | Fapp({f_node = Fop(p,tys) },args) ->
      let args = List.map trans_form args in
      trans_app !env p tys args

    | Fapp(e,args) ->
      let args = List.map trans_form args in
      apply_highorder (trans_form e) args

    | Ftuple args ->
      let args = List.map trans_form_b args in
      Term.t_tuple args

    | Fproj(f,i) ->
      let a = trans_form f in
      let ty = oget (a.Term.t_ty) in
      let n = 
        match ty.Ty.ty_node with
        | Ty.Tyapp(_,targs) -> List.length targs
        | _ -> assert false in
      let ls = trans_proj n i in
      Term.t_app_infer ls [a] 
      
    | FhoareF _   -> raise (CannotTranslate "FhoareF")
    | FhoareS _   -> raise (CannotTranslate "FhoareS")
    | FbdHoareF _ -> raise (CannotTranslate "FbdHoareF")
    | FbdHoareS _ -> raise (CannotTranslate "FbdHoareS")
    | FequivF _   -> raise (CannotTranslate "FequivF")
    | FeagerF _   -> raise (CannotTranslate "FeagerF")
    | FequivS _   -> raise (CannotTranslate "FequivS")

    | Fpvar(pv,m) ->
        let pv = trans_pv !env pv f.f_ty m in
        pv

    | Fglob(mp,m) ->
      let mo = trans_glob !env mp in
      let mem = trans_lv !env m in
      get_var mo mem

    | Fpr pr ->
        let mem   = trans_lv !env pr.pr_mem in
        let args  = trans_form_b pr.pr_args in
        let f = 
          trans_fun !env pr.pr_fun (oget args.Term.t_ty) in
        let mid = save () in
        let env0, ty = trans_gty !env (GTmem None) in
        let env1, vs  = add_id env0 (EcCoreFol.mhr, ty) in
        env := env1;
        let evbody = trans_form pr.pr_event in
        let ev = trans_lambda [vs] evbody in
        restore mid;
        getpr f mem args ev

  and trans_form_b f = force_bool (trans_form f)

  and trans_lambda vs body =
    (* TODO how to share lambda with free variable *)
    try Mta.find (vs,body) !env.env_lam 
    with Not_found ->
    (* We compute the free variable of the lambda *)
      let fv     =
        List.fold_left (fun s x -> Term.Mvs.remove x s)
          (Term.t_vars body) vs in
      let fv_ids = Term.Mvs.keys fv in
      let tfv = List.map (fun v -> v.Term.vs_ty) fv_ids in
      let tvs = List.map (fun v -> v.Term.vs_ty) vs in
      let codom = 
        if body.Term.t_ty = None then Ty.ty_bool else oget body.Term.t_ty in
      (* We create the symbol corresponding to the lambda *)
      let lam_sym = Ident.id_fresh "unamed_lambda" in 
      let flam_sym = 
        Term.create_fsymbol lam_sym tfv 
          (List.fold_right Ty.ty_func tvs codom) in
      let decl_sym = Decl.create_param_decl flam_sym in
      (* We create the spec *)
      let fvargs   = List.map Term.t_var fv_ids in
      let vsargs   = List.map Term.t_var vs in
      let flam_app = 
        Term.t_app_infer flam_sym fvargs in
      let flam_fullapp = 
        List.fold_left Term.t_func_app flam_app vsargs in
      let concl = 
        if body.Term.t_ty = None then Term.t_iff (force_prop flam_fullapp) body
        else Term.t_equ flam_fullapp body in
      let spec = Term.t_forall_close (fv_ids@vs) [] concl in
      let spec_sym = 
        Decl.create_prsymbol (Ident.id_fresh "unamed_lambda_spec") in
      let decl_spec = Decl.create_prop_decl Decl.Paxiom spec_sym spec in
      rb := RBfun(decl_sym,decl_spec, (vs,body), flam_app) :: !rb;
      env := { !env with
        env_lam = Mta.add (vs,body) flam_app !env.env_lam;
        logic_task =
          List.fold_left add_decl_with_tuples !env.logic_task
            [decl_sym;decl_spec] };
      flam_app in

  let f = trans_form f in
  !env, !rb, f

let destr_ty_fun ty =
  let rec aux tys codom =
    match codom.Ty.ty_node with
    | Ty.Tyapp(ts,[dom;codom]) when Ty.ts_equal ts Ty.ts_func ->
      aux (dom::tys) codom
    | _ -> List.rev tys, codom in
  aux [] ty

let trans_oper_body env path wparams ty body =
  let pid = preid_p path in

  let body = 
    match body with
    | OB_oper None -> None
    | OB_oper (Some (OP_Plain  o))  -> Some (`Plain (EcCoreFol.form_of_expr EcCoreFol.mhr o))
    | OB_oper (Some (OP_Fix    o))  -> Some (`Fix o)
    | OB_oper (Some (OP_Constr _))  -> assert false
    | OB_oper (Some (OP_Record _))  -> assert false
    | OB_oper (Some (OP_Proj   _))  -> assert false
    | OB_oper (Some (OP_TC      ))  -> assert false
    | OB_pred o -> o |> omap (fun x -> `Plain x)
  in
    match body with
    | None ->
        let ty = trans_ty env ty in
        let dom, codom = destr_ty_fun ty in
        let codom = if Ty.ty_equal codom Ty.ty_bool then None else Some codom in
          (env, [], Term.create_lsymbol pid dom codom, None)

    | Some (`Plain body) ->
        let bd, body =
          match body.f_node with
          | Fquant (Llambda, bd, f) -> (bd, f)
          | _ -> ([], body) in
        let ids, dom   = List.split bd in    
        let env, dom   = trans_gtys env dom in
        let env, vs    = add_ids env ids dom in
        let env, rb, f = trans_form env body in
        let f = 
          if   Ty.oty_equal f.Term.t_ty (Some Ty.ty_bool)
          then force_prop f 
          else f
        in
          (env, rb, Term.create_lsymbol pid dom f.Term.t_ty, Some (vs, f))

    | Some (`Fix o) ->
        let (env, dom, vs) =
          let ids, dom = List.split o.opf_args in
          let dom      = List.map (trans_ty env) dom in
          let env, vs  = add_ids env ids dom in
            (env, dom, vs)
        in

        let ls      = Term.create_lsymbol pid dom (Some (trans_ty env o.opf_resty)) in
        let pterm   = List.map (List.nth vs) (fst o.opf_struct) in
        let ptermty = List.map (fun x -> x.Term.vs_ty) pterm in
        let ptermc  = List.length ptermty in
        let ops = env.env_op in
        let env = { env with env_op = Mp.add path (ls, ls, wparams) env.env_op; } in

        let ((env, rb), ptns) =
          let rec compile ((env, rb), ptns) (ctors, m) =
            match m with
            | OPB_Branch bs ->
                Parray.fold_left
                  (fun ((env, rb), ptns) b ->
                    let cl = proj3_1 (oget (Mp.find_opt (fst b.opb_ctor) env.env_op)) in
                      compile ((env, rb), ptns) (cl :: ctors, b.opb_sub))
                  ((env, rb), ptns) bs

            | OPB_Leaf (locals, e) ->
                let ctors = List.rev ctors in
                let env, vs =
                  List.map_fold
                    (fun env locals ->
                       let ids, sig_   = List.split locals in
                       let sig_        = List.map (trans_ty env) sig_ in
                         add_ids env ids sig_)
                    env locals
                in

                let env, rb1, e = trans_form env (EcCoreFol.form_of_expr EcCoreFol.mhr e) in

                let ptn =
                  let for1 (cl, vs) pty =
                    let ptn = List.map Term.pat_var vs in
                    let ptn = Term.pat_app cl ptn pty in
                      ptn
                  in
                    try  List.map2 for1 (List.combine ctors vs) ptermty
                    with Failure _ -> assert false
                in

                let ptn =
                  if   ptermc > 1
                  then Term.pat_app (Term.fs_tuple ptermc) ptn (Ty.ty_tuple ptermty)
                  else oget (List.ohead ptn)
                in
                  ((env, rb1@rb), (ptn, e)::ptns)
          in
            compile ((env, []), []) ([], o.opf_branches)
        in

        let ptns = List.rev ptns in
        let ptns = List.map (fun (p, e) -> Term.t_close_branch p (force_bool e)) ptns in
        let mtch =
          if   ptermc > 1
          then Term.t_tuple (List.map Term.t_var pterm)
          else Term.t_var (oget (List.ohead pterm)) in
        let body = Term.t_case mtch ptns in
          ({ env with env_op = ops; }, rb, ls, Some (vs, body))

let trans_oper env path op =
  let mty = env.env_tv in
  let mid = env.env_id in
  let env, wparams = trans_typarams env op.op_tparams in
  let env, rb, ls, body = trans_oper_body env path wparams op.op_ty op.op_kind in
  let decl = 
    match body with
    | None -> Decl.create_param_decl ls
    | Some(ids,f) -> Decl.create_logic_decl [Decl.make_ls_defn ls ids f]
  in
    ({ env with env_tv = mty; env_id = mid; }, rb, ls, wparams, decl)

let add_ty env path td =
  let (ts, decl) = trans_tydecl env path td in
    (add_ts env path ts decl, [RBty (path, ts, decl)])

let add_op env path op =
  try
    let env, rb, ls, wparams, decl = trans_oper env path op in
    let odecl = mk_highorder_func ls in
    let env = add_ls env path ls wparams decl odecl in
    let rb = RBop(path,(ls,wparams),decl,odecl)::rb in
      (env, rb)
  with CannotTranslate _ -> (env, [])

let add_ax env path ax =
  let pr = Decl.create_prsymbol (preid_p path) in
  let mty = env.env_tv in
  let mid = env.env_id in
  let env, _ = trans_typarams env ax.ax_tparams in
  match ax.ax_spec with
  | None -> assert false
  | Some f ->
    let env, rb = 
      try
        let env,rb,f = trans_form env f in
        let decl = Decl.create_prop_decl Decl.Paxiom pr (force_prop f) in
        add_pr env path pr decl, RBax(path,pr,decl)::rb
      with CannotTranslate _ ->
        { env with env_tv = mty}, [] in
    { env with env_tv = mty; env_id = mid }, rb

let add_mod_exp_mp env mp me =
  assert (mp.EcPath.m_args = []);
  assert (match mp.EcPath.m_top with
  | `Local _ | `Concrete(_, None) -> true
  | _ -> false);

  let is_alias = function ME_Alias _ -> true | _ -> false in
  match me.me_body with
  | ME_Alias (arity,_) ->
    if arity = 0 then env, [] 
    else
      let ls = Term.create_fsymbol (preid_mp mp) [] ty_mod in
      add_mp env mp ls, [RBmp(mp,ls)] 
  | _ ->
    let ls = Term.create_fsymbol (preid_mp mp) [] ty_mod in
    let env = ref (add_mp env mp ls) in
    let rb  = ref [RBmp(mp,ls)] in
    let tparams = List.map (fun _ -> ty_mod) me.me_sig.mis_params in
    let add_xpv xp ls = 
      env := add_xpv !env xp ls;
      rb  := RBxpv(xp,ls) :: !rb in
    let add_gpv xp ty =
      assert (not (Mx.mem xp !env.env_xpv));
      let ty = trans_ty !env ty in
      let ls = Term.create_fsymbol (preid_xp xp) [] (ty_var ty) in
      add_xpv xp ls in
    let add_lpv xp ty =
      assert (not (Mx.mem xp !env.env_xpv));
      let ty = trans_ty !env ty in
      let ls = Term.create_fsymbol (preid_xp xp) tparams (ty_var ty) in
      add_xpv xp ls in
    let rec add_comps mp comps = List.iter (add_comp mp) comps
    and add_comp mp comp =
      match comp with
      | MI_Module me  -> 
        if not (is_alias me.me_body) then begin 
          let mp = EcPath.mqname mp me.me_name in
          let ls = Term.create_fsymbol (preid_mp mp) tparams ty_mod in
          env := add_mp !env mp ls;
          rb  := RBmp(mp,ls) :: !rb;
          add_comps mp me.me_comps
        end
      | MI_Variable v -> 
        add_gpv (EcPath.xpath_fun mp v.v_name) v.v_type
      | MI_Function f -> 
        let tys =trans_ty !env f.f_sig.fs_arg in
        let xp = EcPath.xpath_fun mp f.f_name in
        let ls = Term.create_fsymbol (preid_xp xp) tparams (ty_fun tys) in
        env := add_xpf !env xp ls;
        rb  := RBxpf(xp,ls) :: !rb;
        add_lpv (EcPath.xqname xp "param") f.f_sig.fs_arg;
        add_lpv (EcPath.xqname xp "res") f.f_sig.fs_ret in
    add_comps mp me.me_comps;
    !env, !rb

let add_mod_exp env p me = add_mod_exp_mp env (mpath_crt p [] None) me
  
let check_w3_formula ?notify pi task f =
  let pr   = Decl.create_prsymbol (Ident.id_fresh "goal") in
  let decl = Decl.create_prop_decl Decl.Pgoal pr f in
  let task = add_decl_with_tuples task decl in
    EcProvers.execute_task ?notify pi task = Some true

exception CannotProve of axiom

type me_of_mt = EcIdent.t -> module_type -> mod_restr -> module_expr

let trans_tv env id = 
  let ts = Ty.create_tysymbol (preid id) [] None in
  let decl = Decl.create_ty_decl ts in
  { env with
    env_tv = Mid.add id (Ty.ty_app ts []) env.env_tv;
    logic_task = add_decl_with_tuples env.logic_task decl }
  
let add_abs_mod me_of_mt env id mt restr =
  let me = me_of_mt id mt restr in
  let env = trans_tv env id in
        (* represent the type of the glob memory of the module *)
  let ty = Mid.find id env.env_tv in
  let vty = ty_var ty in
  let ls = Term.create_fsymbol (preid id) [] vty in
  let decl = Decl.create_param_decl ls in
  let env = 
    { env with env_id = Mid.add id (t_app ls [] vty) env.env_id;
      logic_task = add_decl_with_tuples env.logic_task decl } in
  let nenv,_ = add_mod_exp_mp env (EcPath.mident id) me in
  nenv

(* -------------------------------------------------------------------- *)
open EcProvers

type notify = EcProvers.notify

let rec filter_task_r w3env (hints : hints) task = (* FIXME: not tail-rec *)
  match task with
  | None -> None
  | Some task ->
      let aout = filter_task_r w3env hints task.Task.task_prev in
        match task.Task.task_decl.Theory.td_node with
        | Theory.Decl { Decl.d_node = Decl.Dprop (_, x, _) } -> begin
            match Decl.Mpr.find_opt x w3env.env_rax with
            | None   -> Task.add_tdecl aout task.Task.task_decl
            | Some p -> begin
                match Hints.mem p hints with
                | true  -> Task.add_tdecl aout task.Task.task_decl
                | false -> aout
            end
        end
        | _ -> Task.add_tdecl aout task.Task.task_decl

let filter_task w3env hints task =
  if   hints = Hints.full
  then task
  else filter_task_r w3env hints task

(* -------------------------------------------------------------------- *)
let check_goal ?notify me_of_mt env pi hints (hyps, concl) =
  let env = ref env in
  let trans_tv id = env := trans_tv !env id in

  let trans_hyp (id,ld) =
    try 
      match ld with
      | LD_var (ty,body) ->
        let codom = trans_ty !env ty in
        let pid = preid id in
        let ls = Term.create_fsymbol pid [] codom in
        let decl = match body with
          | None -> Decl.create_param_decl ls
          | Some e ->
            let nenv, _, e = trans_form !env e in
            env := nenv;
            Decl.create_logic_decl [Decl.make_ls_defn ls [] (force_bool e)] in
        env := 
          { !env with env_id = Mid.add id (t_app ls [] codom) !env.env_id;
            logic_task = add_decl_with_tuples !env.logic_task decl }
          
      | LD_hyp f ->
        let nenv, _, f = trans_form !env f in
        env := nenv;
        let pr = Decl.create_prsymbol (preid id) in
        let decl = Decl.create_prop_decl Decl.Paxiom pr (force_prop f) in
        env :=
          { !env with logic_task = add_decl_with_tuples !env.logic_task decl }
          
      | LD_mem  mt ->
        let env0, _ = trans_gty !env (GTmem mt) in 
        let ls = Term.create_fsymbol (preid id) [] ty_mem in
        let decl = Decl.create_param_decl ls in
        env := 
          { env0 with env_id = Mid.add id (t_app ls [] ty_mem) env0.env_id;
            logic_task = add_decl_with_tuples env0.logic_task decl }
          
      | LD_modty (mt,restr) ->
        env := add_abs_mod me_of_mt !env id mt restr

      | LD_abs_st _ -> ()

    with CannotTranslate _ -> ()
  in
  List.iter trans_tv (List.map fst hyps.h_tvar);
  List.iter trans_hyp (List.rev hyps.h_local);
  let env, _, concl = trans_form !env concl in
  let task = filter_task env hints env.logic_task in
    check_w3_formula ?notify pi task (force_prop concl)
