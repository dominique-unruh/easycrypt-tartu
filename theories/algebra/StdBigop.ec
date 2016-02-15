(* --------------------------------------------------------------------
 * Copyright (c) - 2012--2016 - IMDEA Software Institute
 * Copyright (c) - 2012--2016 - Inria
 *
 * Distributed under the terms of the CeCILL-B-V1 license
 * -------------------------------------------------------------------- *)

(* -------------------------------------------------------------------- *)
require import Pred Int IntExtra IntDiv Real RealExtra Ring List.
require import StdRing StdOrder.
require (*--*) Bigop Bigalg.
(*---*) import IntID IntOrder.

pragma Proofs:weak.

(* -------------------------------------------------------------------- *)
theory Bigint.
clone include Bigalg.BigOrder with
  type t <- int,
  pred Num.Domain.unit (z : int) <- (z = 1 \/ z = -1),
    op Num.Domain.zeror  <- 0,
    op Num.Domain.oner   <- 1,
    op Num.Domain.( + )  <- Int.( + ),
    op Num.Domain.([-])  <- Int.([-]),
    op Num.Domain.( * )  <- Int.( * ),
    op Num.Domain.invr   <- (fun (z : int) => z),
    op Num.Domain.intmul <- IntID.intmul,
    op Num.Domain.ofint  <- IntID.ofint,
    op Num.Domain.exp    <- IntID.exp,

    op Num."`|_|" <- Int."`|_|",
    op Num.( <= ) <- Int.(<=),
    op Num.( <  ) <- Int.(< )

    proof Num.Domain.* by smt, Num.Axioms.* by smt

    rename [theory] "BAdd" as "BIA"
           [theory] "BMul" as "BIM"

    remove abbrev Num.Domain.(-)
    remove abbrev Num.Domain.(/).

lemma nosmt sumzE ss : sumz ss = BIA.big predT (fun x => x) ss.
proof. by elim: ss=> [|s ss ih] //=; rewrite BIA.big_cons -ih. qed.

