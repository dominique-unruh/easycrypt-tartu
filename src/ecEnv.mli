(* -------------------------------------------------------------------- *)
open EcUtils
open EcPath
open EcSymbols
open EcTypes
open EcMemory
open EcDecl
open EcFol
open EcModules
open EcTheory

(* -------------------------------------------------------------------- *)

(* A [path] is missing the module application information. As such, when
 * resolving a path, it is not returned a object but a suspension to
 * that object. This suspension can resolved by providing the missing
 * modules parameters. Such a resolved suspension only contains path of the
 * for [EPath _]. See the environment API for more information.
 *)
type 'a suspension = {
  sp_target : 'a;
  sp_params : (EcIdent.t * module_type) list list;
}

val is_suspended : 'a suspension -> bool

(* -------------------------------------------------------------------- *)

(* Describe the kind of objects that can be bound in an environment.
 * We alse define 2 classes of objects:
 * - containers    : theory   / module
 * - module values : variable / function
 *)

type okind = [
  | `Variable
  | `Function
  | `Theory
  | `Module
  | `ModType
  | `TypeDecls
  | `OpDecls
  | `Lemma
]

module Kinds : EcUtils.IFlags with type flag = okind

val ok_container : Kinds.t
val ok_modvalue  : Kinds.t

(* -------------------------------------------------------------------- *)
type varbind = {
  vb_type  : EcTypes.ty;
  vb_kind  : EcTypes.pvar_kind;
}

