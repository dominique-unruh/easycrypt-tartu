(* --------------------------------------------------------------------
 * Copyright (c) - 2012-2015 - IMDEA Software Institute and INRIA
 * Distributed under the terms of the CeCILL-C license
 * -------------------------------------------------------------------- *)

(* -------------------------------------------------------------------- *)
type exn_printer = Format.formatter -> exn -> unit

val register    : exn_printer -> unit
val exn_printer : exn_printer 
val tostring    : exn -> string
