(* --------------------------------------------------------------------
 * Copyright (c) - 2012-2014 - IMDEA Software Institute and INRIA
 * Distributed under the terms of the CeCILL-C license
 * -------------------------------------------------------------------- *)

(* -------------------------------------------------------------------- *)
exception Unexpected

val unexpected : unit -> 'a
val checkpoint : unit -> unit

(* -------------------------------------------------------------------- *)
type 'data cb = Cb : 'a * ('data -> 'a -> unit) -> 'data cb

(* -------------------------------------------------------------------- *)
val tryexn : (exn -> bool) -> (unit -> 'a) -> 'a option
val try_nf : (unit -> 'a) -> 'a option

val try_finally : (unit -> 'a) -> (unit -> unit) -> 'a

(* -------------------------------------------------------------------- *)
val identity : 'a -> 'a

val (^~) : ('a -> 'b -> 'c) -> ('b -> 'a -> 'c)
val (-|) : ('a -> 'b) -> ('c -> 'a) -> 'c -> 'b
val (|-) : ('a -> 'b) -> ('c -> 'a) -> 'c -> 'b

val (|>) : 'a -> ('a -> 'b) -> 'b
val (<|) : ('a -> 'b) -> 'a -> 'b

val curry   : ('a1 -> 'a2 -> 'b) -> 'a1 * 'a2 -> 'b
val uncurry : ('a1 * 'a2 -> 'b) -> 'a1 -> 'a2 -> 'b

val curry3   : ('a1 -> 'a2 -> 'a3 -> 'b) -> 'a1 * 'a2 * 'a3 -> 'b
val uncurry3 : ('a1 * 'a2 * 'a3 -> 'b) -> 'a1 -> 'a2 -> 'a3 -> 'b

(* -------------------------------------------------------------------- *)
val clamp : min:int -> max:int -> int -> int

(* -------------------------------------------------------------------- *)
val copy : 'a -> 'a

(* -------------------------------------------------------------------- *)
val reffold  : ('a -> 'b * 'a) -> 'a ref -> 'b
val postincr : int ref -> int

(* -------------------------------------------------------------------- *)
type 'a tuple0 = unit
type 'a tuple1 = 'a
type 'a tuple2 = 'a * 'a
type 'a tuple3 = 'a * 'a * 'a
type 'a tuple4 = 'a * 'a * 'a * 'a
type 'a tuple5 = 'a * 'a * 'a * 'a * 'a
type 'a tuple6 = 'a * 'a * 'a * 'a * 'a * 'a
type 'a tuple7 = 'a * 'a * 'a * 'a * 'a * 'a * 'a
type 'a tuple8 = 'a * 'a * 'a * 'a * 'a * 'a * 'a * 'a
type 'a tuple9 = 'a * 'a * 'a * 'a * 'a * 'a * 'a * 'a * 'a
type 'a pair   = 'a tuple2

(* -------------------------------------------------------------------- *)
val in_seq1: ' a -> 'a list

(* -------------------------------------------------------------------- *)
val as_seq0 : 'a list -> 'a tuple0
val as_seq1 : 'a list -> 'a tuple1
val as_seq2 : 'a list -> 'a tuple2
val as_seq3 : 'a list -> 'a tuple3
val as_seq4 : 'a list -> 'a tuple4
val as_seq5 : 'a list -> 'a tuple5
val as_seq6 : 'a list -> 'a tuple6
val as_seq7 : 'a list -> 'a tuple7

(* -------------------------------------------------------------------- *)
val int_of_bool : bool -> int

(* -------------------------------------------------------------------- *)
val proj3_1 : 'a * 'b * 'c -> 'a
val proj3_2 : 'a * 'b * 'c -> 'b
val proj3_3 : 'a * 'b * 'c -> 'c

val proj4_1 : 'a * 'b * 'c * 'd -> 'a
val proj4_2 : 'a * 'b * 'c * 'd -> 'b
val proj4_3 : 'a * 'b * 'c * 'd -> 'c
val proj4_4 : 'a * 'b * 'c * 'd -> 'd

val fst_map : ('a -> 'c) -> 'a * 'b -> 'c * 'b
val snd_map : ('b -> 'c) -> 'a * 'b -> 'a * 'c

val swap: 'a * 'b -> 'b * 'a

(* -------------------------------------------------------------------- *)
type 'a eq  = 'a -> 'a -> bool
type 'a cmp = 'a -> 'a -> int

val pair_equal : 'a eq -> 'b eq -> ('a * 'b) eq
val opt_equal  : 'a eq -> 'a option eq

(* -------------------------------------------------------------------- *)
val compare_tag : 'a cmp
val compare2: int lazy_t -> int lazy_t -> int
val compare3: int lazy_t -> int lazy_t -> int lazy_t -> int

(* -------------------------------------------------------------------- *)
val none : 'a option
val some : 'a -> 'a option

val is_none : 'a option -> bool
val is_some : 'a option -> bool

val funnone : 'a -> 'b option

(* -------------------------------------------------------------------- *)
val oiter      : ('a -> unit) -> 'a option -> unit
val obind      : ('a -> 'b option) -> 'a option -> 'b option
val ofold      : ('a -> 'b -> 'b) -> 'b -> 'a option -> 'b
val omap       : ('a -> 'b) -> 'a option -> 'b option
val odfl       : 'a -> 'a option -> 'a
val ofdfl      : (unit -> 'a) -> 'a option -> 'a
val oget       : 'a option -> 'a
val oall2      : ('a -> 'b -> bool) -> 'a option -> 'b option -> bool
val otolist    : 'a option -> 'a list
val ocompare   : 'a cmp -> 'a option cmp
val omap_dfl   : ('a -> 'b) -> 'b -> 'a option -> 'b

module OSmart : sig
  val omap : ('a -> 'a) -> 'a option -> 'a option
  val omap_fold : ('a -> 'b -> 'a * 'b) -> 'a -> 'b option -> 'a * 'b option
end

(* -------------------------------------------------------------------- *)
type ('a, 'b) tagged = Tagged of ('a * 'b option)

val tg_val : ('a, 'b) tagged -> 'a
val tg_tag : ('a, 'b) tagged -> 'b option
val tg_map : ('a -> 'b) -> ('a, 'c) tagged -> ('b, 'c) tagged
val notag  : 'a -> ('a, 'b) tagged

(* -------------------------------------------------------------------- *)
val iterop: ('a -> 'a) -> int -> 'a -> 'a

(* -------------------------------------------------------------------- *)
module Counter : sig
  type t

  val create : unit -> t
  val next   : t -> int
end

(* -------------------------------------------------------------------- *)
module Disposable : sig
  type 'a t

  exception Disposed

  val create  : ?cb:('a -> unit) -> 'a -> 'a t
  val get     : 'a t -> 'a
  val dispose : 'a t -> unit
end

(* -------------------------------------------------------------------- *)
module ISet : sig
  include module type of BatISet
end

(* -------------------------------------------------------------------- *)
module List : sig
  include module type of List

  val compare : 'a cmp -> 'a list cmp

  val ocons : 'a option -> 'a list -> 'a list

  val isempty : 'a list -> bool

  val ohead : 'a list -> 'a option

  val otail : 'a list -> 'a list option

  val last : 'a list -> 'a

  val olast : 'a list -> 'a option

  val iteri : (int -> 'a -> 'b) -> 'a list -> unit

  val iter2i : (int -> 'a -> 'b -> 'c) -> 'a list -> 'b list -> unit

  val fusion : ('a -> 'a -> 'a) -> 'a list -> 'a list -> 'a list

  val iter2o : ('a option -> 'b option -> 'c) -> 'a list -> 'b list -> unit

  val findopt : ('a -> bool) -> 'a list -> 'a option

  val findex : ('a -> bool) -> 'a list -> int option
  
  val findex_last : ('a -> bool) -> 'a list -> int option

  val index :  'a -> 'a list -> int option

  val uniqf : ('a -> 'a -> bool) -> 'a list -> bool

  val uniq : 'a list -> bool

  val take : int -> 'a list -> 'a list

  val split_n : int -> 'a list -> 'a list * 'a * 'a list

  val fold_lefti : (int -> 'a -> 'b -> 'a) -> 'a -> 'b list -> 'a

  val filter2 : ('a -> 'b -> bool) -> 'a list -> 'b list -> 'a list * 'b list

  val create : int -> 'a -> 'a list

  val init : int -> (int -> 'a) -> 'a list

  val find_split : ('a -> bool) -> 'a list -> 'a list * 'a * 'a list

  val mapi : (int -> 'a -> 'b) -> 'a list -> 'b list

  val map_fold : ('a -> 'b -> 'a * 'c) -> 'a -> 'b list -> 'a * 'c list

  val map_fold2 : ('a -> 'b -> 'c -> 'a * 'd) -> 'a -> 'b list -> 'c list -> 'a * 'd list

  val map_combine : ('a -> 'c) -> ('b -> 'd) -> 'a list -> 'b list -> ('c * 'd) list

  val take_n : int -> 'a list -> 'a list * 'a list

  val all2 : ('a -> 'b -> bool) -> 'a list -> 'b list -> bool

  val hd2 : 'a list -> 'a * 'a

  val pick : ('a -> 'b option) -> 'a list -> 'b option

  val fpick : (unit -> 'a option) list -> 'a option

  val assoc_eq : ('a -> 'a -> bool) -> 'a -> ('a * 'b) list -> 'b

  val tryassoc_eq : ('a -> 'a -> bool) -> 'a -> ('a * 'b) list -> 'b option

  val tryassoc : 'a -> ('a * 'b) list -> 'b option

  val find_map : ('a -> 'b option) -> 'a list -> 'b

  val pmap : ('a -> 'b option) -> 'a list -> 'b list

  val prmap : ('a -> 'b option) -> 'a list -> 'b list

  val sum : int list -> int

  val min : 'a -> 'a list -> 'a

  val max : 'a -> 'a list -> 'a

  val rotate : [`Left|`Right] -> int -> 'a list -> int * 'a list

  module Smart : sig
    val map : ('a -> 'a) -> 'a list -> 'a list

    val map_fold : ('a -> 'b -> 'a * 'b) -> 'a -> 'b list -> 'a * 'b list
  end
end

(* -------------------------------------------------------------------- *)
module Stream : sig
  include module type of Stream with type 'a t = 'a Stream.t

  val next_opt : 'a Stream.t -> 'a option
end

(* -------------------------------------------------------------------- *)
module String : sig
  include module type of String

  val init : int -> (int -> char) -> string

  val mapi : (int -> char -> char) -> string -> string

  val startswith : string -> string -> bool

  val endswith : string -> string -> bool

  val slice : ?first:int -> ?last:int -> string -> string

  val split : char -> string -> string list

  val splitlines : string -> string list

  val strip : string -> string
end

(* -------------------------------------------------------------------- *)
module Parray : sig
  type 'a t

  val empty : 'a t

  val get : 'a t -> int -> 'a

  val length : 'a t -> int

  val of_list : 'a list -> 'a t

  val to_list : 'a t -> 'a list

  val of_array : 'a array -> 'a t

  val init : int -> (int -> 'a) -> 'a t

  val map : ('a -> 'b) -> 'a t -> 'b t

  val fmap : ('a -> 'b) -> 'a list -> 'b t

  val fold_left : ('a -> 'b -> 'a) -> 'a -> 'b t -> 'a

  val fold_right : ('b -> 'a -> 'a) -> 'b t -> 'a -> 'a

  val fold_left2 : ('a -> 'b -> 'c -> 'a) -> 'a -> 'b t -> 'c t -> 'a

  val iter : ('a -> unit) -> 'a t -> unit

  val iter2 : ('a -> 'b -> unit) -> 'a t -> 'b t -> unit

  val split : ('a * 'b) t -> ('a t * 'b t)

  val exists : ('a -> bool) -> 'a t -> bool

  val for_all : ('a -> bool) -> 'a t -> bool
end

(* -------------------------------------------------------------------- *)
module Os : sig
  val listdir : string -> string list
end
