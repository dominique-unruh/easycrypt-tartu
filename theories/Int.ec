(* --------------------------------------------------------------------
 * Copyright (c) - 2012-2015 - IMDEA Software Institute and INRIA
 * Distributed under the terms of the CeCILL-B licence.
 * -------------------------------------------------------------------- *)

import why3 "int" "Int"
  op "prefix -" as "[-]".

(* Random thing *)
op int_of_bool (b : bool) = if b then 1 else 0.
  
(* Group operation *)

op zeroz = 0.
op onez  = 1.

lemma nosmt addz1_neq0 (i : int): 0 <= i => i+1 <> 0
by smt full.

lemma nosmt onez_neq0 : 1 <> 0 
by smt full.

lemma nosmt addzA (x y z : int): x + (y + z) = (x + y) + z
by smt full.

lemma nosmt addzC (x y : int): x + y = y + x
by smt full.

lemma nosmt add0z (x : int): 0 + x = x
by smt full.

lemma nosmt addNz (x : int): (-x) + x = 0
by smt full.

lemma nosmt addzCA (x y z : int): x + (y + z) = y + (x + z)
by smt full.

lemma nosmt addzAC (x y z : int): (x + y) + z = (x + z) + y
by smt full.

lemma nosmt addIz (x1 x2 y : int): x1 + y = x2 + y => x1 = x2
by smt full.

lemma nosmt addzI (x1 x2 y : int): y + x1 = y + x2 => x1 = x2
by smt full.

lemma nosmt oppzK (x : int): -(-x) = x
by smt full.

lemma nosmt oppz0: -0 = 0
by smt full.

lemma nosmt addAzN (x y : int): (x + y) - y = x
by smt full.

lemma nosmt mulzA  (x y z : int): x * (y * z) = (x * y) * z
by smt full.

lemma nosmt mulzC  (x y : int): x * y = y * x
by smt full.

lemma nosmt mul1z  (x : int): 1 * x = x
by smt full.

lemma nosmt mulzDl (x y z : int): (x + y) * z = x * z + y * z
by smt full.

lemma subzE (x y : int): x - y = x + (- y)
by smt full.

(** Number theory *)
(* TODO: I merged in some stray bits from NewList and this may appear to be in whatever order... it is. *)

op "`|_|" (x:int) = (0 <= x) ? x : -x.

lemma nosmt lez_norm_add (x y : int): `|x + y| <= `|x| + `|y|
by smt full.

lemma nosmt addz_gt0     (x y : int): 0 < x => 0 < y => 0 < x + y
by smt full.

lemma nosmt norm_eq0     (x   : int): `|x| = 0 => x = 0
by smt full.

lemma nosmt gez_leVge    (x y : int): 0 <= x => 0 <= y => x <= y \/ y <= x
by smt full.

lemma nosmt normzM       (x y : int): `|x * y| = `|x| * `|y|
by smt full.

lemma nosmt lez_def      (x y : int): x <= y <=> `|y - x| = y - x
by smt full.

lemma nosmt ltz_def      (x y : int): x < y <=> ( y <> x /\ x <= y)
by smt full.

lemma nosmt subzz (z : int): z - z = 0 by smt full.

lemma nosmt lezz (z : int): z <= z by [].
lemma nosmt ltzz (z : int): z < z <=> false by smt full.

lemma nosmt ltzNge (x y : int): (x <  y) <=> !(y <= x) by smt full.
lemma nosmt lezNgt (x y : int): (x <= y) <=> !(y <  x) by smt full.

lemma nosmt gez_le (x y : int): (x >= y) <=> (y <= x) by smt full.
lemma nosmt gtz_lt (x y : int): (x >  y) <=> (y <  x) by smt full.

lemma nosmt neq_ltz (x y : int): (x <> y) <=> (x < y \/ y < x) by smt full.
lemma nosmt eqz_leq (x y : int): (x = y) <=> (x <= y /\ y <= x) by [].

lemma nosmt lez_addl (x y z : int): (x + y <= x + z) <=> (y <= z) by smt full.

lemma nosmt lez_add1r (x y : int): (1 + x <= y) = (x < y) by smt full.