lemma nosmt big_constz (P : 'a -> bool) x s:
  BIA.big P (fun i => x) s = x * (count P s).
proof. by rewrite BIA.sumr_const -IntID.intmulz. qed.

lemma nosmt big_count (P : 'a -> bool) s:
    BIA.big P (fun (x : 'a) => count (pred1 x) s) (undup s)
  = size (filter P s).
proof. admit. qed.

abbrev sumid i j = BIA.bigi predT (fun n => n) i j.

lemma sumidE n : 0 <= n =>
  BIA.bigi predT (fun i => i) 0 n = (n * (n - 1)) %/ 2.
proof.
elim: n => /= [|n ge0_n ih]; first by rewrite BIA.big_geq // div0z.
rewrite BIA.big_int_recr //= ih addrK mulrC -{3}(mulzK n 2) //.
by rewrite -divzDl 2:/# dvdzE -oddPn oddM -{2}(addzK 1) addzAC oddS /#.
qed.
end Bigint.

import Bigint.

(* -------------------------------------------------------------------- *)
theory Bigreal.
clone include Bigalg.BigOrder with
  type t <- real,
  pred Num.Domain.unit (z : real) <- (z <> 0%r),
    op Num.Domain.zeror  <- 0%r,
    op Num.Domain.oner   <- 1%r,
    op Num.Domain.( + )  <- Real.( + ),
    op Num.Domain.([-])  <- Real.([-]),
    op Num.Domain.( * )  <- Real.( * ),
    op Num.Domain.invr   <- Real.inv,
    op Num.Domain.intmul <- RField.intmul,
    op Num.Domain.ofint  <- RField.ofint,
    op Num.Domain.exp    <- RField.exp,

    op Num."`|_|" <- Real."`|_|",
    op Num.( <= ) <- Real.(<=),
    op Num.( <  ) <- Real.(< )

    proof Num.Domain.* by smt, Num.Axioms.* by smt

    rename [theory] "BAdd" as "BRA"
           [theory] "BMul" as "BRM"

    remove abbrev Num.Domain.(-)
    remove abbrev Num.Domain.(/).

import Bigint.BIA Bigint.BIM BRA BRM.

lemma sumr_ofint (P : 'a -> bool) F s :
  (Bigint.BIA.big P F s)%r = (BRA.big P (fun i => (F i)%r) s).
proof.
elim: s => [//|x s ih]; rewrite !big_cons; case: (P x)=> // _.
by rewrite fromintD ih.
qed.

lemma prodr_ofint (P : 'a -> bool) F s :
  (Bigint.BIM.big P F s)%r = (BRM.big P (fun i => (F i)%r) s).
proof.
elim: s => [//|x s ih]; rewrite !big_cons; case: (P x)=> // _.
by rewrite fromintM ih.
qed.

lemma sumr_const (P : 'a -> bool) (x : real) (s : 'a list):
  BRA.big P (fun (i : 'a) => x) s = (count P s)%r * x.
proof. by rewrite sumr_const RField.intmulr RField.mulrC. qed.

lemma sumr1 (s : 'a list) :
  BRA.big predT (fun i => 1%r) s = (size s)%r.
proof. by rewrite sumr_const count_predT RField.mulr1. qed.

lemma sumr1_int (n : int) : 0 <= n =>
  BRA.bigi predT (fun i => 1%r) 0 n = n%r.
proof. by move=> ge0_n; rewrite sumr1 size_range max_ler. qed.
end Bigreal.

import Bigreal.

(* -------------------------------------------------------------------- *)
require import Bool.

(* -------------------------------------------------------------------- *)
clone Bigop as BBA with
  type t <- bool,
  op Support.idm <- false,
  op Support.(+) <- Bool.( ^^ )
  proof Support.Axioms.* by (delta; smt).

(* -------------------------------------------------------------------- *)
theory BBM.
clone include Bigop with
  type t <- bool,
  op Support.idm <- true,
  op Support.(+) <- Pervasive.( /\ )
  proof Support.Axioms.* by (delta; smt).

lemma bigP (P : 'a -> bool) (s : 'a list):
  big predT P s <=> (forall a, mem s a => P a).
proof.
elim: s => [|x s ih] //=; rewrite !big_cons {1}/predT /=.
rewrite ih; split=> [[Px h] y [->|/h]|h] //.
  by split=> [|y sy]; apply/h; rewrite ?sy.
qed.
end BBM.

(* -------------------------------------------------------------------- *)
theory BBO.
clone include Bigop with
  type t <- bool,
  op Support.idm <- false,
  op Support.(+) <- Pervasive.( || )
  proof Support.Axioms.* by (delta; smt).

lemma bigP (P : 'a -> bool) (s : 'a list):
  big predT P s <=> (exists a, mem s a /\ P a).
proof.
elim: s => [|x s ih] //=; rewrite big_cons /predT /=.
rewrite ih; case: (P x)=> Px /=; first by exists x.
have h: forall y, P y => y <> x by move=> y Py; apply/negP=> ->>.
split; case=> y [sy ^Py /h ne_yx]; exists y.
  by rewrite ne_yx. by case: sy.
qed.

lemma nosmt b2i_big (P1 P2 : 'a -> bool) (s : 'a list) :
   b2i (big P1 P2 s) <= BIA.big P1 (fun i => b2i (P2 i)) s.
proof.
elim: s => [|x s ih] //=; rewrite big_cons BIA.big_cons.
case: (P1 x)=> //= P1x; rewrite ora_or b2i_or.
rewrite -addrA ler_add2l ler_subl_addr ler_paddr //.
by rewrite -b2i_and b2i_ge0.
qed.

lemma nosmt b2r_big (P1 P2 : 'a -> bool) (s : 'a list) :
  b2r (big P1 P2 s) <= BRA.big P1 (fun i => b2r (P2 i)) s.
proof.
rewrite b2rE (BRA.eq_bigr _ _ (fun i => (b2i (P2 i))%r)).
  by move=> x _ /=; rewrite b2rE.
by rewrite -sumr_ofint le_fromint b2i_big.
qed.
end BBO.
