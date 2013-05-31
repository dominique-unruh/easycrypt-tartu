require Logic.
require import Int.
require import Real.

module M1 = { 
  fun f () : int * int= {
    var x : int;
    var y : int;
    x = 1;
    y = 10;
    while (x <> y) {
      x = x + 1;
    }
    return (x,y);
  }
}.

lemma test1 : bd_hoare [M1.f : true ==> true] [=] [1%r]
proof.
  fun.
  while (x<=y) (y-x).
  intros z.
  wp; skip; trivial.
  wp; skip; trivial.
save.


