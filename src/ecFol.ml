open EcUtils
open EcMaps
open EcIdent
open EcTypes

type quantif = 
  | Lforall
  | Lexists

type binding = (EcIdent.t * ty) list

module Side : sig
  type t = int
  (* For non relational formula *)
  val mono : t 
  (* For relational formula *)
  val left : t
  val right : t 
end = struct
  type t = int 
  let mono = 0
  let left = 1
  let right = 2
end

type form = { 
    f_node : f_node;
    f_ty   : ty;
    f_fv   : Sid.t }

and f_node = 
  | Fquant of quantif * binding * form
  | Fif    of form * form * form
  | Flet   of lpattern * form * form
  | Fint    of int                               (* int. literal        *)
  | Flocal  of EcIdent.t                         (* Local variable      *)
  | Fpvar   of EcTypes.prog_var * ty * Side.t    (* sided symbol        *)
  | Fapp    of EcPath.path * form list           (* op/pred application *)
  | Ftuple  of form list                         (* tuple constructor   *)

let fv f = f.f_fv 
let ty f = f.f_ty

let fv_node = function
  | Fint _ | Fpvar _ -> Sid.empty
  | Flocal id -> Sid.singleton id
  | Fquant(_,b,f) -> 
      List.fold_left (fun s (id,_) -> Sid.remove id s) (fv f) b 
  | Fif(f1,f2,f3) -> 
      Sid.union (fv f1) (Sid.union (fv f2) (fv f3))
  | Flet(lp, f1, f2) ->
      let fv2 = 
        List.fold_left (fun s id -> Sid.remove id s) (fv f2) (ids_of_lpattern lp) in
      Sid.union (fv f1) fv2
  | Fapp(_,args) | Ftuple args ->
      List.fold_left (fun s f -> Sid.union s (fv f)) Sid.empty args
  
let mk_form node ty = 
  { f_node = node;
    f_ty   = ty;
    f_fv  = fv_node node }

let ty_bool = tbool
let ty_int = tint 
let ty_unit = tunit

let f_app x args ty = 
  mk_form (Fapp(x,args)) ty

let f_true = f_app EcCoreLib.p_true [] ty_bool
let f_false = f_app EcCoreLib.p_false [] ty_bool
let f_bool b = if b then f_true else f_false
let f_int n = mk_form (Fint n) ty_int

let f_not f = f_app EcCoreLib.p_not [f] ty_bool
let f_and f1 f2 = f_app EcCoreLib.p_and [f1;f2] ty_bool
let f_or  f1 f2 = f_app EcCoreLib.p_or [f1;f2] ty_bool
let f_imp f1 f2 = f_app EcCoreLib.p_imp [f1;f2] ty_bool
let f_iff f1 f2 = f_app EcCoreLib.p_iff [f1;f2] ty_bool

let f_eq f1 f2 = f_app EcCoreLib.p_eq [f1;f2] ty_bool

let f_local x ty = mk_form (Flocal x) ty
let f_pvar x ty s = mk_form (Fpvar(x,ty,s)) ty

let f_tuple args = 
  mk_form (Ftuple args) (Ttuple (List.map ty args))

let f_if f1 f2 f3 = mk_form (Fif(f1,f2,f3)) f2.f_ty 

let f_let q f1 f2 = mk_form (Flet(q,f1,f2)) f2.f_ty (* FIXME rename binding *)

let f_quant q b f = 
  if b = [] then f else
  mk_form (Fquant(q,b,f)) ty_bool (* FIXME rename binding *)

let f_exists b f = f_quant Lexists b f 
let f_forall b f = f_quant Lforall b f

type destr_error =
  | Destr_and
  | Destr_or
  | Destr_imp
  | Destr_forall
  | Destr_exists

exception DestrError of destr_error

let destr_error e = raise (DestrError e)

let destr_and f = 
  match f.f_node with
  | Fapp(p,[f1;f2]) when EcPath.p_equal p EcCoreLib.p_and -> f1,f2
  | _ -> destr_error Destr_and 

