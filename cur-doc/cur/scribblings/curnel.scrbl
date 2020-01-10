#lang scribble/manual

@(require
  "defs.rkt"
  (for-label (only-meta-in 0 cur))
  scribble/eval)

@title{Curnel Forms}
@;@defmodule[cur]
@deftech{Curnel forms} are the core forms provided @racketmodname[cur].
These forms come directly from the trusted core and are all that remain after macro expansion.
@todo{Link to guide regarding macro expansion}
The core of @racketmodname[cur] is essentially TT with an impredicative universe @racket[(Type 0)].
For a very understandable in-depth look at TT, see chapter 2 of
@hyperlink["https://eb.host.cs.st-andrews.ac.uk/writings/thesis.pdf"
           "Practical Implementation of a Dependently Typed Functional Programming Language"], by
Edwin C. Brady.

@(define curnel-eval (curnel-sandbox ""))

@defform[(Type n)]{
Define the universe of types at level @racket[n], where @racket[n] is any natural number.
Cur is impredicative in @racket[(Type 0)], although this is likely to change to
a more restricted impredicative universe.

@examples[#:eval curnel-eval
          (Type 0)
          (Type 1)]

@history[#:changed "0.20" @elem{Removed @racket[Type] synonym from Curnel; changed run-time representation from symbolic @racket['(Unv n)] to transparent struct.}]
}

@defform[(λ (id : type-expr) body-expr)]{
Produces a single-arity procedure, binding the identifier @racket[id] of type
@racket[type-expr] in @racket[body-expr] and in the type of @racket[body-expr].
Both @racket[type-expr] and @racket[body-expr] can contain non-curnel forms,
such as macros.

Currently, Cur will return the underlying representation of a procedure when a
@racket[λ] is evaluated at the top-level.
Do not rely on this representation.

@examples[#:eval curnel-eval
          (λ (x : (Type 0)) x)
          (λ (x : (Type 0)) (λ (y : x) y))]

@history[#:changed "0.20" @elem{Changed run-time representation from symbolic @racket['(λ (x : t) e)] to Racket procedure}]
}

@defform[(#%app procedure argument)]{
Applies the single-arity @racket[procedure] to @racket[argument].

@examples[#:eval curnel-eval
          ((λ (x : (Type 1)) x) (Type 0))
          (#%app (λ (x : (Type 1)) x) (Type 0))]
}

@defform[(Π (id : type-expr) body-expr)]{
Produces a dependent function type, binding the identifier @racket[id] of type
@racket[type-expr] in @racket[body-expr].


@examples[#:eval curnel-eval
          (Π (x : (Type 0)) (Type 0))
          (λ (x : (Π (x : (Type 1)) (Type 0)))
            (x (Type 0)))]

@history[#:changed "0.20" @elem{Changed run-time representation from symbolic @racket['(Π (x : t) e)] to a transparent struct.}]
}

@defform[(data id : nat type-expr (id* : type-expr*) ...)]{
Defines an inductive datatype named @racket[id] of type @racket[type-expr]
whose first @racket[nat] arguments are parameters, with constructors
@racket[id*] each with the corresponding type @racket[type-expr*].

@examples[#:eval curnel-eval
          (data Bool : 0 (Type 0)
                (true : Bool)
                (false : Bool))
          ((λ (x : Bool) x) true)
          (data False : 0 (Type 0))
          (data And : 2 (Π (A : (Type 0)) (Π (B : (Type 0)) (Type 0)))
            (conj : (Π (A : (Type 0)) (Π (B : (Type 0)) (Π (a : A) (Π (b : B) ((And A) B)))))))
          ((((conj Bool) Bool) true) false)]

@history[#:changed "0.20" "Added strict positivity checking. (or, at least, documented it)"]
}

@defform[(elim inductive-type motive (method ...) target)]{
Fold over the term @racket[target] of the inductively defined type @racket[inductive-type].
The @racket[motive] is a function that expects the indices of the inductive
type and a term of the inductive type and produces the type that this
fold returns.
The type of @racket[target] is @racket[(inductive-type index ...)].
@racket[elim] takes one method for each constructor of @racket[inductive-type].
Each @racket[method] expects the arguments for its corresponding constructor,
and the inductive hypotheses generated by recursively eliminating all recursive
arguments of the constructor.

The following example runs @racket[(sub1 (s z))].

@examples[#:eval curnel-eval
          (data Nat : 0 (Type 0)
            (z : Nat)
            (s : (Π (n : Nat) Nat)))
          (elim Nat (λ (x : Nat) Nat)
                (z
                 (λ (n : Nat) (λ (IH : Nat) n)))
                (s z))
          (elim And (λ (_ : ((And Nat) Bool)) ((And Bool) Nat))
                ((λ (n : Nat)
		  (λ (b : Bool)
		    ((((conj Bool) Nat) b) n))))
                ((((conj Nat) Bool) z) true))]

@deprecated[#:what "function" @racket[new-elim]]

}

@defform[(new-elim target motive (method ...))]{
Like @racket[elim], but makes the type annotation unnecessary.

@history[#:added "0.20"]
}

@defform[(define id expr)]{
Binds @racket[id] to the result of @racket[expr].

@examples[#:eval curnel-eval
          (data Nat : 0 (Type 0)
            (z : Nat)
            (s : (Π (n : Nat) Nat)))
          (define sub1 (λ (n : Nat)
                         (elim Nat (λ (x : Nat) Nat)
                               (z
                                (λ (n : Nat) (λ (IH : Nat) n)))
                               n)))
          (sub1 (s (s z)))
          (sub1 (s z))
          (sub1 z)]
}

@defform[(cur-axiom id : type)]{
Creates a new constant @racket[id] of type @racket[type] which has no computational content.

@history[#:added "0.20"]
}

@defform[(void)]{
A representation of nothing. Primarily used by extensions that perform side-effects but produce nothing.

@history[#:added "0.20"]
}