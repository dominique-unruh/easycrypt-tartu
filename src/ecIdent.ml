(* -------------------------------------------------------------------- *)
open EcSymbols
open EcUtils
open EcMaps

(* -------------------------------------------------------------------- *)
type ident = { 
  id_symb : symbol;
  id_tag  : int;
}

(* -------------------------------------------------------------------- *)
let name x = x.id_symb
let tag  x = x.id_tag

(* -------------------------------------------------------------------- *)
let id_equal : ident -> ident -> bool = (==)
let id_compare i1 i2 = i2.id_tag - i1.id_tag 
let id_hash id = id.id_tag 

(* -------------------------------------------------------------------- *)
module IdComparable = struct
  type t = ident
  let compare = id_compare
end

module Mid = Map.Make(IdComparable)
module Sid = Mid.Set

(* -------------------------------------------------------------------- *)
type t = ident

let create (x : symbol) = 
  { id_symb = x;
    id_tag  = EcUidgen.unique () }

let fresh (id : t) = create (name id)

let tostring (id : t) =
  Printf.sprintf "%s/%d" id.id_symb id.id_tag

(* -------------------------------------------------------------------- *)
module Map = struct
  type key  = t
  type 'a t = ((key * 'a) list) Msym.t

  let empty : 'a t =
    Msym.empty

  let add (id : key) (v : 'a) (m : 'a t) =
    Msym.change
      (fun p ->
        let xs =
          List.filter
            (fun (id', _) -> not (id_equal id id'))
            (odfl [] p)
        in
          Some ((id, v) :: xs))
      (name id) m

  let byident (id : key) (m : 'a t) =
    obind (Msym.find_opt (name id) m) (List.tryassoc_eq id_equal id)

  let byname (x : symbol) (m : 'a t) =
    match Msym.find_opt x m with
    | None | Some []  -> None
    | Some (idv :: _) -> Some idv 

  let allbyname (x : symbol) (m : 'a t) =
    odfl [] (Msym.find_opt x m)

   let dump ~name valuepp pp (m : 'a t) =
     let keyprinter k v =
       match v with
       | [] -> Printf.sprintf "%s (empty)" k
       | _  -> k

     and valuepp pp (_, xs) =
       match xs with
       | [] -> ()
       | _  ->
           EcDebug.onhlist pp
             (Printf.sprintf "%d binding(s)" (List.length xs))
             (fun pp (x, v) ->
                EcDebug.onhlist pp (tostring x) valuepp [v])
             xs
     in
       Msym.dump ~name keyprinter valuepp pp m
end

(* -------------------------------------------------------------------- *)
let pp_ident fmt id = Format.fprintf fmt "%s" (name id)