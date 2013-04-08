(* -------------------------------------------------------------------- *)
open EcSymbols
open EcLocation
open EcUtils

(* -------------------------------------------------------------------- *)
exception ParseError of EcLocation.t * string option

let pp_parse_error fmt msg =
  match msg with
  | Some msg -> Format.fprintf fmt "parse error: %s" msg
  | None     -> Format.fprintf fmt "parse error"

let () =
  let pp fmt exn =
    match exn with
    | ParseError (_loc, msg) -> pp_parse_error fmt msg
    | _ -> raise exn
  in
    EcPException.register pp

(* -------------------------------------------------------------------- *)
let qsymb_of_symb (x : symbol) : qsymbol = ([], x)

(* -------------------------------------------------------------------- *)
type psymbol  = symbol  located
type pqsymbol = qsymbol located
type pmsymbol = (psymbol * ((pmsymbol located) list) option) list
type posymbol = symbol option located

(* -------------------------------------------------------------------- *)
type pty_r =
  | PTunivar
  | PTtuple     of pty list
  | PTnamed     of pqsymbol
  | PTvar       of psymbol
  | PTapp       of pqsymbol * pty list
  | PTfun       of pty * pty

and pexpr_r =
  | PEint      of int                               (* int. literal       *)
  | PEident    of pqsymbol * ptyannot option        (* symbol             *)
  | PEapp      of pexpr * pexpr list                (* op. application    *)
  | PElet      of plpattern * pexpr * pexpr         (* let binding        *)
  | PEtuple    of pexpr list                        (* tuple constructor  *)
  | PEif       of pexpr * pexpr * pexpr             (* _ ? _ : _          *)

and ptyannot_r = 
  | TVIunamed of pty list
  | TVInamed  of (psymbol * pty) list

and plpattern_r =
  | LPSymbol of psymbol
  | LPTuple  of psymbol list

and plvalue_r =
  | PLvSymbol of pqsymbol
  | PLvTuple  of pqsymbol list
  | PLvMap    of pqsymbol * ptyannot option * pexpr

and pty       = pty_r       located
and pexpr     = pexpr_r     located
and plpattern = plpattern_r located
and plvalue   = plvalue_r   located
and ptyannot  = ptyannot_r  located

(* -------------------------------------------------------------------- *)
type pinstr =
  | PSasgn   of plvalue * pexpr
  | PSrnd    of plvalue * pexpr
  | PScall   of plvalue option * pqsymbol * pexpr list
  | PSif     of pexpr * pstmt * pstmt
  | PSwhile  of pexpr * pstmt
  | PSassert of pexpr

and pstmt = pinstr list

(* -------------------------------------------------------------------- *)
type pmodule_type = pqsymbol 

and pmodule_sig =
  | Pmty_struct of pmodule_sig_struct

and pmodule_sig_struct = {
  pmsig_params : (psymbol * pmodule_type) list;
  pmsig_body   : pmodule_sig_struct_body;
}

and pmodule_sig_struct_body = pmodule_sig_item list

and pmodule_sig_item = [
  | `VariableDecl of pvariable_decl
  | `FunctionDecl of pfunction_decl
]

and pvariable_decl = {
  pvd_name : psymbol;
  pvd_type : pty;
}

and pfunction_decl = {
  pfd_name     : psymbol;
  pfd_tyargs   : (psymbol * pty) list;
  pfd_tyresult : pty;
  pfd_uses     : (pqsymbol list) option;
}

(* -------------------------------------------------------------------- *)
and pmodule_expr_r =
  | Pm_ident  of pqsymbol * pqsymbol list
  | Pm_struct of pstructure

and pmodule_expr = pmodule_expr_r located

and pstructure = {
  ps_params    : (psymbol * pmodule_type) list;
  ps_body      : pstructure_item list;
  ps_signature : ((pqsymbol * psymbol list) located) list;
}