type preenv = private {
  (* The current scope path, i.e. the path to the current active
   * theory/module. All paths of inserted objects are computed
   * from that value. *)
  env_scope  : EcPath.mpath;

  (* The sets of object living reachable from the current active
   * scope. This includes objects imported via the [require import]
   * commands and defined in the currently active scope. *)
  env_current : activemc;

  (* The sets of `compoments' (see the documentation of the [premc])
   * for each container (theory/module) living in the environment.
   * This is the unique point where the fully resolved components of
   * a container is stored. *)
  env_comps  : premc EcPath.Mp.t;

  (* The set of local variables *)
  env_locals : (EcIdent.t * EcTypes.ty) MMsym.t;

  (* The set of memories (i.e. sided program variables) *)
  env_memories : EcMemory.memenv MMsym.t;

  (* The active memory *)
  env_actmem : EcMemory.memory option;
 
  (* Why3 environment && meta-data *)
  env_w3     : EcWhy3.env;
  env_rb     : EcWhy3.rebinding;        (* in reverse order *)
  env_item   : ctheory_item list        (* in reverse order *)
}

(* A [premc] value describes the components (i.e. resolved members)
 * of a container, i.e. its variables, functions, sub-theories, ...
 * We maintain an invariant that, for a given object kind, a name
 * cannot be bound twice.
 *
 * Sub-containers also contain an entry in the [mc_components] set.
 * This set only records the presence of a field with a container.
 * The contents (components) of the container must be looked up using
 * the [env_comps] field of the associated environment.
 *
 * The field [mc_parameters] records the (module) parameter of the
 * associated container (module).
 *)
and premc = private {
  mc_parameters : (EcIdent.t * module_type)        list;
  mc_variables  : (mpath * varbind)                Msym.t;
  mc_functions  : (mpath * EcModules.function_)    Msym.t;
  mc_modules    : (mpath * EcModules.module_expr)  Msym.t;
  mc_modtypes   : (mpath * EcModules.module_sig)   Msym.t;
  mc_typedecls  : (mpath * EcDecl.tydecl)          Msym.t;
  mc_operators  : (mpath * EcDecl.operator)        Msym.t;
  mc_axioms     : (mpath * EcDecl.axiom)           Msym.t;
  mc_theories   : (mpath * ctheory)                Msym.t;
  mc_components : path                             Msym.t;
}

(* As [premc], but allows names to be bound several times, and maps
 * objects to [epath] instead of [path]. This structure serves as the
 * components description of the current active scope. It includes all
 * the objects imported via the [import] command. *)

and activemc = {
  amc_variables  : (mpath * varbind)                MMsym.t;
  amc_functions  : (mpath * EcModules.function_)    MMsym.t;
  amc_modules    : (mpath * EcModules.module_expr)  MMsym.t;
  amc_modtypes   : (mpath * EcModules.module_sig)   MMsym.t;
  amc_typedecls  : (mpath * EcDecl.tydecl)          MMsym.t;
  amc_operators  : (mpath * EcDecl.operator)        MMsym.t;
  amc_axioms     : (mpath * EcDecl.axiom)           MMsym.t;
  amc_theories   : (mpath * ctheory)                MMsym.t;
  amc_components : path                             MMsym.t;
}

(* -------------------------------------------------------------------- *)
type env = preenv

val preenv  : env -> preenv
val root    : env -> EcPath.path
val mroot   : env -> EcPath.mpath
val initial : env

(* -------------------------------------------------------------------- *)
val dump : ?name:string -> EcDebug.ppdebug -> env -> unit

(* -------------------------------------------------------------------- *)
exception LookupFailure of [`Path of path | `QSymbol of qsymbol]

(* -------------------------------------------------------------------- *)
type meerror =
| UnknownMemory of [`Symbol of symbol | `Memory of memory]

exception MEError of meerror

module Memory : sig

  val set_active  : memory -> env -> env
  val get_active  : env -> memory option

  val byid        : memory -> env -> EcMemory.memenv option
  val lookup      : symbol -> env -> EcMemory.memenv option
  val current     : env -> EcMemory.memenv option
  val push        : EcMemory.memenv -> env -> env
  val push_all    : EcMemory.memenv list -> env -> env
  val push_active : EcMemory.memenv -> env -> env

end

(* -------------------------------------------------------------------- *)
module Fun : sig
  type t = function_

  val by_path     : EcPath.path -> env -> t suspension
  val by_path_opt : EcPath.path -> env -> (t suspension) option
  val by_mpath    : EcPath.mpath -> env -> t
  val by_mpath_opt: EcPath.mpath -> env -> t option
  val lookup      : qsymbol -> env -> mpath * t
  val lookup_opt  : qsymbol -> env -> (mpath * t) option
  val lookup_path : qsymbol -> env -> mpath

  val sp_lookup     : qsymbol -> env -> (path * t suspension)
  val sp_lookup_opt : qsymbol -> env -> (path * t suspension) option

  val prF : EcPath.mpath -> env -> env

  val hoareF : EcPath.mpath -> env -> env * env

  val hoareS : EcPath.mpath -> env -> EcMemory.memenv * EcModules.function_def * env

  val hoareS_anonym : EcModules.variable list -> env -> EcMemory.memenv * env

  val equivF : EcPath.mpath -> EcPath.mpath -> env -> env * env

  val equivS : 
    EcPath.mpath -> EcPath.mpath -> env ->
    EcMemory.memenv * EcModules.function_def * EcMemory.memenv *
      EcModules.function_def * env

  val equivS_anonym : 
    EcModules.variable list ->
    EcModules.variable list ->
    env -> EcMemory.memenv * EcMemory.memenv * env

  val enter : symbol -> env -> env
  val add : EcPath.path -> env -> env
end

(* -------------------------------------------------------------------- *)
module Var : sig
  type t = varbind

  val by_path     : EcPath.path -> env -> t suspension
  val by_path_opt : EcPath.path -> env -> (t suspension) option
  val by_mpath    : EcPath.mpath -> env -> t
  val by_mpath_opt: EcPath.mpath -> env -> t option

  (* Lookup restricted to given kind of variables *)
  val lookup_locals    : symbol -> env -> (EcIdent.t * EcTypes.ty) list
  val lookup_local     : symbol -> env -> (EcIdent.t * EcTypes.ty)
  val lookup_local_opt : symbol -> env -> (EcIdent.t * EcTypes.ty) option

  val lookup_progvar     : ?side:memory -> qsymbol -> env -> (prog_var * EcTypes.ty)
  val lookup_progvar_opt : ?side:memory -> qsymbol -> env -> (prog_var * EcTypes.ty) option

  (* Locals binding *)
  val bind_local  : EcIdent.t -> EcTypes.ty -> env -> env
  val bind_locals : (EcIdent.t * EcTypes.ty) list -> env -> env

  (* Program variables binding *)
  val bind    : symbol -> pvar_kind -> EcTypes.ty -> env -> env
  val bindall : (symbol * EcTypes.ty) list -> pvar_kind -> env -> env

  val add : EcPath.path -> env -> env
end

(* -------------------------------------------------------------------- *)
module Ax : sig
  type t = axiom

  val by_path     : EcPath.path -> env -> t
  val by_path_opt : EcPath.path -> env -> t option
  val lookup      : qsymbol -> env -> EcPath.path * t
  val lookup_opt  : qsymbol -> env -> (EcPath.path * t) option
  val lookup_path : qsymbol -> env -> EcPath.path

  val add  : EcPath.path -> env -> env
  val bind : symbol -> axiom -> env -> env

  val instanciate : EcPath.path -> EcTypes.ty list -> env -> EcFol.form 
end

(* -------------------------------------------------------------------- *)
module Mod : sig
  type t = module_expr

  val by_path     : EcPath.path -> env -> t suspension
  val by_path_opt : EcPath.path -> env -> (t suspension) option
  val by_mpath    : EcPath.mpath -> env -> t
  val by_mpath_opt: EcPath.mpath -> env -> t option
  val lookup      : qsymbol -> env -> mpath * t
  val lookup_opt  : qsymbol -> env -> (mpath * t) option
  val lookup_path : qsymbol -> env -> mpath

  val sp_lookup     : qsymbol -> env -> mpath * t suspension
  val sp_lookup_opt : qsymbol -> env -> (mpath * t suspension) option

  val add  : EcPath.path -> env -> env
  val bind : symbol -> module_expr -> env -> env

  val enter : symbol -> (EcIdent.t * module_type) list -> env -> env
  val bind_local : EcIdent.t -> module_type -> env -> env

end

(* -------------------------------------------------------------------- *)
module ModTy : sig
  type t = module_sig

  val by_path     : EcPath.path -> env -> t
  val by_path_opt : EcPath.path -> env -> t option
  val lookup      : qsymbol -> env -> EcPath.path * t
  val lookup_opt  : qsymbol -> env -> (EcPath.path * t) option
  val lookup_path : qsymbol -> env -> EcPath.path

  val add  : EcPath.path -> env -> env
  val bind : symbol -> t -> env -> env

  val mod_type_equiv : env -> module_type -> module_type -> bool
  val has_mod_type : env -> module_type list -> module_type -> bool
end

(* -------------------------------------------------------------------- *)
module NormMp : sig 
  val norm_mpath : env -> EcPath.mpath -> EcPath.mpath 
  val norm_pvar  : env -> EcTypes.prog_var -> EcTypes.prog_var
end

(* -------------------------------------------------------------------- *)
type ctheory_w3

val ctheory_of_ctheory_w3 : ctheory_w3 -> ctheory

module Theory : sig
  type t = ctheory

  val by_path     : EcPath.path -> env -> t
  val by_path_opt : EcPath.path -> env -> t option
  val lookup      : qsymbol -> env -> EcPath.path * t
  val lookup_opt  : qsymbol -> env -> (EcPath.path * t) option
  val lookup_path : qsymbol -> env -> EcPath.path

  val add : EcPath.path -> env -> env

  val bind  : symbol -> ctheory_w3 -> env -> env
  val bindx : symbol -> ctheory -> env -> env

  val require : symbol -> ctheory_w3 -> env -> env
  val import  : EcPath.path -> env -> env
  val export  : EcPath.path -> env -> env

  val enter : symbol -> env -> env
  val close : env -> ctheory_w3
end

(* -------------------------------------------------------------------- *)
module Op : sig
  type t = operator

  val by_path     : EcPath.path -> env -> t
  val by_path_opt : EcPath.path -> env -> t option
  val lookup      : qsymbol -> env -> EcPath.path * t
  val lookup_opt  : qsymbol -> env -> (EcPath.path * t) option
  val lookup_path : qsymbol -> env -> EcPath.path

  val add  : EcPath.path -> env -> env
  val bind : symbol -> operator -> env -> env

  val all : (operator -> bool) -> qsymbol -> env -> (EcPath.path * t) list
  val reducible : env -> EcPath.path -> bool
  val reduce    : env -> EcPath.path -> ty list -> form
end

(* -------------------------------------------------------------------- *)
module Ty : sig
  type t = EcDecl.tydecl

  val by_path     : EcPath.path -> env -> t
  val by_path_opt : EcPath.path -> env -> t option
  val lookup      : qsymbol -> env -> EcPath.path * t
  val lookup_opt  : qsymbol -> env -> (EcPath.path * t) option
  val lookup_path : qsymbol -> env -> EcPath.path

  val add  : EcPath.path -> env -> env
  val bind : symbol -> t -> env -> env

  val defined : EcPath.path -> env -> bool
  val unfold  : EcPath.path -> EcTypes.ty list -> env -> EcTypes.ty
end

(* -------------------------------------------------------------------- *)
type ebinding = [
  | `Variable  of EcTypes.pvar_kind * EcTypes.ty
  | `Function  of function_
  | `Module    of module_expr
  | `ModType   of module_sig
]

val bind1   : symbol * ebinding -> env -> env
val bindall : (symbol * ebinding) list -> env -> env

val import_w3_dir :
     env -> string list -> string
  -> EcWhy3.renaming_decl
  -> env * ctheory_item list

(* -------------------------------------------------------------------- *)
val check_goal : env -> EcWhy3.prover_infos -> EcBaseLogic.l_decl -> bool
