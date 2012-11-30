(* -------------------------------------------------------------------- *)
open EcSymbols
open EcParsetree

(* -------------------------------------------------------------------- *)
module Context : sig
  type symbol = string

  type 'a context

  exception DuplicatedNameInContext of string
  exception UnboundName of string

  val empty   : unit -> 'a context
  val bind    : symbol -> 'a -> 'a context -> 'a context
  val rebind  : symbol -> 'a -> 'a context -> 'a context
  val exists  : symbol -> 'a context -> bool
  val lookup  : symbol -> 'a context -> 'a option
  val iter    : (symbol -> 'a -> unit) -> 'a context -> unit
  val fold    : ('b -> symbol -> 'a -> 'b) -> 'b -> 'a context -> 'b
  val tolist  : 'a context -> (symbol * 'a) list
end

(* -------------------------------------------------------------------- *)
type scope

val initial : symbol -> scope
val name    : scope -> symbol
val env     : scope -> EcEnv.env

module Op : sig
  (* Possible exceptions when checking/adding an operator *)
  type operror =
  | OpE_DuplicatedTypeVariable

  exception OpError of operror

  val operror : operror -> 'a

  (* [add scope op] type-checks the given *parsed* operator [op] in
   * scope [scope], and add it to it. Raises [DuplicatedNameInContext]
   * if a type with given name already exists. *)
  val add : scope -> poperator -> scope
end

module Ty : sig
  (* [add scope t] adds an abstract type with name [t] to scope
   * [scope]. Raises [DuplicatedNameInContext] if a type with
   * given name already exists. *)
  val add : scope -> (symbol list * symbol) -> scope

  (* [define scope t body] adds a defined type with name [t] and body
   * [body] to scope [scope]. Can raise any exception triggered by the
   * type-checker or [DuplicatedNameInContext] in case a type with name
   * [t] already exists *)
  val define : scope -> (symbol list * symbol) -> pty -> scope
end

module Mod : sig
  (* [add scope x m] chekc the module [n] and add it to the scope
   * [scope] with name [x]. Can raise any exception triggered by the
   * type-checker or [DuplicatedNameInContext] in case a module with
   * name [x] already exists *)
  val add : scope -> symbol -> pmodule_expr -> scope
end

module ModType : sig
  (* [add scope x i] checks the module type [i] and add it to the
   * scope [scope] with name [x]. Can raise any exception triggered by
   * the type-checker or [DuplicatedNameInContext] in case a module
   * type with name [x] already exists *)
  val add : scope -> symbol -> pmodule_type -> scope
end