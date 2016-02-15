(* --------------------------------------------------------------------
 * Copyright (c) - 2012--2016 - IMDEA Software Institute
 * Copyright (c) - 2012--2016 - Inria
 *
 * Distributed under the terms of the CeCILL-B-V1 license
 * -------------------------------------------------------------------- *)

(* -------------------------------------------------------------------- *)
require import Int Real RealExtra.
require (*--*) Ring.

(* -------------------------------------------------------------------- *)
theory RField.
  clone include Ring.Field with
    type t <- real,
    op   zeror <- 0%r,
    op   oner  <- 1%r,
    op   ( + ) <- Real.( + ),
    op   [ - ] <- Real.([-]),
    op   ( * ) <- Real.( * ),
    op   invr  <- Real.inv
    proof * by smt remove abbrev (-) remove abbrev (/).

  lemma nosmt ofintR (i : int): ofint i = i%r.
  proof.
    have h: forall i, 0 <= i => ofint i = i%r.
      elim=> [|j j_ge0 ih] //=; first by rewrite ofint0.
      by rewrite ofintS // fromintD ih addrC.
    elim/natind: i; smt.
  qed.

  lemma intmulr x c : intmul x c = x * c%r.
  proof.
    have h: forall cp, 0 <= cp => intmul x cp = x * cp%r.
      elim=> /= [|cp ge0_cp ih].
        by rewrite mulr0z.
      by rewrite mulrS // ih fromintD mulrDr mulr1 addrC.
    case: (lezWP c 0) => [le0c|_ /h //].
    rewrite -{2}(@oppzK c) fromintN mulrN -h 1:smt.
    by rewrite mulrNz opprK.
  qed.

  lemma nosmt double_half (x : real) : x / 2%r + x / 2%r = x.
  proof. by rewrite -ofintR -mulrDl -mul1r2z -mulrA divff // ofintR. qed.
end RField.

(* -------------------------------------------------------------------- *)
instance ring with int
  op rzero = Int.zero
  op rone  = Int.one
  op add   = Int.( + )
  op opp   = Int.([-])
  op mul   = Int.( * )
  op expr  = Int.( ^ )

  proof oner_neq0 by smt
  proof addr0     by smt
  proof addrA     by smt
  proof addrC     by smt
  proof addrN     by smt
  proof mulr1     by smt
  proof mulrA     by smt
  proof mulrC     by smt
  proof mulrDl    by smt
  proof expr0     by smt
  proof exprS     by smt.
