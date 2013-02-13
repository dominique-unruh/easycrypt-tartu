type t.

module type I = {
  var x : t
}.

module type J = {
  var y : t
}.

module M : I, J = {
  var x : t
  var y : t
  var z : t
}.