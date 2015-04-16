(* --------------------------------------------------------------------
 * Copyright (c) - 2012-2015 - IMDEA Software Institute and INRIA
 * Distributed under the terms of the CeCILL-B licence.
 * -------------------------------------------------------------------- *)

require import Real.
require import FSet.
require import ISet.
require import Pair.
require import Distr.
require import Monoid.

require Means.

theory MeansBool.
  
  clone export Means as M with
  type input <- bool,
  op d <- {0,1}.

  lemma Mean (A<:Worker) &m (p: bool -> glob A -> output -> bool):
     Pr[Rand(A).main() @ &m : p (fst res) (glob A) (snd res)] = 
     1%r/2%r*(Pr[A.work(true) @ &m : p true (glob A) res] + 
                Pr[A.work(false) @ &m : p false (glob A) res]).
  proof.
    cut Hcr: forall x, 
             mem x (create (support {0,1})) <=>
             mem x (add true (add false (FSet.empty)%FSet)).
      by intros=> x; rewrite !FSet.mem_add; case x=> //=; smt.
    cut Hf : Finite.finite (create (support {0,1})).
      by exists (FSet.add true (FSet.add false FSet.empty)) => x;apply Hcr.
    cut := Mean A &m p => /= -> //.
    cut -> : Finite.toFSet (create (support {0,1})) = 
             (FSet.add true (FSet.add false FSet.empty)).
    by apply FSet.set_ext => x; rewrite Finite.mem_toFSet //;apply Hcr.
    rewrite Mrplus.sum_add;first smt.
    rewrite Mrplus.sum_add;first smt.
    rewrite Mrplus.sum_empty /= !Bool.Dbool.mu_x_def.
    cut Hd: 2%r <> 0%r by smt.
    by algebra.
  qed.

end MeansBool.

clone import MeansBool as MB with 
  type M.output <- bool.

lemma Sample_bool (A<:Worker) &m (p:glob A -> bool):
  Pr[Rand(A).main() @ &m : fst res = snd res /\ p (glob A)] - 
  Pr[A.work(false) @ &m : p (glob A)]/2%r = 
      1%r/2%r*(Pr[A.work(true) @ &m : res /\ p (glob A)] - 
               Pr[A.work(false) @ &m : res /\ p (glob A)]).
proof strict.
  cut := Mean A &m (fun b (gA:glob A) (b':bool), b = b' /\ p gA) => /= ->.
  cut Hd: 2%r <> Real.zero by smt.
  cut -> : Pr[A.work(true) @ &m : true = res /\ p (glob A)] = 
           Pr[A.work(true) @ &m : res /\ p (glob A)].
    by rewrite Pr[mu_eq];smt.
  cut -> : Pr[A.work(false) @ &m : false = res /\ p (glob A)] = 
           Pr[A.work(false) @ &m : !res /\ p (glob A)].
    by rewrite Pr[mu_eq];smt.       
  cut -> : Pr[A.work(false) @ &m : p (glob A)] = 
           Pr[A.work(false) @ &m : (!res /\ p (glob A)) \/ (res /\ p (glob A))].
    by rewrite Pr[mu_eq];smt.
  rewrite Pr[mu_disjoint];first smt.
  by fieldeq.
qed.

lemma Sample_bool_lossless (A<:Worker) &m:
  Pr[A.work(false) @ &m : true] = 1%r =>
  Pr[Rand(A).main() @ &m : fst res = snd res] - 1%r/2%r = 
      1%r/2%r*(Pr[A.work(true) @ &m : res] - Pr[A.work(false) @ &m : res]).
proof strict.
  intros Hloss.
  cut := Sample_bool A &m (fun x, true) => /= <-.
  by rewrite Hloss.
qed.


