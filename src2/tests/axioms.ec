theory TEST.
  axiom toto : false.
(*  axiom toto : false. *)
end TEST.

theory TEST2.
  axiom toto : true.
end TEST2.  

theory ARITH.
op eq : (int,int) -> bool.
op plus : (int, int) -> int.
end ARITH.



theory TEST3.
  axiom toto : forall (x:_), ARITH.eq (ARITH.plus(x,x), 0).
end TEST3.  