theory Induction.

  axiom nosmt induction (p:int -> bool):
    (p 0) =>
    (forall i, 0 <= i => p i => p (i + 1)) =>
    (forall i, 0 <= i => p i).

  lemma nosmt strongInduction (p:int -> bool):
    (forall j, 0 <= j => (forall k, 0 <= k < j => p k) => p j) =>
    (forall i, 0 <= i => p i).
  proof strict.
    intros hyp i iVal.
    apply (induction (fun i, forall k, 0 <= k <= i => p k) _ _ i); smt full.
  qed.

  lemma nosmt natind (p : int -> bool):
       (forall n, n <= 0 => p n)
    => (forall n, 0 <= n => p n => p (n+1))
    => forall n, p n.
  proof.
    move=> h0 hS n; case (n < 0); 1: smt full.
    by rewrite -lezNgt; elim/induction n; smt.
  qed.

  lemma nosmt natcase (p : int -> bool):
       (forall n, n <= 0 => p n)
    => (forall n, 0 <= n => p (n+1))
    => forall n, p n.
  proof. smt full. qed.

  lemma nosmt ge0ind (p : int -> bool):
       (forall n, n < 0 => p n)
    => p 0
    => (forall n, 0 <= n => p n => p (n+1))
    => forall n, p n.
  proof.
    move=> hN h0 hS n; case (n < 0); 1: by move=> /hN.
    by rewrite -lezNgt; elim/induction n.
  qed.

  lemma nosmt ge0case (p : int -> bool):
       (forall n, n < 0 => p n)
    => p 0
    => (forall n, 0 <= n => p (n+1))
    => forall n, p n.
  proof. smt full. qed.
end Induction.

(* Fold operator *)

op fold : ('a -> 'a) -> 'a -> int -> 'a.

axiom foldle0 p (f : 'a -> 'a) a: p <= 0 => fold f a p = a.

lemma fold0 (f : 'a -> 'a) a: fold f a 0 = a
by smt full.

axiom foldS (f : 'a -> 'a) a n: 0 <= n => fold f a (n+1) = f (fold f a n).

lemma nosmt foldpos (f : 'a -> 'a) a n: 0 < n => f (fold f a (n-1)) = fold f a n
by smt full.

lemma fold_add (f : 'a -> 'a) a n1 n2 : 0 <= n1 => 0 <= n2 =>
   fold f (fold f a n2) n1 = fold f a (n1 + n2).
proof. elim/Induction.induction n1; smt full. qed.

(* Power *)

op ( ^ ) (x:int) (p:int) = fold (( * ) x) 1 p
axiomatized by powE.

lemma nosmt powNeg p x: p <= 0 => x ^ p = 1
by smt full.

lemma pow0 x: x ^ 0 = 1
by smt full.

lemma powS p x: 0 <= p => x ^ (p+1) = x * x ^ p
by smt full.

lemma pow_add z p1 p2: 0 <= p1 => 0 <= p2 => z^p1 * z^p2 = z^(p1+p2).
proof. 
  move=> Hp1; elim/Induction.induction p2; smt full.
qed.

lemma pow_mul z p1 p2: 0 <= p1 => 0 <= p2 => (z^p1)^p2 = z^(p1*p2).
proof.
  move=> Hp1; elim/Induction.induction p2; smt full.
qed.

lemma powPos z p: 0 < z => 0 < z ^ p.
proof.
 case (0 <= p); intros Hp Hz; last smt full.
 elim/Induction.induction p Hp; smt full.
qed.

lemma pow_Mle (x y:int): 0 <= x <= y => 2^x <= 2^y.
proof.
  intros [leq0_x leqx_y]; cut leq0_y: 0 <= y by smt.
  move: leqx_y; elim /Induction.induction y leq0_y; smt full.
qed.

(* Diveucl *)
import why3 "int" "EuclideanDivision"
  op "div" as "/%";
  op "mod" as "%%".

theory EuclDiv.

  axiom ediv_spec m d:
    d <> 0 =>
    0 <= m %% d < `|d| /\
    m = (m /% d) * d + (m %% d).

  axiom ediv_unique m d q r:
    d <> 0 =>
    0 <= r < `|d| =>
    m = q * d + r =>
    q = m /% d /\ r = m %% d.

  axiom ediv_Mle : forall (m1 m2 d:int), 0 < d => m1 <= m2 => m1/%d <= m2/%d.

  lemma ediv_pos : forall m d, 0 < d => 0 <= m => 0 <= m /%d.
  proof -strict. 
    intros m d Hd Hm.
    apply (Trans _ (0/%d));last apply ediv_Mle;smt.
    elim (ediv_unique 0 d 0 0 _ _ _) => //; smt full.
  qed.
