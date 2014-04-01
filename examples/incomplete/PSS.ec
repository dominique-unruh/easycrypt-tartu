require import Fun.
require import Int.
require import Real.
require import ISet.
require import FSet.
require import FMap.
require import Pair.
require import Distr.

(*** These belong somewhere else *)
op pi3_1 (t:'a * 'b * 'c): 'a =
  let (a,b,c) = t in a.

op pi3_2 (t:'a * 'b * 'c): 'b =
  let (a,b,c) = t in b.

op pi3_3 (t:'a * 'b * 'c): 'c =
  let (a,b,c) = t in c.

axiom mu_x_FU (d:'a distr) x:
  isuniform d =>
  ISet.Finite.finite (ISet.create (support d)) =>
  in_supp x d =>
  mu_x d x = 1%r / (card (ISet.Finite.toFSet (ISet.create (support d))))%r.

(*** General definitions *)
(** Lengths *)
op k:int.
axiom lt0_k: 0 < k.

op k0:int.
axiom lt0_k0: 0 < k0.

op k1:int.
axiom lt0_k1: 0 < k1.

axiom constraints:
  k0 + k1 < k - 1.

op kg:int = k - k1 - 1.
lemma lt0_kg1: 0 < kg by [].

op kg2:int = k - k0 - k1 - 1.
lemma lt0_kg2: 0 < kg2 by [].

op k':int = k - 1.
lemma lt0_k': 0 < k' by [].

op qS:int.
axiom leq0_qS: 0 <= qS.

op qH:int.
axiom leq0_qH: 0 <= qH.

op qG:int.
axiom leq0_qG: 0 <= qG.

(** Types *)
require AWord.
require import ABitstring.

type message = bitstring.

(* Signatures.
   We use a non-standard distribution instead
   of the default Dword. *)
type signature.
clone import AWord as Signature with
  type word <- signature,
  op length <- k.

(* Nonce *)
type salt.
clone import AWord as Salt with
  type word <- salt,
  op length <- k0.
op sample_salt = Salt.Dword.dword.
axiom saltL: mu sample_salt True = 1%r.

(* Output of H *)
type htag.
clone import AWord as HTag with
  type word <- htag,
  op length <- k1.
op sample_htag = HTag.Dword.dword.
axiom htagL: mu sample_htag True = 1%r.
lemma htagU: isuniform sample_htag by [].
op s_htag = fun (x:message * salt), sample_htag.
lemma s_htagL x: mu (s_htag x) True = 1%r by [].

(* Output of G *)
type gtag.
clone import AWord as GTag with
  type word <- gtag,
  op length <- kg.
op sample_gtag = GTag.Dword.dword.
axiom gtagL: mu sample_gtag True = 1%r.
lemma gtagU: isuniform sample_gtag by [].
op s_gtag = fun (x:htag), sample_gtag.
lemma s_gtagL x: mu (s_gtag x) True = 1%r by [].

(* Output of G2 [G1 produces an HTag] *)
type g2tag.
clone import AWord as G2Tag with
  type word <- g2tag,
  op length <- kg2.

(** Instantiating *)
require PKS.
require OW.
require ROM.

type pkey.
type skey.
op keypairs: (pkey * skey) distr.

op modulus_p: pkey -> int.

op sample_plain: pkey -> signature distr.
axiom nosmt plainF pk: ISet.Finite.finite (ISet.create (support (sample_plain pk))).
axiom nosmt plainU pk: isuniform (sample_plain pk).
axiom nosmt card_plain pk:
  card (ISet.Finite.toFSet (ISet.create (support (sample_plain pk)))) = modulus_p pk.


clone import OW as RSA with
  type pkey <- pkey,
  type skey <- skey,
  type t <- signature,
  op keypairs <- keypairs,
  op challenge <- sample_plain.

(** Things we know on RSA in addition to the one-wayness *)
axiom f_dom_rng: f_dom = f_rng.

axiom nosmt zeros_plain pk:
  valid_pkey pk =>
  in_supp Signature.zeros (sample_plain pk).

axiom nosmt modulus_size pk:
  valid_pkey pk => 2^(k-1) <= modulus_p pk < 2^k.

lemma nosmt card_plain_valid pk:
  valid_pkey pk =>
  2^(k-1) <= card (ISet.Finite.toFSet (ISet.create (support (sample_plain pk)))) < 2^k.
proof strict.
by intros=> valid; rewrite card_plain modulus_size.
qed.

lemma nosmt plain0 pk:
  valid_pkey pk =>
  mu_x (sample_plain pk) Signature.zeros = 1%r / (modulus_p pk)%r.
proof strict.
intros=> valid; rewrite mu_x_FU.
  by apply plainU.
  by apply plainF.
  by apply zeros_plain.
by rewrite card_plain.
qed.

lemma nosmt plain0_bnd pk:
  valid_pkey pk =>
  mu_x (sample_plain pk) Signature.zeros <= 1%r / (2 ^ (k - 1))%r.
proof strict.
intros=> valid; rewrite plain0 //.
cut H: forall x y, 1%r <= x <= y => 1%r / y <= 1%r / x
  by admit. (* Why3 does not know this! *)
apply H; split; first smt.
by cut:= card_plain_valid pk; rewrite card_plain; smt.
qed.

op ( * ): signature -> signature -> pkey -> signature.

axiom mulIn (x y:signature) pk:
  support (sample_plain pk) x =>
  support (sample_plain pk) y =>
  support (sample_plain pk) ((x * y) pk).

axiom mulC (x y:signature) pk:
  support (sample_plain pk) x =>
  support (sample_plain pk) y =>
  (x * y) pk = (y * x) pk.

axiom mulA (x y z:signature) pk:
  (((x * y) pk) * z) pk = (x * ((y * z) pk)) pk.

axiom homo_f_mul (x y:signature) pk:
  support (sample_plain pk) x =>
  support (sample_plain pk) y =>
  f pk ((x * y) pk) = (f pk x * f pk y) pk.

axiom homo_finv_mul (x y:signature) pk sk:
  valid_keys (pk,sk) =>
  support (sample_plain pk) x =>
  support (sample_plain pk) y =>
  finv sk ((x * y) pk) = (finv sk x * finv sk y) pk.

op one_sig: signature.
axiom one_plain pk:
  support (sample_plain pk) one_sig.
axiom mul1 (x:signature) pk:
  support (sample_plain pk) x =>
  (x * one_sig) pk = x.

op inv: signature -> pkey -> signature.
axiom invIn x pk:
  support (sample_plain pk) x =>
  support (sample_plain pk) (inv x pk).

axiom mul_inv (x:signature) pk:
  x <> Signature.zeros =>
  support (sample_plain pk) x =>
  (x * (inv x pk)) pk = one_sig.

(* More facts on RSA for 0 and 1: not sure how useful they are *)
axiom f_zero pk: valid_pkey pk => f pk Signature.zeros = Signature.zeros.
axiom finv_zero sk: valid_skey sk => finv sk Signature.zeros = Signature.zeros.

axiom f_one pk: valid_pkey pk => f pk (one_sig) = one_sig.
axiom finv_one sk: valid_skey sk => finv sk (one_sig) = one_sig.

(** Continuing on with instantiation *)
clone import ROM.LazyEager as Gt with
  type from <- htag,
  type to <- gtag,
  op dsample <- s_gtag.
module G = Gt.Lazy.RO.
module G' = Gt.Eager.RO.

clone import ROM.Lazy as Ht with
  type from <- (message * salt),
  type to <- htag,
  op dsample <- s_htag.
module H = Ht.RO.

clone import PKS as PKSi with
  type pkey <- pkey,
  type skey <- skey,
  type message <- message,
  type signature <- signature.
import EF_CMA.

(*** Defining PSS *)
module PSS(G:Gt.Types.Oracle,H:Ht.Types.Oracle): Scheme = {
  proc init(): unit = {
    G.init();
    H.init();
  }

  proc g1(x:htag):salt = {
    var r:gtag;
    r  = G.o(x);
    return Salt.from_bits (sub (to_bits r) 0 k0);
  }

  proc g2(x:htag):g2tag = {
    var r:gtag;
    r  = G.o(x);
    return G2Tag.from_bits (sub (to_bits r) k0 kg2);
  }

  (* Keygen *)
  proc keygen():(pkey * skey) = {
    var (pk, sk):(pkey * skey);
    (pk,sk) = $keypairs;
    return (pk,sk);
  }

  (* Sign *)
  proc sign(sk:skey, m:message):signature = {
    var r:salt;
    var rMask:salt;
    var maskedR:salt;
    var w:htag;
    var gamma:g2tag;
    var y:signature;

    r = $sample_salt;
    w  = H.o((m,r));
    rMask  = g1(w);
    maskedR = rMask ^ r;
    gamma  = g2(w);
    y = Signature.from_bits (zeros 1 || (to_bits w) || (to_bits maskedR) || (to_bits gamma));
    return (finv sk y); (* For fault injection, we will later refine this; we should make it a function so it can be reasoned about separately *)
  }

  (* Verify *)
  proc verify(pk:pkey, m:message, s:signature):bool = {
    var y:signature;
    var w:htag;
    var w':htag;
    var maskedR:salt;
    var gamma:g2tag;
    var gamma':g2tag;
    var rMask:salt;
    var r:salt;
    var b:bool;

    y = (f pk s);
    b = (sub (to_bits y) 0 1 <> zeros 1);
    w = HTag.from_bits (sub (to_bits y) 1 k1);
    maskedR = Salt.from_bits (sub (to_bits y) (k1 + 1) k0);
    gamma = G2Tag.from_bits (sub (to_bits y) (k1 + k0 + 1) kg2);
    rMask  = g1(w);
    r = rMask ^ maskedR;
    w'  = H.o((m,r));
    gamma'  = g2(w);
    return (w = w' /\ gamma = gamma' /\ !b);
  }
}.

(* A CMA adversary with access to two random oracles *)
module type CMA_2RO(G:Gt.Types.ARO,H:Ht.Types.ARO,S:AdvOracles) = {
  proc * forge(pk:pkey): message * signature {G.o H.o S.sign}
}.

(* Cloning and instantiating the Dice_sampling argument *)
require import Dice_sampling.
import Dprod.
import Dapply.
op lsb0 (pk:pkey) (z:signature) = sub (to_bits z) 0 1 = zeros 1.

clone GenDice as S with 
  type t <- signature,
    type input <- pkey,
    pred valid = valid_pkey,
    type t' <- htag * gtag,
    op d <- sample_plain,
    op test <- lsb0,
    op d' (pk:pkey) <- sample_htag * sample_gtag,
    op sub_supp <- (fun (pk:pkey),
                      Finite.toFSet (filter (lsb0 pk) univ))
    proof *.
  realize dU. proof strict. by move=> pk; rewrite /valid=> vpk; apply RSA.challengeU. qed.
  realize test_in_supp. 
  proof strict. intros pk x /=. admit. qed. (* sub (to_bits x) 0 1 = zeros 1 => toInt x <= modulus_p pk *)
  realize test_sub_supp.
  proof strict.
    cut fSig: Finite.finite univ<:signature>. admit. (* this should be known for finite words on finite alphabets *)
    by intros=> i x; rewrite Finite.filterM 2:mem_filter 2:Finite.mem_toFSet 3:mem_univ.
  qed.
  realize d'_uni. proof strict. intros pk x /=.
    cut fSig: Finite.finite univ<:signature>. admit. (* this should be known for finite words on finite alphabets *)
    intros supp; rewrite Finite.filterM //.
    cut ->: card (filter (lsb0 pk) (Finite.toFSet univ)) =
              2^(k - 1). admit. (* | filter (lambda x, sub (to_bits x) 0 n = x') {words<k>}| = 2^(k - n) *)
    rewrite !Dprod.mu_x_def
            /sample_htag HTag.Dword.mu_x_def
            /sample_gtag GTag.Dword.mu_x_def.
    cut ->: 1%r / (2^k1)%r * (1%r  /(2^kg)%r) = 1%r / ((2^k1) * (2^kg))%r by smt.
    cut ->: forall m n, 0 <= m => 0 <= n => 2^m * 2^n = 2^(m + n); first 3 smt.
    smt.
  qed.
  realize valid_nonempty. proof.
    cut:= witness_support True keypairs _; first by smt.
    rewrite /True /= => [ks]; elim/tuple2_ind ks=> ks pk sk ks_def sup_ks.
    by exists pk; exists sk.
  qed.

section. 
  declare module A:CMA_2RO {G,G',H,EF_CMA,Wrap,OW}.
  axiom adversaryL (G <: Gt.Types.ARO {A}) (H <: Ht.Types.ARO {A}) (S <: AdvOracles {A}):
    islossless G.o => islossless H.o => islossless S.sign =>
    islossless A(G,H,S).forge.

  (* This is the memory that is used by the concrete adversary during the proof *)
  (* In the final transition, we rewrite the concrete adversary into an
     adversary against OW, and therefore drop the secret key from its state.    *)
  local module Mem = {
    var pk:pkey
    var sk:skey
    var qs:message set

    proc init(ks:pkey * skey): unit = {
      (pk,sk) = ks;
      qs = FSet.empty;
    }
  }.

  (* The oracle H is split between adversary queries
     and queries made by the signing oracle, we do this immediately *)
  module type SplitOracle = {
    proc * init(ks:pkey*skey): unit { }
    proc o(c:bool,x:message * salt):htag
  }.

  (** Since the proof mostly works by modifying H,
      with some eager-style interactions with G,
      we will mostly reason in terms of a concrete
      adversary trying to distinguish various
      implementations of G and H through the signing
      oracle. This should allow some abstraction in the
      proof, and in particular in the two eager steps
      on G.                                             **)
  module type Gadv (H:SplitOracle, G:Gt.Types.ARO) = { 
    proc * main (ks:pkey * skey) : bool {H.o G.o}
  }.

  local module Gen (Gadv:Gadv, H:SplitOracle, G:Gt.Types.Oracle) = {
    module GA = Gadv(H,G)

    proc main () : bool = { 
      var keys : pkey * skey;
      var b : bool;
      keys = $keypairs;
      G.init();
      H.init(keys);
      b = GA.main(keys);
      return b;
    }
  }.

  local module GAdv(H:SplitOracle, G:Gt.Types.ARO) = {
    (* Wrapping a split oracle for use by the signing oracle *)
    module Hs = {
      proc o(x:message * salt): htag = {
        var r:htag;
        r = H.o(false,x);
        return r;
      }
    }

    (* Wrapping a split oracle for direct use by the adversary *)
    module Ha = {
      proc o(x:message * salt): htag = {
        var r:htag;
        r = H.o(true,x);
        return r;
      }
    }

    (* Signing oracle *)
    module S = {
      proc sign(m:message): signature = {
        var r:salt;
        var g:gtag;
        var rMask:salt;
        var maskedR:salt;
        var w:htag;
        var gamma:g2tag;
        var y:signature;

        Mem.qs = add m Mem.qs;
        r = $sample_salt;
        w = Hs.o((m,r));
        g = G.o(w);
        rMask = Salt.from_bits (sub (to_bits g) 0 k0);
        maskedR = rMask ^ r;
        gamma = G2Tag.from_bits (sub (to_bits g) k0 kg2);
        y = Signature.from_bits (zeros 1 || (to_bits w) || (to_bits maskedR) || (to_bits gamma));
        return finv Mem.sk y;
      }

      proc fresh(m:message): bool = {
        return !mem m Mem.qs;
      }
    }

    module A = A(G, Ha, S)

    proc main (ks:pkey*skey) : bool = { 
      var m:message;
      var s:signature;
      var y:signature;
      var w:htag;
      var w':htag;
      var g:gtag;
      var maskedR:salt;
      var gamma:g2tag;
      var gamma':g2tag;
      var rMask:salt;
      var r:salt;
      var forged, fresh:bool;

      Mem.init(ks);
      (m,s) = A.forge(Mem.pk);

      y = (f Mem.pk s);
      forged = (sub (to_bits y) 0 1 <> zeros 1);
      w = HTag.from_bits (sub (to_bits y) 1 k1);
      maskedR = Salt.from_bits (sub (to_bits y) (k1 + 1) k0);
      gamma = G2Tag.from_bits (sub (to_bits y) (k1 + k0 + 1) kg2);
      g = G.o(w);
      rMask = Salt.from_bits (sub (to_bits g) 0 k0);
      r = rMask ^ maskedR;
      w' = Hs.o((m,r));
      gamma' = G2Tag.from_bits (sub (to_bits g) k0 kg2);
      forged =  w = w' /\ gamma = gamma' /\ !forged;

      fresh = S.fresh(m);
      return forged /\ fresh;
    }
  }.

  (* Generic losslessness lemmas for wrapped split oracles *)
  local lemma GAdv_Hs_oL (H <: SplitOracle {GAdv}) (G <: Gt.Types.ARO {GAdv}):
    islossless H.o => islossless GAdv(H,G).Hs.o.
  proof strict.
  by intros=> HoL; proc; call HoL.
  qed.

  local lemma GAdv_Ha_oL (H <: SplitOracle {GAdv}) (G <: Gt.Types.ARO {GAdv}):
    islossless H.o => islossless GAdv(H,G).Ha.o.
  proof strict.
  by intros=> HoL; proc; call HoL.
  qed.

  (* Generic losslessness lemma for refactored PSS *)
  local lemma GAdvL (H <: SplitOracle {GAdv}) (G <: Gt.Types.ARO {GAdv}):
    islossless H.o => islossless G.o => islossless GAdv(H, G).main.
  proof strict.
  intros=> HoL GoL; proc.
  call (_: true)=> //.
  wp; call (_: true); first by call HoL.
  wp; call GoL.
  wp; call (adversaryL G (<: GAdv(H,G).Ha) (<: GAdv(H,G).S) _ _ _)=> //.
    by apply (GAdv_Ha_oL H G _).
    proc; wp.
      call GoL.
      call (GAdv_Hs_oL H G _)=> //.
      by rnd; wp; skip; smt.
    by call (_: true); first by wp.
  qed.

  (** A module to store the globals used
      in most variants of H, along with
      some useful equality predicates *)
  local module Hmem = {
    var pk:pkey
    var sk:skey
    var xstar:signature

    proc init(ks:pkey*skey): unit = {
      (pk,sk) = ks;
      xstar = $sample_plain pk;
    }
  }.

  local module Hmap = {
    var m:(message * salt,htag * bool * signature) map

    proc init(ks:pkey*skey) : unit = {
      Hmem.init(ks);
      m = FMap.empty;
    }
  }.

  local equiv Hmem_init:
    Hmem.init ~ Hmem.init: ={ks} /\ valid_keys ks{2} ==>
                           ={glob Hmem} /\
                           valid_keys (Hmem.pk,Hmem.sk){2} /\
                           f_dom Hmem.pk{2} Hmem.xstar{2}
  by (proc; rnd; wp; skip; smt). (* recent changes lead to our having to prove (x.`1,x.`2) = x *)

  local equiv Hmap_init:
    Hmap.init ~ Hmap.init: ={ks} /\ valid_keys ks{2} ==>
                           ={glob Hmap} /\
                           valid_keys (Hmem.pk,Hmem.sk){2} /\
                           f_dom Hmem.pk{2} Hmem.xstar{2}
  by (proc; wp; call Hmem_init).

  (* partial equality between simple and extended maps *)
  pred (=<=) (m0:(message * salt,htag) map) (m1:(message * salt,htag * bool * signature) map) =
    forall x, m0.[x] = if m1.[x] = None then None else Some (pi3_1 (oget m1.[x])).

  (** Zeroth Transition:
      We rewrite PSS into an adversary against Gen with G and a trivial split oracle H0. *)
  local module H0 : SplitOracle = { 
    proc init(ks:pkey*skey): unit = {
      Hmap.init(ks);
    }

    proc o(c:bool,x:message * salt):htag = {
      var r : htag;
      r = $sample_htag;
      if (!in_dom x Hmap.m) Hmap.m.[x] = (r,c,Signature.ones);
      return pi3_1 (oget Hmap.m.[x]);
    }
  }.

  local module G0 = Gen(GAdv,H0,G).

  local equiv PSS_G0_H:
    H.o ~ H0.o: ={x} /\ H.m{1} =<= Hmap.m{2} ==> ={res} /\ H.m{1} =<= Hmap.m{2}.
  proof strict.
  proc; inline H0.o; wp; rnd; wp; skip.
  rewrite /(=<=); progress=> //; [smt|case ((x = x0){2})|smt|case ((x = x0){2}); first smt|smt|smt|smt];
  last 2 by intros=> x_x0;
            do 3!rewrite ?get_set_neq //;
            apply H.
  by intros=> x_x0; subst; rewrite !get_set_eq; smt.
  qed.

  (* More informed use of conseq* might speed up some of the smt calls *)
  local equiv PSS_G0:
    EF_CMA(Wrap(PSS(G,H)),A(G,H)).main ~ G0.main: true ==> ={res}.
  proof strict.
  proc; inline G0.main Gen(GAdv,H0,Gt.Lazy.RO).GA.main; wp.
  (* fresh: by eqobs_in *)
  call (_: ={m} /\ Wrap.qs{1} = Mem.qs{2} ==> ={res});
    first by sim.
  (* In the following, we would really like to be able to write Ht.RO instead of RO,
     for symmetry and ease of reading. This currently does not work. *)
  inline Wrap(PSS(Gt.Lazy.RO,RO)).verify PSS(Gt.Lazy.RO,RO).verify
         PSS(Gt.Lazy.RO,RO).g1 PSS(Gt.Lazy.RO,RO).g2.
  swap{1} [18..19] -3. (* Grouping the two calls to G on the left *)
  inline GAdv(H0,Gt.Lazy.RO).Hs.o; wp; call PSS_G0_H.
  (* We use seq to cut out the calls to G and limit the scope of the rcond call *)
  wp; seq 12 11: (={glob G, w, m, maskedR, gamma} /\
                  H.m{1} =<= Hmap.m{2} /\
                  Wrap.qs{1} = Mem.qs{2} /\
                  b0{1} = forged{2} /\
                  m1{1} = m{2}).
    wp; inline Wrap(PSS(Gt.Lazy.RO,RO)).init PSS(Gt.Lazy.RO,RO).init
               RO.init Gt.Lazy.RO.init PSS(Gt.Lazy.RO,RO).keygen
               H0.init H.init Mem.init.
    call (_: ={glob G} /\ H.m{1} =<= Hmap.m{2} /\ Wrap.qs{1} = Mem.qs{2} /\ Wrap.sk{1} = Mem.sk{2}).
     (* G *)
     by conseq* Gt.Lazy.abstract_o.
     (* H *)
     by proc*; inline GAdv(H0,Gt.Lazy.RO).Ha.o; sp; wp; call PSS_G0_H=> //.
     (* sign *)
     proc; inline PSS(Gt.Lazy.RO, RO).sign.
       wp; inline PSS(Gt.Lazy.RO, RO).g1 PSS(Gt.Lazy.RO, RO).g2 Gt.Lazy.RO.o
                  GAdv(H0, Gt.Lazy.RO).Hs.o.
       rcondf{1} 16;
         first intros=> &m; inline RO.o; do !(rnd; wp); skip; progress=> //; smt.
       wp; rnd{1} cpTrue.
       wp; rnd.
       wp; call PSS_G0_H.
       wp; rnd.
       by wp; skip; smt.
    (* Initialization code *)
    inline Hmap.init Hmem.init; wp; rnd{2} True.
    wp; rnd; wp; skip; progress=> //.
      by rewrite /weight challengeL //; exists pk1skL.`2; smt.
      smt.

  (* Leftover from the main: two successive calls to G.o with
     the same argument yield the same result. *)
  inline Gt.Lazy.RO.o; rcondf{1} 9.
    by intros=> &m //=; do !(rnd; wp); skip; smt.
    by wp; rnd{1} cpTrue; wp; rnd; wp; skip; progress=> //; smt.
  qed.

  (** First Transition: Calling G inside H *)
  (* The proof is by two instances of eager,
     where we build a distinguishing adversary
     against G from parameterized versions of
     H0 and H1, and any GAdv. *)
  local module H1 = {
    proc init(ks:pkey * skey): unit = {
      Hmap.init(ks);
    }

    proc o(c:bool, x:message * salt): htag = {
      var w:htag;
      var st:gtag;

      if (!in_dom x Hmap.m) {
        w = $sample_htag;
        Hmap.m.[x] = (w,c,Signature.ones);
        st = G.o(w);
      }
      return pi3_1 (oget Hmap.m.[x]);
    }
  }.

  local module G1 = Gen(GAdv,H1,G).

  module type PSplitOracle (G:Gt.Types.ARO) = {
    proc * init(ks:pkey * skey): unit
    proc * o(c:bool,x:message * salt): htag {G.o}
  }.

  local module H0' (G:Gt.Types.ARO) = {
    proc init(ks:pkey*skey): unit = {
      Hmap.init(ks);
    }

    proc o(c:bool,x:message * salt):htag = {
      var r : htag;
      r = $sample_htag;
      if (!in_dom x Hmap.m) Hmap.m.[x] = (r,c,Signature.ones);
      return pi3_1 (oget Hmap.m.[x]);
    }
  }.

  local module H1' (G:Gt.Types.ARO) = {
    proc init(ks:pkey * skey): unit = {
      Hmap.init(ks);
    }


    proc o(c:bool, x:message * salt): htag = {
      var w:htag;
      var st:gtag;

      if (!in_dom x Hmap.m) {
        w = $sample_htag;
        Hmap.m.[x] = (w,c,Signature.ones);
        st = G.o(w);
      }
      return pi3_1 (oget Hmap.m.[x]);
    }
  }.

  local module D (Ga:Gadv, H:PSplitOracle, G:Gt.Types.ARO) = {
    module H = H(G)
    module Ga = Ga(H,G)

    proc distinguish(): bool = {
      var b:bool;
      var ks:pkey * skey;
      ks = $keypairs;
      H.init(ks);
      b = Ga.main(ks);
      return b;
    }
  }.

  (* Refactoring G0 into a distinguishing adversary D0 against G *)
  local equiv G0_D0 (Ga <: Gadv {G,Hmap}):
    Gen(Ga,H0,G).main ~ Gt.Types.IND(G,D(Ga,H0')).main: true ==> ={res}.
  proof strict.
  by proc;
     inline Gt.Types.IND(Lazy.RO,D(Ga,H0')).D.distinguish; swap{1} 1 1;
     sim.
  qed.

  (* Applying eager on D0 *)
  local equiv D0_D0e (Ga <: Gadv {G,G'}):
    Gt.Types.IND(G,D(Ga,H0')).main ~ Gt.Types.IND(G',D(Ga,H0')).main: ={glob Ga, glob D, glob H0'} ==> ={res}
  by (conseq* (eagerRO (D(Ga,H0')) _ _)=> //=; [admit (* htag finite *) | apply s_gtagL]).

  (* Equivalence of D0 and D1 *)
  local equiv D0e_D1e (Ga <: Gadv {G',Hmap}):
    Gt.Types.IND(G',D(Ga,H0')).main ~ Gt.Types.IND(G',D(Ga,H1')).main: ={glob Ga} ==> ={res}.
  proof strict.
  proc; call (_: ={glob Eager.RO} /\ forall x, in_dom x G'.m{1}).
    call (_: ={glob Eager.RO, glob Hmap} /\ forall x, in_dom x G'.m{1}).
      (* H *)
      proc; case ((in_dom x Hmap.m){1}).
        rcondf{1} 2; first by intros=> &m; rnd.
        by rcondf{2} 1; last wp; rnd{1}; skip; smt.
        rcondt{1} 2; first by intros=> &m; rnd.
        by rcondt{2} 1; last inline Eager.RO.o; wp; rnd; skip; smt.
      (* G *)
      by conseq* Gt.Eager.abstract_o; first 2 smt.
    call (_: ={ks} ==> ={glob Hmap}); first by sim.
    by rnd; skip; smt.
  call (Gt.Eager.abstract_init _).
    admit (* htag is finite *).
  by skip; smt.
  qed.

  (* Reversting the eager transformation *)
  local equiv D1e_D1 (Ga <: Gadv {G,G'}):
    Gt.Types.IND(G',D(Ga,H1')).main ~ Gt.Types.IND(G,D(Ga,H1')).main: ={glob Ga, glob D, glob H1'} ==> ={res}.
  proof strict.
  symmetry.
  conseq* (eagerRO (D(Ga,H1')) _ _)=> //.
    by progress; smt.
    admit (* htag finite *).
    by apply s_gtagL.
  qed.

  (* Rewriting D1 as an adversary G1 against Gen *)
  local equiv D1_G1 (Ga <: Gadv {G,Hmap}):
    Gt.Types.IND(G,D(Ga,H1')).main ~ Gen(Ga,H1,G).main: true ==> ={res}.
  proof strict.
  by proc;
     inline Gt.Types.IND(Lazy.RO,D(Ga,H1')).D.distinguish; swap{1} 1 1;
     sim.
  qed.

  (* Combining all the proof steps *)
  local equiv G0_G1_abstract (Ga <: Gadv {G,G',Hmap}):
    Gen(Ga,H0,G).main ~ Gen(Ga,H1,G).main: ={glob Ga} ==> ={res}.
  proof strict.
  bypr (res{1}) (res{2})=> // &1 &2 a eq_Ga.
  apply (eq_trans _ Pr[Gt.Types.IND(G,D(Ga,H0')).main() @ &1: a = res]);
    first by byequiv (G0_D0 Ga).
  apply (eq_trans _ Pr[Gt.Types.IND(G',D(Ga,H0')).main() @ &1: a = res]);
    first by byequiv (D0_D0e Ga).
  apply (eq_trans _ Pr[Gt.Types.IND(G',D(Ga,H1')).main() @ &1: a = res]);
    first by byequiv (D0e_D1e Ga).
  apply (eq_trans _ Pr[Gt.Types.IND(G,D(Ga,H1')).main() @ &1: a = res]);
    first by byequiv (D1e_D1 Ga).
  by byequiv (D1_G1 Ga).
  qed.

  local equiv G0_G1_equiv: G0.main ~ G1.main: ={glob GAdv} ==> ={res}
  by apply (G0_G1_abstract GAdv).

  local lemma G0_G1 &m:
    Pr[G0.main() @ &m: res] = Pr[G1.main() @ &m: res]
  by byequiv G0_G1_equiv.

  (** G2: upto "having already called G on the same w that has just been freshly sampled by H"
        + optimistic sampling *)
  local module H2 = {
    var bad:bool

    proc init(ks:pkey*skey): unit = {
      Hmap.init(ks);
      bad = false;
    }  

    proc o (c:bool, x:message * salt): htag = {
      var w:htag;
      var st:gtag;

      if (!in_dom x Hmap.m) {
        w = $sample_htag;
        st = $sample_gtag;
        Hmap.m.[x] = (w,c,Signature.ones);
        bad = bad \/ in_dom w G.m;
        G.m.[w] = st ^ (GTag.from_bits (to_bits (snd x) || zeros (kg - k0)));
      }
      return pi3_1 (oget Hmap.m.[x]);
    }
  }.

  local module G2 = Gen(GAdv, H2, G).

  local equiv G1_G2_H:
    H1.o ~ H2.o:
      !H2.bad{2} /\ ={glob Hmap, glob G, c, x} ==>
      !H2.bad{2} => ={glob Hmap, glob G, res}.
  proof strict.
  proc; if=> //; inline G.o; swap{1} [3..4] -1; wp;
  rnd ((^) (GTag.from_bits (to_bits (snd x{2}) || zeros (kg - k0))));
  wp; rnd; skip; progress=> //.
    by generalize H4; rewrite /s_gtag=> H4;
       rewrite /s_gtag; apply gtagU=> //;
       rewrite /sample_gtag; apply GTag.Dword.in_supp_def.
    by rewrite /s_gtag /sample_gtag; apply GTag.Dword.in_supp_def.
    (* All these are ring rewrites *)
    by rewrite GTag.xorwA GTag.xorwK GTag.xorwC GTag.xorw0.
    by rewrite GTag.xorwA GTag.xorwK GTag.xorwC GTag.xorw0.
    by rewrite GTag.xorwC GTag.xorwA GTag.xorwK GTag.xorwC GTag.xorw0.
    by rewrite GTag.xorwC GTag.xorwA GTag.xorwK GTag.xorwC GTag.xorw0; smt.
  qed.

  local lemma G1_G2_abstract (Ga <: Gadv {G, H1, H2}):
    (forall (H <: SplitOracle{Ga}) (G <: Gt.Types.ARO{Ga}),
       islossless H.o => islossless G.o => islossless Ga(H,G).main) => 
    equiv [Gen(Ga,H1,G).main ~ Gen(Ga,H2,G).main: true ==> !H2.bad{2} => ={res}].
  proof strict.  
  intros=> GaL; proc.
  call (_: H2.bad, ={glob G, glob Hmap}).
    (* H *)
    by conseq* G1_G2_H; smt.
    intros=> _ _; proc.
      if=> //;
      call (Gt.Lazy.lossless_o _);
        first by apply s_gtagL.
      by wp; rnd; skip; progress=> //; apply htagL.
    intros=> _; proc.
      by if => //; wp; do !rnd True;
         skip; smt.
    (* G *)
    by conseq* Gt.Lazy.abstract_o.
    by intros=> _ _;
       conseq* (Gt.Lazy.lossless_o _);
       apply s_gtagL.
    by intros=> _ /=;
       conseq* (Gt.Lazy.lossless_o _);
       apply s_gtagL.
  call (_: ={ks} /\ valid_keys ks{1} ==> ={glob Hmap} /\ !H2.bad{2});
    first by proc; wp; call Hmap_init.
  call Gt.Lazy.abstract_init.
  by rnd; skip; smt.
  qed.

  local equiv G1_G2_equiv: G1.main ~ G2.main: true ==> !H2.bad{2} => ={res}
  by (apply (G1_G2_abstract GAdv); apply GAdvL).

  (* Try using OracleBounds once it is made generic *)
  (* TODO (note that qG, qH and qS also have global versions if needed for the proof) *)
  local lemma GAdv1_GAdv2_BAD &m (qG qH qS:int) ks:
    0 < qG => 0 < qH => 0 < qS =>
    valid_keys ks =>
    Hmap.m{m} = FMap.empty =>
    !H2.bad{m} =>
    G.m{m} = FMap.empty =>
    Pr[ GAdv(H2,G).main(ks) @ &m:
          H2.bad /\
          size Hmap.m <= qH + qS /\
          size G.m <= qG + qH ] <=
      ((qG + qH) * (qH + qS))%r / (2^k1)%r.
  proof strict.
  admit.
(* This proof goes by the failure event lemma and may require dynamic tests for bounding the random oracle sizes *)
(*
  intros=> lt0_qG lt0_qH lt0_qS valid_ks H_empty nbad G_empty.
  fel 1 (card (ISet.Finite.toFSet (dom G.m))) (lambda x, (qH + qS)%r / (2^k1)%r) (qG + qH) H2.bad [H2.o: (card (ISet.Finite.toFSet (dom G.m)) < qG + qH /\ x = x)]=> //.
    (* Inductive argument on the bound *)
    rewrite /int_sum /intval (_: qG + qH = qG + qH - 1 + 1); first smt.
    elim/Induction.induction (qG + qH - 1).
      cut ->: 0 + 1 - 1 = 0 by smt.
      cut minus_neg: 0 > 0 - 1 by smt.
      by rewrite Interval.interval_pos // Interval.interval_neg //; smt.
      intros=> i leq0_i IH.
      cut ->: i + 1 + 1 - 1 = i + 1 by smt.
      rewrite Interval.interval_pos; first smt.
      rewrite Monoid.Mrplus.sum_add //=; first smt.
      by admit. (* Scoping issues? *)
      smt.
    (* Establishing the invariant *)
    inline Mem.init; wp; skip; progress=> //. admit. admit. (* Completeness of FEL tactic: bug #16416 *)
    (* bounding the probability of bad **becoming** true during a single oracle query *)
    fun. admit. (** more invariant needed or completeness issue with FEL: the postcondition should be taken
                    as a "conditional probability" style condition *)
*)
  qed.

  local lemma G1_G2_BAD &m (qG qH qS:int):
    0 < qG => 0 < qH => 0 < qS =>
    Pr[ G2.main() @ &m:
          H2.bad /\
          size Hmap.m <= qH + qS /\
          size G.m <= qG + qH ] <=
      ((qG + qH) * (qH + qS))%r / (2^k1)%r.
  proof strict.
  intros=> lt0_qG lt0_qH lt0_qS;
  byphoare (_: true ==>
               H2.bad /\
               size Hmap.m <= qH + qS /\
               size G.m <= qG + qH)=> //; proc.
  call (_: valid_keys ks /\
           Hmap.m{hr} = FMap.empty /\
           !H2.bad{hr} /\
           G.m{hr} = FMap.empty ==>
           H2.bad /\
           size Hmap.m <= qH + qS /\
           size G.m <= qG + qH).
    by bypr=> &m' [vkeys [Hm_emp [nbad Gm_emp]]]; apply (GAdv1_GAdv2_BAD &m' qG qH qS ks{m'} _ _ _ _).
  call (_: true ==> Hmap.m = FMap.empty /\ !H2.bad);
    first by proc; wp; call (_: true ==> Hmap.m = FMap.empty)=> //; proc; wp.
  call (_: true ==> G.m = FMap.empty);
    first by proc; wp.
  by rnd.
  qed.

  (** G3: upto "H is called by the signature oracle on a message * salt pair that has
                previously been queried directly by the adversary" *)
  local module H3: SplitOracle = {
    var bad:bool

    proc init(ks:pkey*skey): unit = {
      Hmap.init(ks);
      bad = false;
    }

    proc o(c:bool,x:message * salt): htag = {
      var w:htag;
      var st:gtag;

      if (!in_dom x Hmap.m) {
        w = $sample_htag;
        st = $sample_gtag;
        Hmap.m.[x] = (w,c,Signature.ones);
        G.m.[w] = st ^ (GTag.from_bits (to_bits (snd x) || zeros (kg - k0)));
      } else {
        if (!c /\ pi3_2 (oget Hmap.m.[x])) {
          bad = true;
          Hmap.m.[x] = (HTag.zeros,c,Signature.ones);
        }
      }
      return pi3_1 (oget Hmap.m.[x]);
    }
  }.

  local module G3 = Gen(GAdv, H3, G).

  (** Proofs *)
  local equiv G2_G3_H:
    H2.o ~ H3.o:
      !H3.bad{2} /\ ={glob Hmap, glob G, c, x} ==>
      !H3.bad{2} => ={glob Hmap, glob G, res}.
  proof strict.
  proc; sp; if=> //.
    by wp; do !rnd.
    by wp.
  qed.

  local lemma G2_G3_abstract (Ga <: Gadv {H2,H3,G,Hmem}):
    (forall (H <: SplitOracle{Ga}) (G <: Gt.Types.ARO{Ga}),
       islossless H.o => islossless G.o => islossless Ga(H,G).main) => 
    equiv [Gen(Ga,H2,G).main ~ Gen(Ga,H3,G).main: true ==> !H3.bad{2} => ={res}].
  proof strict.
  intros=> GaL; proc.
  call (_: H3.bad, ={glob Hmap, glob G}).
    (* H *)
    by conseq* G2_G3_H=> //; smt.
    by intros=> &2 _; conseq* (_: true ==> true)=> //;
       proc; if=> //; wp; do !rnd True; skip; smt.
    by intros=> _; proc; if=> //; wp; try (do !rnd True); skip; smt.
    (* G *)
    by conseq* Gt.Lazy.abstract_o.
    by intros _ _; conseq* (Gt.Lazy.lossless_o _); apply s_gtagL.
    by intros _; conseq* (Gt.Lazy.lossless_o _); apply  s_gtagL.
  call (_: ={ks} /\ valid_keys ks{2} ==> ={glob Hmap} /\ !H3.bad{2});
    first by proc; wp; call Hmap_init.
  call (_: true ==> ={glob G});
    first by sim.
  by rnd; skip; smt.
  qed.

  local equiv G2_G3: Gen(GAdv,H2,G).main ~ Gen(GAdv,H3,G).main : true ==> !H3.bad{2} => ={res}.
  proof strict.
  by apply (G2_G3_abstract GAdv _); apply GAdvL.
  qed.

  (** TODO: Bound the probability of bad in G3 *)
  local lemma G2_G3_BAD &m (qH qS:int):
    0 < qH => 0 < qS =>
    Pr[ G3.main() @ &m:
          H3.bad /\
          size Hmap.m <= qH + qS ] <=
      (qH * (qH + qS))%r / (2^k0)%r. (* Number of direct adversary queries times number of queries
                                        over size of the input space (randomness only) *)
  proof strict.
    
  admit.
  qed.

  (** G4: compute z and u from the sampled values
        Note: z is uniform in "bitstrings of length k starting with a zero bit" (denoted '0 || 2^k-1'), and
              u is uniform in f^-1(0 || 2^k-1) *)
  module type Sample_w_st = {
    proc * sample(i:pkey) : htag * gtag
  }.

  local module GenH4 (S:Sample_w_st) : SplitOracle = {
     proc init(ks:pkey * skey): unit = {
      Hmap.init(ks);
    }

    proc o(c:bool,x:message * salt): htag = {
      var w:htag;
      var st:gtag;
      var z, u:signature;

      if (!in_dom x Hmap.m)
      {
        (w,st) = S.sample(Hmem.pk);
        z = Signature.from_bits (zeros 1 || to_bits w || to_bits st);
        u = if c then ((inv Hmem.xstar Hmem.pk) * finv Hmem.sk  z) Hmem.pk else finv Hmem.sk z;
        Hmap.m.[x] = (w,c,u);
        G.m.[w] = st ^ (GTag.from_bits (to_bits (snd x) || zeros (kg - k0)));
      }
      else
      {
        if (!c /\ pi3_2 (oget Hmap.m.[x])) Hmap.m.[x] = (HTag.zeros,c,Signature.ones);
      }
      return pi3_1 (oget Hmap.m.[x]);
    }
  }.  

  local module S2 = { 
    proc sample (i:pkey) : htag * gtag = {
      var w:htag;
      var st:gtag;
      w = $sample_htag;
      st = $sample_gtag;
      return (w,st);
    }
  }.
 
  local module H4 = GenH4(S2).

  local module G4 = Gen(GAdv,H4,G).

  local equiv G3_G4_H: H3.o ~ H4.o:
    ={glob Hmem, glob G, c, x} /\
    dom Hmap.m{1} = dom Hmap.m{2} /\
    (forall x, in_dom x Hmap.m{1} =>
       pi3_1 (oget Hmap.m.[x]{1}) = pi3_1 (oget Hmap.m.[x]{2})) /\
    (forall x, in_dom x Hmap.m{1} =>
       pi3_2 (oget Hmap.m.[x]{1}) = pi3_2 (oget Hmap.m.[x]{2})) ==>
    ={glob Hmem, glob G, res} /\
    dom Hmap.m{1} = dom Hmap.m{2} /\
    (forall x, in_dom x Hmap.m{1} =>
       pi3_1 (oget Hmap.m.[x]{1}) = pi3_1 (oget Hmap.m.[x]{2})) /\
    (forall x, in_dom x Hmap.m{1} =>
       pi3_2 (oget Hmap.m.[x]{1}) = pi3_2 (oget Hmap.m.[x]{2})).
  proof strict.
  proc; if; first smt.
    seq 2 3: (={glob Hmem, glob G, c, x, w, st} /\
              dom Hmap.m{1} = dom Hmap.m{2} /\
              (forall x, in_dom x Hmap.m{1} =>
                pi3_1 (oget Hmap.m.[x]{1}) = pi3_1 (oget Hmap.m.[x]{2})) /\
              (forall x, in_dom x Hmap.m{1} =>
                pi3_2 (oget Hmap.m.[x]{1}) = pi3_2 (oget Hmap.m.[x]{2}))).
      by inline S2.sample;wp; do !rnd;wp.
    seq 1 1: (={glob Hmem, glob G, c, x, w, st} /\
              dom Hmap.m{1} = dom Hmap.m{2} /\
              (forall x, in_dom x Hmap.m{1} =>
                pi3_1 (oget Hmap.m.[x]{1}) = pi3_1 (oget Hmap.m.[x]{2})) /\
              (forall x, in_dom x Hmap.m{1} =>
                pi3_2 (oget Hmap.m.[x]{1}) = pi3_2 (oget Hmap.m.[x]{2}))).
      wp; skip; progress=> //; first smt.
       case ((x = x0){2}); first smt.
       by intros=> x_x0; do 2!rewrite ?get_set_neq //; smt.
       case ((x = x0){2}); first by intros=> x_x0; subst; rewrite !get_set_eq.
       by intros=> x_x0; do 2!rewrite ?get_set_neq //; smt.
    by wp; skip; progress=> //; smt.

    if; [smt | | ]; wp; skip; progress=> //; first 2 last; last 3 smt.
      by case ((x = x0){2}); [| intros=> x_x0; do 2!rewrite ?get_set_neq //]; smt.
      by case ((x = x0){2}); [| intros=> x_x0; do 2!rewrite ?get_set_neq //]; smt.
  qed.

  local equiv G3_G4_abstract (Ga <: Gadv {H2,H3,G,Hmem}):
    Gen(Ga,H3,G).main ~ Gen(Ga,H4,G).main: true ==> ={res}.
  proof strict.
  proc; call (_: ={glob Hmem, glob G} /\
                 dom Hmap.m{1} = dom Hmap.m{2} /\
                 (forall x, in_dom x Hmap.m{1} =>
                   pi3_1 (oget Hmap.m.[x]{1}) = pi3_1 (oget Hmap.m.[x]{2})) /\
                 (forall x, in_dom x Hmap.m{1} =>
                   pi3_2 (oget Hmap.m.[x]{1}) = pi3_2 (oget Hmap.m.[x]{2}))).
    (* H *)
    by conseq* G3_G4_H. 
    (* G *)
    by conseq* Gt.Lazy.abstract_o.
  call (_: ={ks} /\ valid_keys ks{1} ==> ={glob Hmap});
    first by proc; wp; call Hmap_init.
  call Gt.Lazy.abstract_init.
  by rnd.
  qed.

  local equiv G3_G4: G3.main ~ G4.main: true ==> ={res}
  by apply (G3_G4_abstract GAdv).

  (** G4': Sampling z in a loop *)
  local module Sw = {
    proc sample(i:pkey):htag * gtag = {
      var z:signature;
      var w:htag;
      var st:gtag;
      z = Signature.from_bits(ones 1 || to_bits HTag.zeros || to_bits GTag.zeros);
      z = S.RsampleW.sample(i,z);
      w = HTag.from_bits (sub (to_bits z) 1 k1);
      st = GTag.from_bits (sub (to_bits z) (k1 + 1) kg); 
      return (w,st);
    }
  }.

  local equiv S2_Sw : S2.sample ~ Sw.sample : ={i} /\ S.valid i{1} ==> ={res}.
  proof.
  transitivity S.Sample.sample (={i} /\ S.valid i{1} ==> ={res}) (={i} /\ S.valid i{1} ==> ={res}) => //.
    by intros &m1 &m2 [-> valid];exists i{m2}.
    bypr (res{1}) (res{2})=> // &1 &2 x [Heqi Hvalid].
    rewrite (_:Pr[S2.sample(i{1}) @ &1 : x = res] = 1%r/(2^(k1+kg))%r).
      byphoare (_: true ==> x = res) => //; proc.
        seq 1: ((fst x) = w) (1%r/(2^k1)%r) (1%r/(2^kg)%r) _ 0%r => //.
          rnd; skip; progress=> //.
          by rewrite (mu_eq _ _ ((=) (fst x))) => //;apply (HTag.Dword.mu_x_def (fst x)).
          conseq * (_ : _ ==> snd x = st).
            by progress; elim/tuple2_ind x.
          rnd;skip;progress => //.
          by rewrite (mu_eq _ _ ((=) (snd x))) => //;apply (GTag.Dword.mu_x_def (snd x)).
          by hoare;rnd;skip;smt.
        progress=> //; cut <-: (2 ^ k1) * (2 ^ kg) = 2 ^ (k1 + kg); smt.
      rewrite eq_sym. byphoare (_: S.valid i ==> x = res) => //; last smt. proc.
      rnd;skip;progress => //.
      rewrite (_ : mu (sample_htag * sample_gtag) (fun (x0 : htag * gtag), x = x0) =
                    mu_x (sample_htag * sample_gtag) x).
        by rewrite /mu_x;apply mu_eq.
      rewrite Dprod.mu_x_def /sample_htag HTag.Dword.mu_x_def /sample_gtag GTag.Dword.mu_x_def. 
      by progress=> //; cut <-: (2 ^ k1) * (2 ^ kg) = 2 ^ (k1 + kg); smt.
    proc*; inline{2} Sw.sample; wp.
    pose f:= fun (p:htag * gtag), 
       Signature.from_bits (zeros 1 || to_bits (fst p) || to_bits (snd p)).
    pose finv := fun (z:signature), (HTag.from_bits (sub (to_bits z) 1 k1),
       GTag.from_bits (sub (to_bits z) (k1 + 1) kg)).
    call (S.Sample_RsampleW f finv);wp;skip;progress => //.
      rewrite /lsb0 Signature.pcan_to_from; first smt.
      rewrite -{2}(length_ones 1); first smt.
      by rewrite sub_app_fst; rewrite eq_sym; apply zeros_ones; smt.
      smt.
      by rewrite /lsb0 /f Signature.pcan_to_from; smt.
      by rewrite Dprod.supp_def; smt.
      rewrite /f /finv /fst /snd /=; cut:= H0; rewrite /lsb0=> <-.
      rewrite HTag.pcan_to_from; first smt.
      rewrite GTag.pcan_to_from; first smt.
      rewrite {2}(_: 1 = 0 + 1) //; pose x:= to_bits rR.
      rewrite -appA sub_app_sub //; first 2 smt.
      rewrite (_: k1 + 1 = 0 + (1 + k1)); first smt.
      by rewrite sub_app_sub //;smt.
    rewrite /finv /f Signature.pcan_to_from;first smt.
    generalize H0; elim/tuple2_ind rL => H0 l r _;simplify fst snd.
    rewrite sub_app_snd_le length_zeros //=.
    cut Hl : `|to_bits l| = k1 by smt.
    rewrite sub_app_fst_le - ?Hl //;first smt.
    rewrite sub_full HTag.can_from_to.
    rewrite -appA sub_app_snd_le;first smt.
    rewrite (_:(`|to_bits l| + 1 - `|zeros 1 || to_bits l| ) = 0);first smt.
    by rewrite (_:kg = `|to_bits r| );smt.
  qed.
           
  local module H4' = GenH4 (Sw).
  local module G4' = Gen(GAdv,H4',G).  

  local equiv G4_G4'_H: H4.o ~ H4'.o: ={glob Hmap, c, x} /\ S.valid Hmem.pk{1} ==> ={glob Hmap, res}.
  proof.
    proc; if=> //; last by wp.
    seq 1 1: (={glob Hmap, c, x, w, st} /\ !in_dom x{1} Hmap.m{1});
      first by call S2_Sw.
    sim.
  qed.

  (** G5: Sampling z in a (non-PTIME) loop *)
  local module H5: SplitOracle = {
    proc init(ks:pkey * skey): unit = {
      Hmap.init(ks);
    }

    proc o(c:bool,x:message * salt): htag = {
      var b:bool;
      var w:htag;
      var st:gtag;
      var z, u:signature;
      var i:int;

      i = 0;
      b = true;
      if (!in_dom x Hmap.m)
      {
        while (b)
        {
          z = $sample_plain Hmem.pk;
          b = ((sub (to_bits z) 0 1) <> zeros 1);
          w = HTag.from_bits (sub (to_bits z) 1 k1);
          st = GTag.from_bits (sub (to_bits z) (k1 + 1) kg);
          u = if c then ((inv Hmem.xstar Hmem.pk) * finv Hmem.sk  z) Hmem.pk else finv Hmem.sk z;
          if (!b)
          {
            Hmap.m.[x] = (w,c,u);
            G.m.[w] = st ^ (GTag.from_bits (to_bits (snd x) || zeros (kg - k0)));
          }
          i = i + 1;
        }
      }
      else
      {
        if (!c /\ pi3_2 (oget Hmap.m.[x])) Hmap.m.[x] = (HTag.zeros,c,Signature.ones);
      }
      return pi3_1 (oget Hmap.m.[x]);
    }
  }.

  local module G5 = Gen(GAdv,H5,G).

  local equiv G4'_G5_H: H4'.o ~ H5.o: ={glob Hmap, glob G, c, x} ==> ={glob Hmap, glob G, res}.
  proof strict.
  proc; sp; if=> //; last by wp.
  inline{1} Sw.sample S.RsampleW.sample;sp;wp; intros => /=.
  while (={glob Hmem,x,c} /\ i0{1} = Hmem.pk{2} /\
         b{2} = !(lsb0 i0 r){1} /\
         if b{2}
         then ={Hmap.m, G.m} 
         else Hmap.m{2} = 
               Hmap.m{1}.[x{1} <-
                  ((HTag.from_bits (sub (to_bits r{1}) 1 k1))%HTag
                   ,c{1}
                   ,if c{1}
                    then ( * ) (inv Hmem.xstar{1} Hmem.pk{1})
                               (finv Hmem.sk{1}
                                  ((Signature.from_bits
                                      (zeros 1 ||
                                       to_bits ((HTag.from_bits (sub (to_bits r{1}) 1 k1)))%HTag ||
                                       to_bits
                                         ((GTag.from_bits (sub (to_bits r{1}) (k1 + 1) kg)))%GTag)))%Signature)
                               Hmem.pk{1}
                    else finv Hmem.sk{1}
                              ((Signature.from_bits
                                  (zeros 1 ||
                                   to_bits ((HTag.from_bits (sub (to_bits r{1}) 1 k1)))%HTag ||
                                   to_bits
                                     ((GTag.from_bits (sub (to_bits r{1}) (k1 + 1) kg)))%GTag)))%Signature)] /\
        Lazy.RO.m{2} =
         Lazy.RO.m{1}.[(HTag.from_bits (sub (to_bits r{1}) 1 k1))%HTag <-
          (GTag.from_bits (sub (to_bits r{1}) (k1 + 1) kg))%GTag ^
          (GTag.from_bits (to_bits (snd x{1}) || zeros (kg - k0)))%GTag]).
     wp;rnd;skip.
     intros &1 &2 [H1 [H2 H3]]; generalize H2 H1 => /=.
     rewrite H3 /lsb0;progress => //.
     rewrite HTag.pcan_to_from;first smt.
     rewrite GTag.pcan_to_from;first smt.
     rewrite -H5.
     rewrite (_: 
       (sub (to_bits rL) 0 1 || sub (to_bits rL) 1 k1 || sub (to_bits rL) (k1 + 1) kg )=
        to_bits rL).
       rewrite (_ : k1 + 1 = 1 + k1);first smt.
       rewrite sub_app_sub //; first 3 smt.
       by rewrite {2}(_: 1 = 0 + 1) // sub_app_sub //;smt.
     by rewrite Signature.can_from_to //.
  skip;progress => //.
    rewrite /lsb0 Signature.pcan_to_from;first smt.
    rewrite sub_app_fst_le //;first smt.
    rewrite eq_sym eqT.
    by rewrite -{2} (length_ones 1) // sub_full // (eq_sym (ones 1));apply zeros_ones.
    smt.
    smt.
    smt.
  qed.

  local lemma G4'_G5_abstract (Ga <: Gadv {H4',H5,G,Hmem}):
    (forall (H <: SplitOracle{Ga}) (G <: Gt.Types.ARO{Ga}),
       islossless H.o => islossless G.o => islossless Ga(H,G).main) => 
    equiv [Gen(Ga,H4',G).main ~ Gen(Ga,H5,G).main: true ==> ={res}].
  proof strict.
  intros=> GaL; proc.
  call (_: ={glob Hmap, glob G}).
    (* H *)
    by conseq* G4'_G5_H.
    (* G *)
    by conseq* Gt.Lazy.abstract_o.
  call (_: ={ks} /\ valid_keys ks{1} ==> ={glob Hmap});
    first by proc; call Hmap_init.
  call Gt.Lazy.abstract_init.
  by rnd.
  qed.
 
  local equiv G4'_G5_equiv: G4'.main ~ G5.main: true ==> ={res}
  by (apply (G4'_G5_abstract GAdv); apply GAdvL).

  (** G6: upto "k2 executions of the loop didn't sample a bitstring starting with 0" *)
  local module H6: SplitOracle = {
    var bad:bool

    proc init(ks:pkey * skey): unit = {
      Hmap.init(ks);
      bad = false;
    }

    proc o(c:bool,x:message * salt): htag = {
      var b:bool;
      var w:htag;
      var st:gtag;
      var z, u:signature;
      var i:int;

      i = 0;
      b = true;
      if (!in_dom x Hmap.m)
      {
        while (b /\ i < kg2)
        {
          z = $sample_plain Hmem.pk;
          b = ((sub (to_bits z) 0 1) <> zeros 1);
          w = HTag.from_bits (sub (to_bits z) 1 k1);
          st = GTag.from_bits (sub (to_bits z) (k1 + 1) kg);
          u = if c then ((inv Hmem.xstar Hmem.pk) * finv Hmem.sk  z) Hmem.pk else finv Hmem.sk z;
          if (!b)
          {
            Hmap.m.[x] = (w,c,u);
            G.m.[w] = st ^ (GTag.from_bits (to_bits (snd x) || zeros (kg - k0)));
          }
          i = i + 1;
        }
        bad = bad \/ b;
      }
      else
      {
        if (!c /\ pi3_2 (oget Hmap.m.[x])) Hmap.m.[x] = (HTag.zeros,c,Signature.ones);
      }
      return pi3_1 (oget Hmap.m.[x]);
    }
  }.

  local module G6 = Gen(GAdv,H6,G).

  local lemma G5_G6_abstract (Ga <: Gadv {H5,H6,G,Hmem}):
    (forall (H <: SplitOracle{Ga}) (G <: Gt.Types.ARO{Ga}),
       islossless H.o => islossless G.o => islossless Ga(H,G).main) => 
    equiv [Gen(Ga,H5,G).main ~ Gen(Ga,H6,G).main: true ==> !H6.bad{2} => ={res}].
  proof strict.
  intros=> GaL; proc.
  call (_: H6.bad, ={glob Hmap, glob G} /\ valid_pkey Hmem.pk{1}, ={Hmem.pk} /\ valid_pkey Hmem.pk{1}).
    (* H *)
    proc; sp; if=> //.
      splitwhile (i < kg2): {1} 1.
      seq 1 1: (={b, i, c, x, w, st, z, u, glob Hmap, glob G} /\ valid_pkey Hmem.pk{1} /\ !H6.bad{2}).
        while (={b, i, c, x, glob Hmap, glob G} /\ 0 <= i{1} /\ (i{1} > 0 => ={z, w, st, u}) /\ (i{1} = 0 => b{1})).
          seq 5 5: (={b, i, c, x, w, st, z, u, glob Hmap, glob G} /\ 0 <= i{1}).
            by wp; rnd; skip; progress=> //; smt.
            by if=> //; wp; skip; smt.
        by skip; progress=> //; smt.
      case (b{1}).
        seq 0 1: (={Hmem.pk} /\ H6.bad{2} /\ valid_pkey Hmem.pk{2}); first by wp; skip; progress=> //; right.
          conseq* (_: _ ==> true); first by progress=> //; smt.
          conseq (_: _ ==> true) (_: valid_pkey Hmem.pk ==> true: =1%r)=> //.
    (* NOTE: 1/2 is not correct! *)
          while (valid_pkey Hmem.pk) (if b then 1 else 0) 1 (1%r/2%r) => //; first smt.
            intros=> Hw.
            seq 7: (valid_pkey Hmem.pk) 1%r 1%r 0%r _ => //.
              by wp => /=; rnd; skip; progress; smt.
              by hoare; wp; rnd.
              by wp => /=; rnd; skip; progress; smt.
              split; first smt.
              intros z0; conseq * (_: true ==> !b) => //;first smt.
              wp=> /=; rnd; skip; progress=> //. admit. (* We need some concrete facts about words of length 1 *)
        by rcondf{1} 1=> //; wp.
      by if=> //; wp.
    intros=> &2 _; proc. 
    seq 2 : (Hmem.pk = Hmem.pk{2} /\ valid_pkey Hmem.pk) => //.
      by wp => //.
    if;[ | wp => //].
    while (valid_pkey Hmem.pk) (if b then 1 else 0) 1 (1%r/2%r) => //;first smt.
      intros Hw.
      seq 7 : (valid_pkey Hmem.pk) => //.
      by wp => /=;rnd;skip;smt.
      by hoare; wp; rnd.
      by wp => /=;rnd;skip;smt.
      split; first smt.
      intros z0; conseq * (_: true ==> !b) => //;first by smt.
      wp=> /=. 
      rnd;skip;progress => //.
      by admit. (* same as above. *)
    by hoare; wp.
    intros=> &1; proc; sp; if.
      wp; while (valid_pkey Hmem.pk) (kg2 - i);
        first by intros=> _; wp; rnd True; skip; smt.
      by skip; smt.
    by wp.
    (* G *)
    by conseq* Gt.Lazy.abstract_o.
    by intros=> _ _; conseq* (Gt.Lazy.lossless_o _); apply s_gtagL.
    by intros=> _; conseq* (Gt.Lazy.lossless_o _); apply s_gtagL.
  call (_: ={ks} /\ valid_keys ks{1} ==> ={glob Hmap} /\ valid_pkey Hmem.pk{1});
    first by proc; wp; call Hmap_init; skip; smt.
  call Gt.Lazy.abstract_init.
  by rnd; skip; smt.
  qed.

  local equiv G5_G6_equiv: G5.main ~ G6.main: true ==> !H6.bad{2} => ={res}
  by (apply (G5_G6_abstract GAdv); apply GAdvL).

  (* TODO: bound the probability of bad in G6 *)
  local lemma G5_G6_BAD &m qH:
    0 < qH =>
    Pr[ G6.main() @ &m: H6.bad ] <= qH%r / (2^kg2)%r.
  proof strict.
  admit. (* I bleieve we are still missing a tactic for this? *)
  qed.

  (** G7: No longer using sk to simulate the oracles *)
  local module H7: SplitOracle = {
    proc init(ks:pkey * skey): unit = {
      Hmap.init(ks);
    }

    proc o(c:bool,x:message * salt): htag = {
      var b:bool;
      var w:htag;
      var st:gtag;
      var z, u:signature;
      var i:int;

      i = 0;
      b = true;
      if (!in_dom x Hmap.m)
      {
        while (b /\ i < kg2)
        {
          u = $sample_plain Hmem.pk;
          z = if c then (f Hmem.pk Hmem.xstar * f Hmem.pk u) Hmem.pk else f Hmem.pk u;
          b = (sub (to_bits z) 0 1 <> zeros 1);
          w = HTag.from_bits (sub (to_bits z) 1 k1);
          st = GTag.from_bits (sub (to_bits z) (k1 + 1) (kg));
          if (!b)
          {
            Hmap.m.[x] = (w,c,u);
            G.m.[w] = st ^ (GTag.from_bits (to_bits (snd x) || zeros (kg - k0)));
          }
          i = i + 1;
        }
      }
      else
      {
        if (!c /\ pi3_2 (oget Hmap.m.[x])) Hmap.m.[x] = (HTag.zeros,c,Signature.ones);
      }
      return pi3_1 (oget Hmap.m.[x]);
    }
  }.

  local module G7 = Gen(GAdv,H7,G).

  local lemma G6_G7_abstract (Ga <: Gadv {H5,H6,G,Hmem}):
    (forall (H <: SplitOracle{Ga}) (G <: Gt.Types.ARO{Ga}),
       islossless H.o => islossless G.o => islossless Ga(H,G).main) => 
    equiv [Gen(Ga,H6,G).main ~ Gen(Ga,H7,G).main: true ==> Hmem.xstar{2} <> Signature.zeros => ={res}].
  proof strict.
  intros=> GaL; proc.
  call (_: Hmem.xstar = Signature.zeros,
             ={glob Hmap, glob G} /\
             valid_keys (Hmem.pk,Hmem.sk){2} /\
             in_supp Hmem.xstar{2} (sample_plain Hmem.pk{2}),
             ={Hmem.pk} /\ valid_pkey Hmem.pk{1}).
    (* H *)
    proc; sp; if=> //.
      wp; while (={x, c, b, i, glob Hmap, glob G} /\
                 valid_keys (Hmem.pk,Hmem.sk){2} /\ 
                 in_supp Hmem.xstar{2} (sample_plain Hmem.pk{2}) /\
                 Hmem.xstar{2} <> Signature.zeros).
        case (c{2}).
          wp; rnd (fun z, ((inv Hmem.xstar Hmem.pk) * finv Hmem.sk z) Hmem.pk){2}
                  (fun u, ((f Hmem.pk Hmem.xstar) * f Hmem.pk u) Hmem.pk){2};
          skip; progress => //; last 4 smt.
            apply (challengeU Hmem.pk{2} _ _ _ _ _)=> //; first smt.
            by rewrite -/(support _ _); apply mulIn; smt.
            by rewrite -/(support _ _); apply mulIn; rewrite -/(f_dom _ _) f_dom_rng; smt.
            rewrite homo_f_mul; first 2 smt.
            rewrite -mulA -homo_f_mul; first 2 smt.
            by rewrite mul_inv ?fofinv 1?mulC ?mul1 //; smt.
            by rewrite homo_finv_mul; try (rewrite -/(f_dom _ _) f_dom_rng); smt.

          wp; rnd (fun z, finv Hmem.sk z){2} (fun u, f Hmem.pk u){2};
          skip; progress=> //; last 6 by try (case (c{2})); smt.
            by apply (challengeU Hmem.pk{2} _ _ _ _)=> //; smt.
            by rewrite -/(support _ _) -/(f_dom _ _) f_dom_rng; smt.
        by skip; smt.
      if=> //; by wp; skip; smt.
    by intros=> &2 xstar_n0; proc; sp; if;
         [wp; while (valid_pkey Hmem.pk) (kg2 - i); [intros=> z; wp; rnd | ]; skip; smt | wp].
    by intros=> &1; proc; sp; if;
         [wp; while (valid_pkey Hmem.pk) (kg2 - i); [intros=> z; wp; rnd | ]; skip; smt | wp].

    (* G *)
    by conseq* (_: ={glob G, x} ==> ={glob G, res})=> //; [smt | sim].
    by intros=> _ _; conseq* (Gt.Lazy.lossless_o _); smt.
    by intros=> _; conseq* (Gt.Lazy.lossless_o _); smt.
  call (_: ={ks} /\
           valid_keys ks{1} ==>
           ={glob Hmap} /\
           valid_keys (Hmem.pk,Hmem.sk){2} /\
           f_dom Hmem.pk{2} Hmem.xstar{2});
    first by proc; wp; call Hmap_init.
  call Gt.Lazy.abstract_init.
  by rnd; skip; smt.
  qed.

  local equiv G6_G7_equiv: G6.main ~ G7.main: true ==> Hmem.xstar{2} <> Signature.zeros => ={res}
  by (apply (G6_G7_abstract GAdv); apply GAdvL).


  (** Proof Note: no abstraction possible here because of a problem with H7 not initializing G's state.
      Why is it not an issue in earlier steps? (In particular, the one immediately above,
      speaking of exactly the same games...) *)
  (* TODO: Benjamin: check soundness of the application of the termination result
           for GAdv in previous games where Hn (with n between 0 and 7) uses G directly
           but does not initialize it. *)
  local module Ha = GAdv(H7,G).Ha.
  local module Si  = GAdv(H7,G).S.

  local lemma G6_G7_bad &m:
    Pr[G7.main() @ &m: Hmem.xstar = Signature.zeros] <= 1%r / (2 ^ (k - 1))%r.
  proof strict.
  byphoare (_: true ==> Hmem.xstar = Signature.zeros)=> //; proc.
  seq 3: (Hmem.xstar = Signature.zeros) (1%r / (2 ^ (k - 1))%r) 1%r _ 0%r=> //.
    call (_: valid_keys ks ==> Hmem.xstar = Signature.zeros);
      first proc; call (_: valid_keys ks ==> Hmem.xstar = Signature.zeros)=> //;
              proc; wp; call (_: valid_keys ks ==> Hmem.xstar = Signature.zeros)=> //;
                proc; rnd; wp; skip; progress=> //. print axiom plain0_bnd.
                  cut:= plain0_bnd (ks.`1{hr}) _; first by rewrite /valid_pkey; exists (ks.`2{hr}); smt.
                  by rewrite /mu_x (_: (fun x, x = Signature.zeros) = ((=) Signature.zeros))=> //; apply ExtEq.fun_ext; smt.
      call (_: true)=> //.
      by rnd.

    by hoare; call (_: true).
  qed.

  (** Reduction to OW: no longer using xstar to simulate the oracles *)
  local module I: Inverter = {
    var ystar:signature
    var pk:pkey

    module H = {
      var m:(message * salt,htag * bool * signature) map

      proc init(): unit = { m = FMap.empty; }

      proc o(c:bool,x:message * salt): htag = {
        var b:bool = true;
        var i:int = 0;
        var w:htag;
        var st:gtag;
        var z, u:signature;

        if (!in_dom x m)
        {
          while (b /\ i < kg2)
          {
            u = $sample_plain I.pk;
            z = if c then (ystar * f pk u) pk else f pk u;
            b = (sub (to_bits z) 0 1 <> zeros 1);
            w = HTag.from_bits (sub (to_bits z) 1 k1);
            st = GTag.from_bits (sub (to_bits z) (k1 + 1) (kg));
            if (!b)
            {
              m.[x] = (w,c,u);
              G.m.[w] = st ^ (GTag.from_bits (to_bits (snd x) || zeros (kg - k0)));
            }
            i = i + 1;
          }
        }
        else
        {
          if (!c /\ pi3_2 (oget I.H.m.[x])) m.[x] = (HTag.zeros,c,Signature.ones);
        }
        return pi3_1 (oget m.[x]);
      }
    }

    module Ha = {
      proc o(x:message * salt): htag = {
        var r:htag;
        r = H.o(true,x);
        return r;
      }
    }

    module IOracles = {
      var qs:message set

      proc sign(m:message): signature = {
        var r:salt;
        var w:htag;
        r = $sample_salt;
        w = H.o(false,(m,r));
        return pi3_3 (oget H.m.[(m,r)]);
      }
    }

    module A = A(G,Ha,IOracles)

    proc invert(pk:pkey,y:signature): signature = {
      var m:message;
      var s:signature;

      IOracles.qs = FSet.empty;
      I.pk = pk;
      ystar = y;
      (m,s) = A.forge(pk);

      return if !mem m IOracles.qs then s else Signature.zeros;
    }
  }.

  (** PROOF NOTE.
      The invariant below is insufficient. We need to know, at least:
        - forall m r w u,
            H.m.[m,r] = Some (w,false,u) =>
            w = sub (f pk u) 1 k1 /\
            G.m.[w] = Some (sub (f pk u) (k1 = 1) kg) ^ (r || zeros)
          (Note that this is currently not true when H is called directly,
           then by the signing oracle... This requires a bit of thought.)
        - forall m r w u,
            H.m.[m,r] = Some (w,true,u) =>
            w = sub ((f pk xstar) * (f pk u) [pk]) 1 k1 /\
            G.m.[w] = Some (sub ((f pk xstar) * (f pk u) [pk]) (k1 = 1) kg) ^ (r || zeros)
       There may also still be an upto bad step missing, that deals with the case where
       the adversary gets lucky and gets a valid signature out of fresh queries to H and G. *)
  local equiv G7_OW_H: H7.o ~ I.H.o:
    ={glob G, x, c} /\
    Hmap.m{1} = I.H.m{2} /\
    Hmem.pk{1} = I.pk{2} /\
    (f Hmem.pk Hmem.xstar){1} = I.ystar{2} ==>
    ={glob G, res} /\
    Hmap.m{1} = I.H.m{2} /\
    Hmem.pk{1} = I.pk{2} /\
    (f Hmem.pk Hmem.xstar){1} = I.ystar{2}.
  proof strict.
  proc; inline H7.o I.H.o; wp; sp; if=> //.
    wp; while (={glob G, i, b, c, x} /\
               Hmap.m{1} = I.H.m{2} /\
               Hmem.pk{1} = I.pk{2} /\
               (f Hmem.pk Hmem.xstar){1} = I.ystar{2})=> //.
          by wp; rnd; skip; smt.
    by if=> //; wp.
  qed.
end section.