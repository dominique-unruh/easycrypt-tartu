(* --------------------------------------------------------------------
 * Copyright (c) - 2012-2015 - IMDEA Software Institute and INRIA
 * Distributed under the terms of the CeCILL-C license
 * -------------------------------------------------------------------- *)

(* -------------------------------------------------------------------- *)
open EcUtils
open EcSymbols
open EcEnv
open EcDecl
open EcPath
open EcLocation
open EcParsetree
open EcTypes
open EcModules

(* -------------------------------------------------------------------- *)
type opmatch = [
  | `Op   of EcPath.path * EcTypes.ty list
  | `Lc   of EcIdent.t
  | `Var  of EcTypes.prog_var
  | `Proj of EcTypes.prog_var * EcTypes.ty * (int * int)
]

type tymod_cnv_failure =
| E_TyModCnv_ParamCountMismatch
| E_TyModCnv_ParamTypeMismatch of EcIdent.t
| E_TyModCnv_MissingComp       of symbol
| E_TyModCnv_MismatchFunSig    of symbol

type modapp_error =
| MAE_WrongArgPosition
| MAE_WrongArgCount
| MAE_InvalidArgType
| MAE_AccesSubModFunctor

type modtyp_error =
| MTE_FunSigDoesNotRepeatArgNames
| MTE_InternalFunctor

type funapp_error =
| FAE_WrongArgCount

type mem_error =
| MAE_IsConcrete

type tyerror =
| UniVarNotAllowed
| FreeTypeVariables
| TypeVarNotAllowed
| OnlyMonoTypeAllowed
| UnboundTypeParameter   of symbol
| UnknownTypeName        of qsymbol
| UnknownTypeClass       of qsymbol
| UnknownRecFieldName    of qsymbol
| DuplicatedRecFieldName of symbol
| MissingRecField        of symbol
| MixingRecFields        of EcPath.path tuple2
| UnknownProj            of qsymbol
| AmbiguousProj          of qsymbol
| AmbiguousProji         of int * ty
| InvalidTypeAppl        of qsymbol * int * int
| DuplicatedTyVar
| DuplicatedLocal        of symbol
| DuplicatedField        of symbol
| NonLinearPattern
| LvNonLinear
| NonUnitFunWithoutReturn
| UnitFunWithReturn
| TypeMismatch           of (ty * ty) * (ty * ty)
| TypeClassMismatch
| TypeModMismatch        of tymod_cnv_failure
| NotAFunction
| UnknownVarOrOp         of qsymbol * ty list
| MultipleOpMatch        of qsymbol * ty list * (opmatch * EcUnify.unienv) list
| UnknownModName         of qsymbol
| UnknownTyModName       of qsymbol
| UnknownFunName         of qsymbol
| UnknownModVar          of qsymbol
| UnknownMemName         of int * symbol
| InvalidFunAppl         of funapp_error
| InvalidModAppl         of modapp_error
| InvalidModType         of modtyp_error
| InvalidMem             of symbol * mem_error
| FunNotInModParam       of qsymbol
| NoActiveMemory
| PatternNotAllowed
| MemNotAllowed
| UnknownScope           of qsymbol

exception TymodCnvFailure of tymod_cnv_failure
exception TyError of EcLocation.t * env * tyerror

val tyerror : EcLocation.t -> env -> tyerror -> 'a

(* -------------------------------------------------------------------- *)
val pp_tyerror     : env -> Format.formatter -> tyerror -> unit
val pp_cnv_failure :  Format.formatter -> env -> tymod_cnv_failure -> unit

(* -------------------------------------------------------------------- *)
val unify_or_fail : env -> EcUnify.unienv -> EcLocation.t -> expct:ty -> ty -> unit

(* -------------------------------------------------------------------- *)
type typolicy

val tp_tydecl : typolicy
val tp_relax  : typolicy

(* -------------------------------------------------------------------- *)
val transtyvars:
  env -> (EcLocation.t * ptyparams option) -> EcUnify.unienv

(* -------------------------------------------------------------------- *)
val transty : typolicy -> env -> EcUnify.unienv -> pty -> ty 

val transtys :  
    typolicy -> env -> EcUnify.unienv -> pty list -> ty list

val transtvi : env -> EcUnify.unienv -> ptyannot -> EcUnify.tvar_inst

val transbinding : env -> EcUnify.unienv -> ptybindings ->
  env * (EcIdent.t * EcTypes.ty) list

(* -------------------------------------------------------------------- *)
val transexp         : env -> [`InProc|`InOp] -> EcUnify.unienv -> pexpr -> expr * ty
val transexpcast     : env -> [`InProc|`InOp] -> EcUnify.unienv -> ty -> pexpr -> expr
val transexpcast_opt : env -> [`InProc|`InOp] -> EcUnify.unienv -> ty option -> pexpr -> expr

(* -------------------------------------------------------------------- *)
val transstmt    : env -> EcUnify.unienv -> pstmt -> stmt

(* -------------------------------------------------------------------- *)
type ptnmap = ty EcIdent.Mid.t ref

val transmem       : env -> EcSymbols.symbol located -> EcIdent.t
val trans_form_opt : env -> EcUnify.unienv -> pformula -> ty option -> EcFol.form
val trans_form     : env -> EcUnify.unienv -> pformula -> ty -> EcFol.form
val trans_prop     : env -> EcUnify.unienv -> pformula -> EcFol.form
val trans_pattern  : env -> (ptnmap * EcUnify.unienv) -> pformula -> EcFol.form

(* -------------------------------------------------------------------- *)
val transmodsig  : env -> symbol -> pmodule_sig  -> module_sig
val transmodtype : env -> pmodule_type -> module_type * module_sig
val transmod     : attop:bool -> env -> symbol -> pmodule_expr -> module_expr

val trans_topmsymbol : env -> pmsymbol located -> mpath
val trans_msymbol    : env -> pmsymbol located -> mpath * module_sig
val trans_gamepath   : env -> pgamepath -> xpath 

(* -------------------------------------------------------------------- *)
type restriction_error
  
exception RestrictionError of restriction_error

val pp_restriction_error : 
   EcEnv.env -> Format.formatter -> restriction_error -> unit

val check_sig_mt_cnv :
  env -> module_sig -> module_type -> unit 

val check_restrictions_fun :
  env -> xpath -> use -> mod_restr -> unit

val check_modtype_with_restrictions :
  env -> mpath -> module_sig -> module_type -> mod_restr -> unit

(* -------------------------------------------------------------------- *)
val get_ring  : (ty_params * ty) -> env -> EcDecl.ring  option
val get_field : (ty_params * ty) -> env -> EcDecl.field option