let destr_or f = 
  match f.f_node with
  | Fapp(p,[f1;f2]) when EcPath.p_equal p EcCoreLib.p_or -> f1,f2
  | _ -> destr_error Destr_or 

let destr_imp f = 
  match f.f_node with
  | Fapp(p,[f1;f2]) when EcPath.p_equal p EcCoreLib.p_imp -> f1,f2
  | _ -> destr_error Destr_imp 

let destr_forall1 f = 
  match f.f_node with
  | Fquant(Lforall,(x,t)::bd,p) -> x,t,f_forall bd p 
  | _ -> destr_error Destr_forall

let destr_exists1 f = 
  match f.f_node with
  | Fquant(Lexists,(x,t)::bd,p) -> x,t,f_exists bd p 
  | _ -> destr_error Destr_exists

(* -------------------------------------------------------------------- *)

let is_and f = 
  match f.f_node with
  | Fapp(p,_) when EcPath.p_equal p EcCoreLib.p_and -> true
  | _ -> false 

let is_or f = 
  match f.f_node with
  | Fapp(p,_) when EcPath.p_equal p EcCoreLib.p_or -> true
  | _ -> false 

let is_imp f = 
  match f.f_node with
  | Fapp(p,_) when EcPath.p_equal p EcCoreLib.p_imp -> true
  | _ -> false

let is_forall f = 
  match f.f_node with
  | Fquant(Lforall,_,_) -> true
  | _ -> false

let is_exists f = 
  match f.f_node with
  | Fquant(Lexists,_,_) -> true
  | _ -> false
  
(* -------------------------------------------------------------------- *)

let map gt g f = 
  match f.f_node with
  | Fquant(q,b,f) -> 
      f_quant q (List.map (fun (x,ty) -> x, gt ty) b) (g f)
  | Fif(f1,f2,f3) -> f_if (g f1) (g f2) (g f3)
  | Flet(lp,f1,f2) -> f_let lp (g f1) (g f2)
  | Fint i -> f_int i 
  | Flocal id -> f_local id (gt f.f_ty)
  | Fpvar(id,ty,s) -> f_pvar id (gt ty) s
  | Fapp(p,es) -> f_app p (List.map g es) (gt f.f_ty)
  | Ftuple es -> f_tuple (List.map g es) 

(* -------------------------------------------------------------------- *)

module Fsubst = struct

  let mapty onty = 
    let rec aux f = map onty aux f in
    aux 

  let uni uidmap = mapty (Tuni.subst uidmap)

  let idty ty = ty 

  let subst_local id fid =
    let rec aux f = 
      match f.f_node with
      | Flocal id1 when EcIdent.id_equal id id1 -> fid
      | _ -> map idty aux f in
    aux

  let subst_tvar mtv = mapty (EcTypes.Tvar.subst mtv)

end

(* -------------------------------------------------------------------- *)
(*    Basic construction for building the logic                         *)

type local_kind =
  | LD_var of ty * form option
  | LD_hyp of form  (* of type bool *)

type l_local = EcIdent.t * local_kind

type hyps = {
    h_tvar  : EcIdent.t list;
    h_local : l_local list;
  }

type l_decl = hyps * form

type prover_info = unit (* FIXME *)