and pstructure_item =
  | Pst_mod   of (psymbol * pmodule_expr)
  | Pst_var   of (psymbol list * pty)
  | Pst_fun   of (pfunction_decl * pfunction_body)
  | Pst_alias of (psymbol * pqsymbol)

and pfunction_body = {
  pfb_locals : (psymbol list * pty * pexpr option) list;
  pfb_body   : pstmt;
  pfb_return : pexpr option;
}

(* -------------------------------------------------------------------- *)
type poperator = {
  po_name   : psymbol;
  po_tyvars : psymbol list option;
  po_dom    : pty list option;
  po_codom  : pty;  
  po_body   : (psymbol list * pexpr) option;
}

(* -------------------------------------------------------------------- *)
type ptydecl = {
  pty_name   : psymbol;
  pty_tyvars : psymbol list;
  pty_body   : pty option;
}

(* -------------------------------------------------------------------- *)
type pgamepath = (pmsymbol * psymbol) located
type pmemory   = psymbol

type pformula  = pformula_r located

and pformula_r = 
  | PFint    of int
  | PFtuple  of pformula list
  | PFident  of pqsymbol * ptyannot option
  | PFside   of pformula * psymbol
  | PFapp    of pformula * pformula list
  | PFif     of pformula * pformula * pformula
  | PFlet    of plpattern * pformula * pformula
  | PFforall of pgtybindings * pformula
  | PFexists of pgtybindings * pformula
  | PFlambda of pgtybindings * pformula

  (* for claims *)
  | PFhoareS of pformula * pfunction_body * pformula
  | PFhoareF of pformula * pgamepath * pformula
  | PFequivF of pformula * (pgamepath * pgamepath) * pformula
  | PFprob   of pgamepath * (pformula list) * pmemory * pformula

and pgtybinding  = psymbol * pgty
and pgtybindings = pgtybinding list

and pgty =
| PGTY_Type  of pty
| PGTY_ModTy of pqsymbol
| PGTY_Mem

(* -------------------------------------------------------------------- *)
type paxiom_kind = PAxiom | PLemma | PILemma

type paxiom = {
  pa_name    : psymbol;
  pa_formula : pformula;
  pa_kind : paxiom_kind;
}

(* -------------------------------------------------------------------- *)
type 'a abstr_def = 
  | AbstrDef of pty list option
  | ConcrDef of (psymbol *pty) list * 'a 

type ppredicate = {
  pp_name   : psymbol;
  pp_tyvars : psymbol list option;
  pp_dom    : pty list option;
  pp_body   : (psymbol list * pformula) option;
}

(* -------------------------------------------------------------------- *)
type pprover_infos = {
  pprov_max : int option;
  pprov_time : int option;
  pprov_names : string located list option
}

let empty_pprover = {
  pprov_max   = None;
  pprov_time  = None;
  pprov_names = None;
}

type fpattern_kind = 
  | FPNamed of pqsymbol * ptyannot option
  | FPCut   of pformula

type fpattern_arg = 
  | EA_form of pformula
  | EA_mem  of pmemory
  | EA_mp   of pmsymbol
  | EA_none 

type fpattern = { 
  fp_kind : fpattern_kind;
  fp_args : fpattern_arg located list 
}

type preduction = {
  pbeta  : bool;
  pdelta : pqsymbol list option;
  pzeta  : bool;   (* remove let *)
  piota  : bool;   (* remove case *)
  plogic : bool;   (* perform logical simplification *)
}


(* -------------------------------------------------------------------- *)
type 'a doption = 
  | Single of 'a
  | Double of 'a * 'a

type tac_side = bool option

type  swap_kind = 
  | SKbase of int * int * int
  | SKmove of int
  | SKmovei of int * int
  | SKmoveinter of int * int * int 

type ptactic = ptactic_r located

