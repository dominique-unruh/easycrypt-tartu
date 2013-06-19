(* -------------------------------------------------------------------- *)
open EcUtils
open EcMaps
open EcLocation
open EcSymbols
open EcParsetree
open EcTypes
open EcModules
open EcFol

open EcBaseLogic
open EcLogic
open EcHiLogic
open EcHiPhl

(* -------------------------------------------------------------------- *)
let process_case loc pf g =
  let concl = get_concl g in
  match concl.f_node with
  | FhoareS _ | FbdHoareS _ ->
    let f = process_phl_formula g pf in
    EcPhl.t_he_case f g
  | FequivS _ ->
    let f = process_prhl_formula g pf in
    EcPhl.t_equiv_case f g
  | _ ->
    let f = process_formula g pf in
    t_seq (set_loc loc (t_case f))
      (t_simplify EcReduction.betaiota_red) g

(* -------------------------------------------------------------------- *)
let process_debug (juc, n) = (juc, [n])

(* -------------------------------------------------------------------- *)
let process_progress (prtc, mkpv) t =
  let t = 
    match t with 
    | None   -> t_id None 
    | Some t -> prtc mkpv t
  in
    t_progress t

(* -------------------------------------------------------------------- *)
let rec process_tactics mkpv (tacs : ptactic list) (gs : goals) : goals =
  match tacs with
  | [] -> gs

  | tac1 :: tacs2 ->
      let gs = process_tactic mkpv tac1 gs in
        process_tactics mkpv tacs2 gs

(* -------------------------------------------------------------------- *)
and process_tactic_chain mkpv (t : ptactic_chain) (gs : goals) : goals =
  match t with
  | Psubtacs tacs   -> t_subgoal   (List.map (process_tactic1 mkpv) tacs) gs
  | Pfirst   (t, i) -> t_on_firsts (process_tactic1 mkpv t) i gs
  | Plast    (t, i) -> t_on_lasts  (process_tactic1 mkpv t) i gs
  | Protate  (d, i) -> t_rotate    d i gs

(* -------------------------------------------------------------------- *)
and process_tactic mkpv (tac : ptactic) (gs : goals) : goals =
  let gs = process_tactic_core mkpv tac.pt_core gs in
  let gs = t_on_goals (EcHiLogic.process_intros tac.pt_intros) gs in
    gs

(* -------------------------------------------------------------------- *)
and process_tactic1 mkpv (tac : ptactic) ((juc, n) : goal) : goals =
  process_tactic mkpv tac (juc, [n])

(* -------------------------------------------------------------------- *)
and process_tactic_core mkpv (tac : ptactic_core) (gs : goals) : goals =
  let loc = tac.pl_loc in

  let tac =
    match unloc tac with
    | Pidtac msg     -> `One (t_id msg)
    | Pdo (b, n, t)  -> `One (t_do b n (process_tactic_core1 mkpv t))
    | Ptry t         -> `One (t_try (process_tactic_core1 mkpv t))
    | Pby t          -> `One (process_by mkpv t)
    | Pseq tacs      -> `One (fun (juc, n) -> process_tactics mkpv tacs (juc, [n]))
    | Pcase  i       -> `One (process_case loc i)
    | Pprogress t    -> `One (process_progress (process_tactic_core1, mkpv) t)
    | Padmit         -> `One (t_admit)
    | Pdebug         -> `One (process_debug)
    | Plogic t       -> `One (process_logic mkpv loc t)
    | PPhl tac       -> `One (EcHiPhl.process_phl loc tac)
    | Psubgoal tc    -> `All (process_tactic_chain mkpv tc)
  in

  let tac = match tac with `One t -> t_on_goals t | `All t -> t in

    set_loc loc tac gs

(* -------------------------------------------------------------------- *)
and process_tactic_core1 mkpv (tac : ptactic_core) ((juc, n) : goal) : goals =
  process_tactic_core mkpv tac (juc, [n])

(* -------------------------------------------------------------------- *)
and process_by mkpv t (juc, n) =
  let gs = process_tactics mkpv t (juc, [n]) in
  let gs = t_on_goals EcHiLogic.process_trivial gs in

    match gs with
    | (_, []) -> gs
    | _ -> tacuerror "[by]: cannot close on goals"