type rule_name = 
  | RN_admit
  | RN_clear of EcIdent.t 
  | RN_prover of prover_info 
  | RN_local  of EcIdent.t
    (* H:f in G    ===>  E,G |- f  *)
  | RN_global of EcPath.path * ty list
    (* p: ['as], f in E  ==> E,G |- f{'as <- tys} *)


  | RN_exc_midle 
    (* E;G |- A \/ !A *)

  | RN_eq of EcIdent.t * form
    (* E;G |- t ~ u   E;G |- P(t)  ===> E;G |- P(u)  *)
    (* where ~ := = | <=>                            *)

  | RN_and_I 
    (* E;G |- A   E;G |- B   ===> E;G |- A /\ B *) 

  | RN_or_I  of bool  (* true = left; false = right *)
    (* E;G |- A_i   ===> E;G |- A_1 \/ A_2 *) 

  | RN_imp_I 
    (* E;G,A |- B   ===> E;G |- A => B *) 

  | RN_forall_I 
    (* E,x:T; G |- P ===> E;G |- forall (x:T), P *)

  | RN_exists_I of form
    (* E;G |- P{x<-t}  ===> E;G |- exists (x:T), P *)

  | RN_and_E 
    (* E;G |- A /\ B   E;G |- A => B => C                ===> E;G |- C *)

  | RN_or_E  
    (* E;G |- A \/ B   E;G |- A => C  E;G |- B => C      ===> E;G |- C *)
                
  | RN_imp_E 
    (* E;G |- A => B   E;G |- A  E;G |- B => C           ===> E;G |- C *)
                     
  | RN_forall_E of form 
    (* E;G |- forall x:t, P  E;G |- P(t) => C            ===> E;G |- C *)

  | RN_exists_E 
    (* E;G |- exists x:t, P  E;G |- forall x:t, P => C   ===> E;G |- C *)

type rule = (rule_name, l_decl) EcBaseLogic.rule
type judgment = (rule_name, l_decl) EcBaseLogic.judgment

module LDecl = struct

  type error = 
    | UnknownSymbol   of EcSymbols.symbol 
    | UnknownIdent    of EcIdent.t
    | NotAVariable    of EcIdent.t
    | NotAHypothesis  of EcIdent.t
    | CanNotClear     of EcIdent.t * EcIdent.t
    | DuplicateIdent  of EcIdent.t
    | DuplicateSymbol of EcSymbols.symbol

  exception Ldecl_error of error

  let error e = raise (Ldecl_error e)

  let lookup s hyps = 
    try 
      List.find (fun (id,_) -> s = EcIdent.name id) hyps.h_local 
    with _ -> error (UnknownSymbol s)

  let lookup_by_id id hyps = 
    try 
      List.assoc_eq EcIdent.id_equal id hyps.h_local 
    with _ -> error (UnknownIdent id)

  let get_hyp = function
    | (id, LD_hyp f) -> (id,f)
    | (id,_) -> error (NotAHypothesis id) 

  let get_var = function
    | (id, LD_var (ty,_)) -> (id, ty)
    | (id,_) -> error (NotAVariable id) 

  let lookup_hyp s hyps = get_hyp (lookup s hyps)

  let has_hyp s hyps = 
    try ignore(lookup_hyp s hyps); true
    with _ -> false

  let lookup_hyp_by_id id hyps = snd (get_hyp (id, lookup_by_id id hyps))

  let lookup_var s hyps = get_var (lookup s hyps) 

  let lookup_var_by_id id hyps = snd (get_var (id, lookup_by_id id hyps))

  let has_symbol s hyps = 
    try ignore(lookup s hyps); true with _ -> false 

  let has_ident id hyps = 
    try ignore(lookup_by_id id hyps); true with _ -> false 

  let check_id id hyps = 
    if has_ident id hyps then error (DuplicateIdent id)
    else 
      let s = EcIdent.name id in
      if s <> "_" && has_symbol s hyps then error (DuplicateSymbol s) 

  let add_local id ld hyps = 
    check_id id hyps;
    { hyps with h_local = (id,ld)::hyps.h_local }


  let clear id hyps = 
    let r,(_,ld), l = 
      try List.find_split (fun (id',_) -> EcIdent.id_equal id id') hyps.h_local
      with _ -> assert false (* FIXME error message *) in
    let check_hyp id = function 
      | (id', LD_var (_, Some f)) when Sid.mem id f.f_fv ->
          error (CanNotClear(id,id'))
      | (id', LD_hyp f) when Sid.mem id f.f_fv -> 
          error (CanNotClear(id,id'))
      | _ -> () in
    begin match ld with
    | LD_var _ -> List.iter (check_hyp id) r 
    | LD_hyp _ -> ()
    end;
    { hyps with h_local = List.rev_append r l }

end