and ptactic_r = 
  | Pidtac
  | Passumption of (pqsymbol option * ptyannot option)
  | Ptrivial    of pprover_infos
  | Pintro      of posymbol list  
  | Psplit                        
  | Pexists     of fpattern_arg located list 
  | Pleft                         
  | Pright                        
  | Pelim       of fpattern 
  | Papply      of fpattern
  | Pcut        of (psymbol * pformula)
  | Pgeneralize of pformula list
  | Pclear      of psymbol list
  | Prewrite    of (bool * fpattern)
  | Psubst      of psymbol list
  | Psimplify   of preduction 
  | Pchange     of pformula
  | PelimT      of (pformula * pqsymbol)
  | Pcase       of pformula 
  | Psubgoal    of ptactics
  | Pseq        of ptactics
  | PPhl        of phl_tactics
  | Padmit

and phl_tactics = 
  | Pfun_def  
  | Pskip
  | Papp        of (int doption * pformula)
  | Pwp         of int doption option 
  | Pwhile      of pformula
  | Pcall       of pformula * pformula
  | Prcond      of (bool option * bool * int)
  | Pcond       of tac_side
  | Pswap       of ((tac_side * swap_kind) located list)
  | Pequivdeno  of (pformula * pformula)

and ptactics = ptactic list        

(* -------------------------------------------------------------------- *)
type ident_spec = psymbol list

type inv = (pformula, (pformula * pformula) * pformula option) EcAstlogic.g_inv

type equiv_concl =
  | Aequiv_spec of (pformula * pformula) * (pexpr * pexpr) option
  | Aequiv_inv  of inv

type auto_info = inv option * ident_spec

type auto_eager = (auto_info, pstmt) EcAstlogic.helper
      
type equiv = {
  eq_name  : psymbol          ;
  eq_left  : pqsymbol         ;
  eq_right : pqsymbol         ;
  eq_concl : equiv_concl      ;
  eq_auto  : auto_eager option;
}

(* -------------------------------------------------------------------- *)
type cnst_decl = (psymbol list * pty) * pexpr option

(* -------------------------------------------------------------------- *)
type hint =
  | Husing of psymbol
  | Hadmit
  | Hcompute
  | Hnone
  | Hsame
  | Hsplit
  | Hauto
  | Hfailure of int * pexpr * pexpr * (psymbol * pexpr) list

type claim = psymbol * (pexpr * hint)

(* -------------------------------------------------------------------- *)
type pprint = 
  | Pr_ty of pqsymbol
  | Pr_op of pqsymbol
  | Pr_th of pqsymbol
  | Pr_pr of pqsymbol
  | Pr_ax of pqsymbol

(* -------------------------------------------------------------------- *)
type renaming_kind = 
  | RNty
  | RNop
  | RNpr

type w3_renaming = 
    string list * renaming_kind * string 
    
(* -------------------------------------------------------------------- *)
type theory_cloning = {
  pthc_base : pqsymbol;
  pthc_name : psymbol option;
  pthc_ext  : (psymbol * theory_override) list;
}

and theory_override =
| PTHO_Type of (psymbol list * pty)
| PTHO_Op   of (psymbol list * pexpr)

(* -------------------------------------------------------------------- *)
type global =
  | Gmodule      of (psymbol * pmodule_expr)
  | Ginterface   of (psymbol * pmodule_sig)
  | Goperator    of poperator
  | Gpredicate   of ppredicate
  | Gaxiom       of paxiom
  | Gclaim       of claim
  | Gtype        of ptydecl
  | Gprint       of pprint
  | GthOpen      of psymbol
  | GthClose     of psymbol
  | GthRequire   of (psymbol * bool option) (* true = export, false = import *)
  | GthImport    of pqsymbol
  | GthExport    of pqsymbol
  | GthClone     of theory_cloning
  | GthW3        of (string list * string * w3_renaming list)
  | Gtactics     of ptactics
  | Gprover_info of pprover_infos
  | Gcheckproof  of bool
  | Gsave        of EcLocation.t

type prog =
  | P_Prog of (global located) list * bool
  | P_Undo of int
