require import Pair.
require import Int.
require import Bitstring.
require import Fun.
require        Set.
require import real.

op caract (p:'a Pred, x : 'a) : real = 
   if p x then 1%r else 0%r.

axiom mu_bounded :
  forall (d: 'a distr, P:'a Pred), 
     0%r <= mu d P && mu d P <= 1%r .

axiom mu_false : forall (d: 'a distr), mu d Pfalse = 0%r. 

axiom mu_incl : forall (P1:_, P2:'a Pred, d:'a distr),
   Pincl P1 P2 => mu d P1 <= mu d P2.

op mu_weight (d : 'a distr) : real = 
  mu d Ptrue.
  
op mu_x (d:'a distr, x:'a) : real = 
  mu d (Peq x).

(** TODO : We need a way to automatically rewrite supp_def lemmas *)

op in_supp (x:'a, d:'a distr) : bool = 
   mu_x d x <> 0%r.

lemma mu_weight_0_1 : forall (d:'a distr),
   mu_weight d = 0%r =>
   forall (P:'a Pred), mu d P = 0%r
proof.
 intros d H P.
 cut H0: (mu d P <= mu d Ptrue).
 apply mu_incl<:'a>(P, Ptrue, d, _).
 trivial.
 trivial.
save.


lemma mu_weight_0_2 : forall (d:'a distr),
    (forall (P:'a Pred), mu d P = 0%r) =>
    mu_weight d = 0%r.

lemma mu_weight_0 : forall (d:'a distr),
   mu_weight d = 0%r <=>
   forall (P:'a Pred), mu d P = 0%r.

(** FIXME/ TODO 
 * Try to express the "mu" axioms in term of mu as much as possible.
 * Then use it to prove lemma on mu_x
 * i.e as in Dunit
*)
theory Dunit.

  op dunit : 'a -> 'a distr.

  axiom mu_def_in : forall (x:'a, P:'a Pred),
     P x =>
     mu (dunit x) P = 1%r.

  axiom mu_def_notin : forall (x:'a, P: 'a Pred), 
     !P x =>
     mu (dunit x) P = 0%r.

  lemma mu_x_def_eq : forall (x:'a),
     mu_x (dunit x) x = 1%r.

  lemma mu_x_def_diff : forall (x:'a, y:'a),
     x <> y =>
     mu_x (dunit x) y = 0%r.

  lemma supp_def :  forall (x1:'a, x2:_), 
     in_supp x1 (dunit x2) <=> x1 = x2.

  lemma mu_weight : forall (x:'a),
     mu_weight (dunit x) = 1%r.

end Dunit.

theory Duni.

  op duni : 'a Set.t -> 'a distr.

  axiom supp_def : forall (x:'a, X:_), in_supp x (duni X) <=> Set.mem x X.

  axiom mu_def : forall (X:'a Set.t, P:'a Pred), 
    !Set.is_empty X => 
       mu (duni X) P = (Set.card (Set.filter P X))%r / (Set.card X)%r. 

  axiom mu_def_empty : forall (P:'a Pred), 
      mu (duni Set.empty) P = 0%r.

  axiom mu_x_def_in : forall (X:'a Set.t, x:'a), 
    Set.mem x X => 
       mu_x (duni X) x = 1%r / (Set.card X)%r. 

  axiom mu_x_def_notin : forall (X:'a Set.t, x:'a), 
    !Set.mem x X => 
       mu_x (duni X) x = 0%r.

  axiom mu_weight : forall (X:'a Set.t), 
     !Set.is_empty X =>
     mu_weight (duni X) = 1%r.

end Duni.

theory Dbool.
  cnst dbool : bool distr.

  axiom supp_def : forall (b:bool), in_supp b dbool.

  axiom mu_def : forall (P:bool Pred), 
      mu dbool P = 
       (1%r/2%r) * caract P true 
     + (1%r/2%r) * caract P false.
  
  axiom mu_x_def : forall (b:bool), mu_x dbool b = 1%r/2%r.

  lemma mu_weight : mu_weight dbool = 1%r.

end Dbool.

theory Dinter.

  op dinter : (int,int) -> int distr.

  axiom supp_def : forall (i:int,j:int,x:int), 
    in_supp x (dinter i j) <=>
     i <= x && x <= j. 

  axiom mu_x_def_in : forall (i:_,j:_,x:int),
     i <= x => x <= j =>
     mu_x (dinter i j) x = 1%r / (i - j + 1)%r. 

  axiom mu_x_def_other : forall (i:_,j:_,x:int),
    x < i || j < x =>  mu_x (dinter i j) x = 0%r.

  axiom mu_weight_le : forall (i:int,j:int), i <= j => 
     mu_weight(dinter i j) = 1%r.  
 
  axiom mu_weight_gt : forall (i:int,j:int), j < i =>
    mu_weight(dinter i j) = 0%r.   

end Dinter.

theory Dbitstring.

  op dbitstring : int -> bitstring distr.

  axiom supp_def : forall ( k:int, s:bitstring),
      in_supp s (dbitstring k) <=> length s = k.

  axiom mu_x_def_in : forall (k:int, s:bitstring),
    length s = k => 
    mu_x (dbitstring k) s = 1%r/(2^k)%r.

  axiom mu_x_def_other : forall (k:int, s:bitstring),
    length s <> k => mu_x (dbitstring k) s = 0%r.

  axiom mu_weight_pos : forall (k:int), 0 <= k =>
    mu_weight(dbitstring k) = 1%r.

  axiom mu_weight_neg : forall (k:int), k < 0 =>
    mu_weight(dbitstring k) = 0%r.

end Dbitstring.


theory Dprod.
  op dprod : ('a distr, 'b distr) -> ('a * 'b) distr.
  
  axiom supp_def : forall (d1:'a distr, d2:'b distr, p: _), 
      in_supp p (dprod d1 d2) <=> in_supp (fst p) d1 && in_supp (snd p) d2.

  axiom mu_x_def : forall (d1:'a distr, d2:'b distr, p: _), 
      mu_x (dprod d1 d2)  p = mu_x d1 (fst p) * mu_x d2 (snd p).

  axiom mu_weight : forall (d1:'a distr, d2:'b distr), 
     mu_weight (dprod d1 d2) = mu_weight d1 * mu_weight d2.

end Dprod.

theory Drestr.
  op drestr : ('a distr, 'a Set.t) -> 'a distr.
 
  axiom supp_def : forall (d:'a distr, X:'a Set.t, x:'a), 
     in_supp x (drestr d X) <=> in_supp x d && !Set.mem x X.
  
  axiom mu_x_def_notin : forall (d:'a distr, X:'a Set.t, x:'a), 
    in_supp x d => !Set.mem x X =>
    mu_x (drestr d X) x = mu_x d x.

  axiom mu_x_def_in : forall (d:'a distr, X:'a Set.t, x:'a), 
    in_supp x d => Set.mem x X =>
    mu_x (drestr d X) x = 0%r.

  axiom mu_weight : forall (d:'a distr, X:'a Set.t), 
    mu_weight(drestr d X) = mu_weight(d) - mu d (Set.Pmem X).

end Drestr.

theory Dscale.

  op dscale : 'a distr -> 'a distr.

  axiom supp_def : forall (d:'a distr, x:'a),
    in_supp x (dscale d) <=> in_supp x d.

  axiom mu_x_def_0 : forall (d:'a distr, x:'a),
    mu_weight d = 0%r => 
    mu_x (dscale d) x = 0%r.

  axiom mu_x_def_diff : forall (d:'a distr, x:'a),
    mu_weight d <> 0%r =>
    mu_x (dscale d) x =  mu_x d x / mu_weight d.  

  axiom mu_weight_0 : forall (d:'a distr),
    mu_weight d = 0%r => 
    mu_weight (dscale d) = 0%r.

  axiom mu_weight_1 : forall (d:'a distr),
    mu_weight d <> 0%r => 
    mu_weight (dscale d) = 1%r.

end Dscale.

theory Dexcepted.
  op [\] (d:'a distr, X:'a Set.t) : 'a distr =
    Dscale.dscale (Drestr.drestr d X). 

  lemma supp_def : forall (d:'a distr, X:'a Set.t, x:'a),
     (in_supp x (d \ X) => (in_supp x d /\ !Set.mem x X)) /\
     ((in_supp x d /\ !Set.mem x X) => in_supp x (d \ X))
  proof.
  intros d X x;split.
    intros in_supp;split;trivial.
    intros in_supp_nmem;trivial.
  save.
    
  lemma mu_x_def: forall (d:'a distr, X:'a Set.t, x:'a),
     mu_x (d \ X) x = (in_supp x (d \ X)) ? mu_x d x / (mu_weight d - mu d (Set.Pmem X)) : 0%r.

  lemma mu_weight_def: forall (d:'a distr, X:'a Set.t),
    mu_weight (d \ X) = (mu_weight d = mu d (Set.Pmem X)) ? 0%r : 1%r.
end Dexcepted.

theory Dlap.

  op dlap : (int,real) -> int distr.

  axiom in_supp : forall (mean:_, scale:_, x:_), 
    0%r <= scale => 
    in_supp x (dlap mean scale).

(*
  axiom mu_x_def : forall (mean:int, scale:real, x:int),
    0%r <= scale => 
    mu_x (dlap mean scale) x = 
      (1%r / (2%r*scale))
    * real.exp( -! (| x%r - mean%r|)) / scale. 
*)
  axiom mu_weight : forall  (mean:_, scale:_), 
    0%r <= scale =>
    mu_weight (dlap mean scale) = 1%r.

end Dlap.

(* x = $dlap(x1,s)   ~ x = $dlap(0,s) + x1 : ={x1,s} ==> ={x}. *)


(*
y1 = $d1 ~ y2 = $d2 : P ==> Q.
  rnd (f,finv).
  P => (forall x1, in_supp(d1,x1) => mu_x(d1,x1) = mu_x(d2,f(x1))) /\
       (forall x2, in_supp(d2, x2) => in_supp(d1, finv(x2))) /\
       (forall x1, in_supp(d1,x1) => finv(f(x1)) = x1) /\
       (forall x2, in_supp(d2, x2) => f(finv(x2)) = x2) /\
       forall x1, in_supp(d1,x1) =>
         Q{y1{1} <- x1, y2{2} <- f(x1) }.

*)