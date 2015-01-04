(* --------------------------------------------------------------------
 * Copyright (c) - 2012-2015 - IMDEA Software Institute and INRIA
 * Distributed under the terms of the CeCILL-C license
 * -------------------------------------------------------------------- *)

require export ExtEq.

(*** Working with predicates *)
(** Inclusion order *)
pred (<=) (p q:'a -> bool) =
  forall a, p a => q a.

pred (< ) (p q:'a -> bool) =
  p <= q /\ !(q <= p).

lemma nosmt leq_refl (X Y:'a -> bool):
  X = Y => X <= Y
by [].

lemma nosmt leq_asym (X Y:'a -> bool):
  X <= Y => Y <= X => X = Y
by (rewrite -fun_ext; smt).

lemma nosmt leq_tran (X Y Z:'a -> bool):
  X <= Y => Y <= Z => X <= Z
by [].

lemma nosmt subpred_eqP (p1 p2 : 'a -> bool):
  (forall x, p1 x <=> p2 x) <=> (p1 <= p2 /\ p2 <= p1).
proof. smt. qed.

(** Lifting boolean operators to predicates *)
op pred1  ['a] (c : 'a) = fun (x : 'a), c = x.
op predT  ['a] = fun (x : 'a), true.
op pred0  ['a] = fun (x : 'a), false.
op predC  ['a] (P : 'a -> bool) = fun (x : 'a), ! (P x).
op predC1 ['a] (c : 'a) = fun (x : 'a), c <> x.
op predD1 ['a] (P : 'a -> bool) (c : 'a) = fun (x : 'a), c <> x /\ P x.

op True   = fun (x:'a), true.
op False  = fun (x:'a), false.

op [!]  (P:'a -> bool)  : 'a -> bool = fun x, !P x.
op (/\) (P Q:'a -> bool): 'a -> bool = fun x, P x /\ Q x.
op (\/) (P Q:'a -> bool): 'a -> bool = fun x, P x \/ Q x.

(** Lemmas *)
(* True *)
lemma True_true (x:'a): True x by done.

lemma True_unique (p:'a -> bool): (forall x, p x) => p = True.
proof strict.
by rewrite -fun_ext=> px x; rewrite px.
qed.

(* False *)
lemma False_false (x:'a): !False x by [].

lemma False_unique (p:'a -> bool): (forall x, !p x) => p = False.
proof strict.
by rewrite -fun_ext=> px x; rewrite /False neqF px.
qed.

(* Not *)
lemma Not_not (p:'a -> bool) x: (!p) x <=> !p x by [].

(* And *)
lemma And_and (p q:'a -> bool) x: (p /\ q) x <=> (p x /\ q x) by [].

lemma And_leq_l (p q:'a -> bool): (p /\ q) <= p by [].

lemma And_leq_r (p q:'a -> bool): (p /\ q) <= q by [].

(* Or *)
lemma Or_or (p q:'a -> bool) x: (p \/ q) x <=> (p x \/ q x) by [].

lemma Or_geq_l (p q:'a -> bool): p <= (p \/ q) by [].

lemma Or_geq_r (p q:'a -> bool): q <= (p \/ q) by [].

(* Lifting useful results on booleans to predicates *)
lemma Excluded_Middle (p:'a -> bool): ((!p) \/ p) = True
by (apply fun_ext; smt).

lemma Sound (p:'a -> bool): ((!p) /\ p) = False
by (apply fun_ext; smt).