end EuclDiv.

export EuclDiv.

theory Extrema.
  op min (a b:int) = if (a < b) then a else b.

  lemma nosmt minC a b : min a b = min b a
  by smt full.

  lemma nosmt min_lel a b : a <= b => min a b = a
  by smt full.

  lemma nosmt min_ler a b : a <= b => min b a = a
  by smt full.

  lemma nosmt min_is_lb a b:
    min a b <= a /\
    min a b <= b
  by smt full.

  lemma nosmt min_is_glb x a b:
    x <= a => x <= b =>
    x <= min a b
  by smt full.

  lemma nosmt min_is_extremum a b:
    min a b = a \/ min a b = b
  by smt full.

  op max (a b:int) = if (a < b) then b else a.

  lemma nosmt maxC a b : max a b = max b a
  by smt full.

  lemma nosmt max_lel a b : a <= b => max b a = b
  by smt full.

  lemma nosmt max_ler a b : a <= b => max a b = b
  by smt full.

  lemma nosmt max_is_ub a b:
    a <= max a b /\
    b <= max a b
  by smt full.

  lemma nosmt max_is_lub x a b:
    a <= x => b <= x =>
    max a b <= x
  by smt full.

  lemma nosmt max_is_extremum a b:
    max a b = a \/ max a b = b
  by smt full.
end Extrema.
export Extrema.

lemma mulMle : forall (x1 x2 y1 y2:int),
   0 <= x1 <= x2 => 0 <= y1 <= y2 => x1 * y1 <= x2 * y2.
proof.
 intros x1 x2 y1 y2 Hx Hy.
 apply (Trans _ (x1 * y2)).
 rewrite ?(Comm.Comm x1) CompatOrderMult; smt full.
 apply CompatOrderMult; smt full.
qed.

theory ForLoop.
  op range: int -> int -> 'a -> (int -> 'a -> 'a) -> 'a.

  axiom range_base i j (st:'a) f:
    j <= i =>
    range i j st f = st.

  axiom range_ind i j (st:'a) f:
    i < j =>
    range i j st f = range (i + 1) j (f i st) f.

  lemma range_ind_lazy i j (st:'a) f:
    i < j =>
    range i j st f = f (j - 1) (range i (j - 1) st f).
  proof.
  intros=> h; cut {h}: 0 < j-i by smt full.    (* missing gt0_subr *)
  move: {-1}(j-i) (eq_refl (j - i))=> n.
  move=> eq_iBj_n gt0_n; generalize i j eq_iBj_n.
  cut ge0_n: 0 <= n by smt full. generalize ge0_n gt0_n st.
  elim/Induction.induction n; first smt full.
  intros=> n ge0_n IH _ st i j.
  case (n = 0); first intros=> -> h.
    by (cut ->: j = i+1 by smt full); rewrite range_ind ?range_base; smt full.
  intros=> nz_n eq_iBj_Sn; rewrite range_ind; first by smt full.
  (rewrite IH; first 2 smt full); congr => //.
  by rewrite -range_ind; first smt full.
  qed.

  (* General result on boolean accumulation *)
  lemma rangeb_forall i j p b:
    ForLoop.range i j b (fun k b, b /\ p k) =
     (b /\ forall k, i <= k < j => p k).
  proof.
  case (i < j)=> i_j; last smt full.
  pose n := j - i; cut ->: j = n + i by smt full.
  cut: 0 <= n by smt full. elim/Induction.induction n;first by smt full.
  intros i0 Hi0 Hrec;rewrite range_ind_lazy;smt full.
  qed.

  (* General result on restricting the range *)
  lemma range_restr (i j:int) (base:'a) f:
    0 <= j - i =>
    ForLoop.range i j base (fun k a, if i <= k < j then f k a else a) = ForLoop.range i j base f.
  proof.
  intros=> h; case (0 = j - i)=> h2; first smt full.
  pose k:= j - i - 1; cut {1 3}->: j = k + i + 1 by smt full.
  cut: k < j - i by smt full. cut: 0 <= k by smt full.
  by elim/Induction.induction k; smt full.
  qed.

  axiom range_add i j1 j2 (a:'a) f : 0 <= j1 => 0 <= j2 => i <= j1 =>
    range i (j1 + j2) a f = range (i+j1) (j1 + j2) (range i j1 a f) f.
end ForLoop.
