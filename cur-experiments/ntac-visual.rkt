#lang cur
(require
 cur/ntac/base
 cur/ntac/standard
 cur/ntac/focus-tree
 cur/stdlib/nat)

#;(ntac Nat
      display-focus-tree
      (fill (exact #'4))
      display-focus-tree)

(ntac (Π (x : Type) (n : x) x)
      display-focus-tree
      (by-intros x n)
      display-focus-tree
      (by-assumption)
      display-focus-tree)