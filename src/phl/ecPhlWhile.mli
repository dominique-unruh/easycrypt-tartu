(* --------------------------------------------------------------------
 * Copyright (c) - 2012-2015 - IMDEA Software Institute and INRIA
 * Distributed under the terms of the CeCILL-C license
 * -------------------------------------------------------------------- *)

(* -------------------------------------------------------------------- *)
open EcParsetree
open EcFol
open EcCoreGoal.FApi

(* -------------------------------------------------------------------- *)
val t_hoare_while      : form -> backward
val t_bdhoare_while    : form -> form -> backward
val t_equiv_while_disj : side -> form -> form -> backward
val t_equiv_while      : form -> backward

(* -------------------------------------------------------------------- *)
val process_while : oside -> while_info -> backward
