require import int.

module G = {
  fun f(x : int, y : int) : int = {
    return x + y;
  }
}.

lemma L : equiv[f @ G ~ f @ G : (x{1} = y{1}) ==> (0 = x{1} + y{1})].