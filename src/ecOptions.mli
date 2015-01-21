(* --------------------------------------------------------------------
 * Copyright (c) - 2012-2015 - IMDEA Software Institute and INRIA
 * Distributed under the terms of the CeCILL-C license
 * -------------------------------------------------------------------- *)

(* -------------------------------------------------------------------- *)
type command = [
| `Compile of cmp_option
| `Cli     of cli_option
| `Config
]

and options = {
  o_options : glb_options;
  o_command : command;
}

and cmp_option = {
  cmpo_input   : string;
  cmpo_provers : prv_options;
}

and cli_option = {
  clio_emacs   : bool;
  clio_webui   : bool;
  clio_provers : prv_options;
}

and prv_options = {
  prvo_maxjobs   : int;
  prvo_timeout   : int;
  prvo_cpufactor : int;
  prvo_provers   : string list option;
  prvo_pragmas   : string list;
  prvo_checkall  : bool;
  prvo_profile   : bool;
}

and ldr_options = {
  ldro_idirs : string list;
  ldro_rdirs : string list;
  ldro_boot  : bool;
}

and glb_options = {
  o_why3     : string option;
  o_reloc    : bool;
  o_ovrevict : string list;
  o_loader   : ldr_options;
}

(* -------------------------------------------------------------------- *)
val parse : string array -> options
