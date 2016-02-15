(* --------------------------------------------------------------------
 * Copyright (c) - 2012--2016 - IMDEA Software Institute
 * Copyright (c) - 2012--2016 - Inria
 *
 * Distributed under the terms of the CeCILL-C-V1 license
 * -------------------------------------------------------------------- *)

(* -------------------------------------------------------------------- *)
let i_top  = "Top"
let i_self = "Self"
let p_top  = EcPath.psymbol i_top

(* -------------------------------------------------------------------- *)
let i_Pervasive = "Pervasive"
let p_Pervasive = EcPath.pqname p_top i_Pervasive
let _Pervasive  = fun x -> EcPath.pqname p_Pervasive x

(*-------------------------------------------------------------------- *)
module CI_Unit = struct
  let p_unit  = _Pervasive "unit"
  let p_tt    = _Pervasive "tt"
end

(*-------------------------------------------------------------------- *)
module CI_Bool = struct
  let i_Bool = "Bool"
  let p_Bool = EcPath.pqname p_top i_Bool
  let p_bool = _Pervasive "bool"

  let p_true  = _Pervasive "true"
  let p_false = _Pervasive "false"

  let p_not  = _Pervasive "[!]"
  let p_anda = _Pervasive "&&"
  let p_and  = _Pervasive "/\\"
  let p_ora  = _Pervasive "||"
  let p_or   = _Pervasive "\\/"
  let p_imp  = _Pervasive "=>"
  let p_iff  = _Pervasive "<=>"
  let p_eq   = _Pervasive "="
end

(* -------------------------------------------------------------------- *)
module CI_Int = struct
  let i_Int = "Int"
  let p_Int = EcPath.pqname p_top i_Int
  let p_int = _Pervasive "int"

  let _Int = fun x -> EcPath.pqname p_Int x

  let p_int_elim = _Int "intind"
  let p_int_opp = _Int "[-]"
  let p_int_add = _Int "+"
  let p_int_mul = _Int "*"
  let p_int_pow = _Int "^"
  let p_int_le  = _Int "<="
  let p_int_lt  = _Int "<"
end

(* -------------------------------------------------------------------- *)
module CI_Real = struct
  let i_Real = "Real"
  let p_Real = EcPath.pqname p_top i_Real
  let p_real = _Pervasive "real"

  let p_RealOrder =
    EcPath.extend p_top ["StdOrder"; "RealOrder"]

  let _Real = fun x -> EcPath.pqname p_Real x

  let p_real0       = _Real "zero"
  let p_real1       = _Real "one"
  let p_real_opp    = _Real "[-]"
  let p_real_add    = _Real "+"
  let p_real_mul    = _Real "*"
  let p_real_inv    = _Real "inv"
  let p_real_pow    = EcPath.extend p_Real ["^"]
  let p_real_le     = _Real "<="
  let p_real_lt     = _Real "<"
  let p_real_of_int = EcPath.extend p_Real ["from_int"]
  let p_real_abs    = EcPath.extend p_Real ["`|_|"]
end

(* -------------------------------------------------------------------- *)
module CI_Distr = struct
  let i_Distr = "Distr"
  let p_Distr  = EcPath.pqname p_top i_Distr
  let p_distr = _Pervasive "distr"

  let _Distr   = fun x -> EcPath.pqname p_Distr x

  let p_dbool = List.fold_left EcPath.pqname p_top ["DBool"; "dbool"]
  let p_dbitstring = List.fold_left EcPath.pqname p_Distr ["Dbitstring"; "dbitstring"]
  let p_dinter     = List.fold_left EcPath.pqname p_top ["DInterval"; "dinter"]

  let p_in_supp = _Distr "in_supp"
  let p_mu      = _Pervasive "mu"
  let p_mu_x    = _Distr "mu_x"
  let p_weight  = _Distr "weight"
end

(* -------------------------------------------------------------------- *)
module CI_Logic = struct
  let i_Logic  = "Logic"
  let p_Logic  = EcPath.pqname p_top i_Logic
  let _Logic   = fun x -> EcPath.pqname p_Logic x
  let mk_logic = _Logic

  let p_cut_lemma     = _Logic "cut_lemma"
  let p_unit_elim     = _Logic "unit_ind"
  let p_false_elim    = _Logic "falseE"
  let p_bool_elim     = _Logic "bool_ind"
  let p_and_elim      = _Logic "andE"
  let p_anda_elim     = _Logic "andaE"
  let p_and_proj_l    = _Logic "andEl"
  let p_and_proj_r    = _Logic "andEr"
  let p_or_elim       = _Logic "orE"
  let p_ora_elim      = _Logic "oraE"
  let p_iff_elim      = _Logic "iffE"
  let p_if_elim       = _Logic "ifE"

  let p_true_intro    = _Logic "trueI"
  let p_and_intro     = _Logic "andI"
  let p_anda_intro    = _Logic "andaI"
  let p_or_intro_l    = _Logic "orIl"
  let p_ora_intro_l   = _Logic "oraIl"
  let p_or_intro_r    = _Logic "orIr"
  let p_ora_intro_r   = _Logic "oraIr"
  let p_iff_intro     = _Logic "iffI"
  let p_if_intro      = _Logic "ifI"
  let p_eq_refl       = _Logic "eq_refl"
  let p_eq_trans      = _Logic "eq_trans"
  let p_eq_iff        = _Logic "eq_iff"
  let p_fcongr        = _Logic "congr1"
  let p_eq_sym        = _Logic "eq_sym"
  let p_eq_sym_imp    = _Logic "eq_sym_imp"
  let p_imp_trans     = _Logic "imp_trans"
  let p_negbTE        = _Logic "negbTE"
  let p_negeqF        = _Logic "negeqF"

  let p_rewrite_l     = _Logic "rewrite_l"
  let p_rewrite_r     = _Logic "rewrite_r"
  let p_rewrite_iff_l = _Logic "rewrite_iff_l"
  let p_rewrite_iff_r = _Logic "rewrite_iff_r"
  let p_rewrite_bool  = _Logic "rewrite_bool"

  let p_iff_lr        = _Logic "iffLR"
  let p_iff_rl        = _Logic "iffRL"

  let p_case_eq_bool  = _Logic "bool_case_eq"

  let p_ip_dup        = _Logic "_ip_dup"
end

(* -------------------------------------------------------------------- *)
let s_get  = "_.[_]"
let s_set  = "_.[_<-_]"
let s_nil  = "[]"
let s_cons = "::"
let s_abs  = "`|_|"

(* -------------------------------------------------------------------- *)
let is_mixfix_op =
  let ops = [s_get; s_set; s_nil; s_abs] in
  fun op -> List.mem op ops

(* -------------------------------------------------------------------- *)
let s_real_of_int = EcPath.toqsymbol CI_Real.p_real_of_int
let s_dbool       = EcPath.toqsymbol CI_Distr.p_dbool
let s_dbitstring  = EcPath.toqsymbol CI_Distr.p_dbitstring
let s_dinter      = EcPath.toqsymbol CI_Distr.p_dinter
