#lang cur
(require cur/stdlib/sugar
         cur/stdlib/nat
         rackunit)

;; this example used to demonstrate a bug in match

(define/rec/match fact : Nat -> Nat
  [z => 1]
  [(s x) => (mult (s x) (fact x))])

;; bad version
;(: fact^ (-> Nat Nat))
#;(define (fact^ [n : Nat])
  (match n #:return Nat
    [z (s z)]
    [(s x) (mult n (fact x))]))

;; bad version is equiv to exp fn
(check-equal? (fact 2) 2) ; bad version produces 4
(check-equal? (fact 3) 6) ; bad version produces 27

;(check-equal? (fact^ 2) 2) ; bad version produces 4
;(check-equal? (fact^ 3) 6) ; bad version produces 27
