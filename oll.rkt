#lang s-exp "redex-curnel.rkt"
;; OLL: The OTT-Like Library
;; TODO: Add latex extraction
;; TODO: Automagically create a parser from bnf grammar
(require "sugar.rkt" "nat.rkt")

(provide define-relation define-language var avar)

(begin-for-syntax
  (define-syntax-class dash
    (pattern x:id
           #:fail-unless (regexp-match #rx"-+" (symbol->string (syntax-e #'x)))
           "Invalid dash"))

  (define-syntax-class decl (pattern (x:id (~datum :) t:id)))

  ;; TODO: Automatically infer decl ... by binding all free identifiers?
  (define-syntax-class inferrence-rule
    (pattern (d:decl ...
              x*:expr ...
              line:dash lab:id
              (name:id y* ...))
              #:with rule #'(lab : (forall* d ...
                                     (->* x* ... (name y* ...)))))))
(define-syntax (define-relation syn)
  (syntax-parse syn
    [(_ (n:id types* ...) rules:inferrence-rule ...)
     #:fail-unless (andmap (curry equal? (length (syntax->datum #'(types* ...))))
                           (map length (syntax->datum #'((rules.y* ...)
                                                          ...))))
     "Mismatch between relation declared and relation definition"
     #:fail-unless (andmap (curry equal? (syntax->datum #'n))
                           (syntax->datum #'(rules.name ...)))
     "Mismatch between relation declared name and result of inference rule"
      #`(data n : (->* types* ... Type)
          rules.rule ...)]))

(begin-for-syntax
  (require racket/syntax)
  (define (new-name name . id*)
    (apply format-id name (for/fold ([str "~a"])
                                  ([_ id*])
                          (string-append str "-~a")) name (map syntax->datum id*)))

  (define (fresh-name id)
    (datum->syntax id (gensym (syntax->datum id)))))

(module+ test
  (begin-for-syntax
    (require rackunit)
    (define (check-id-equal? v1 v2)
      (check-equal?
        (syntax->datum v1)
        (syntax->datum v2)))
    (define (check-id-match? v1 v2)
       (check-regexp-match
         v1
         (symbol->string (syntax->datum v2))))
    (check-id-match?
      #px"term\\d+"
      (fresh-name #'term))
    (check-id-equal?
      #'stlc-lambda
      (new-name #'stlc #'lambda))
    (check-id-match?
      #px"stlc-term\\d+"
      (new-name #'stlc (fresh-name #'term)))))

;; TODO: Oh, this is a mess. Rewrite it.
(begin-for-syntax
  (define lang-name (make-parameter #'name))
  (define nts (make-parameter (make-immutable-hash)))

  (define-syntax-class nt
    (pattern e:id #:fail-unless (hash-has-key? (nts) (syntax->datum #'e)) #f
             #:attr name (hash-ref (nts) (syntax->datum #'e))
             #:attr type (hash-ref (nts) (syntax->datum #'e))))

  (define (flatten-args arg arg*)
    (for/fold ([ls (syntax->list arg)])
              ([e (syntax->list arg*)])
      (append ls (syntax->list e))))

  (define-syntax-class (right-clause type)
    #;(pattern (~datum var)
             #:attr clause-context #`(#,(new-name (lang-name) #'var) :
                                      (-> #,(hash-ref (nts) 'var) #,(hash-ref (nts) type)))
             #:attr name #'var
             #:attr arg-context #'(var))
    (pattern e:nt
             #:attr clause-context #`(#,(new-name #'e.name #'->
                                                  (hash-ref (nts) type)) :
                                      (-> e.type #,(hash-ref (nts) type)))
             #:attr name (fresh-name #'e.name)
             #:attr arg-context #'(e.type))
    (pattern x:id
             #:attr clause-context #`(#,(new-name (lang-name) #'x) :
                                      #,(hash-ref (nts) type))
             #:attr name (new-name (lang-name) #'x)
             #:attr arg-context #'())
    (pattern ((~var e (right-clause type)) (~var e* (right-clause type)) ...)
             #:attr name (fresh-name #'e.name)
             #:attr clause-context #`(e.name : (->* #,@(flatten-args #'e.arg-context #'(e*.arg-context ...))
                                                    #,(hash-ref (nts) type)))
             #:attr arg-context #`(#,@(flatten-args #'e.arg-context #'(e*.arg-context ...)))))

  (define-syntax-class (right type)
    (pattern ((~var r (right-clause type)) ...)
             #:attr clause #'(r.clause-context ...)))

  #;(define-syntax-class left
    (pattern (type:id (nt*:id ...+))
             #:do ))

  (define-syntax-class nt-clauses
    (pattern ((type:id (nt*:id ...+)
              (~do (nts (for/fold ([ht (nts)])
                                  ([nt (syntax->datum #'(type nt* ...))])
                          (hash-set ht nt (new-name (lang-name) #'type)))))
              (~datum ::=)
              . (~var rhs* (right (syntax->datum #'type)))) ...)
             #:with defs (with-syntax ([(name* ...)
                                        (map (λ (x) (hash-ref (nts) x))
                                             (syntax->datum #'(type ...)))])
                           #`((data name* : Type . rhs*.clause)
                              ...)))))

;; TODO: For better error messages, add context, rename some of these patterns. e.g.
;;    (type (meta-vars) ::= ?? )
(define-syntax (define-language syn)
  (syntax-parse syn
    [(_ name:id (~do (lang-name #'name))
        (~do (nts (hash-set (make-immutable-hash) 'var #'var)))
        (~optional (~seq #:vars (x*:id ...)
           (~do (nts (for/fold ([ht (nts)])
                               ([v (syntax->datum #'(x* ...))])
                       (hash-set ht v (hash-ref ht 'var)))))))
        . clause*:nt-clauses)
     #`(begin . clause*.defs)]))

(data var : Type (avar : (-> nat var)))

;;Type this:

(define-language stlc
  #:vars (x)
  (val  (v)   ::= true false)
  (type (A B) ::= bool (-> A B))
  (term (e)   ::= x v (e e) (lambda (x : A) e) (cons e e)
                  (let (x x) = e in e)))

;;This gets generated:

#;
(begin
  (data stlc-val : Type
    (stlc-true : stlc-val)
    (stlc-false : stlc-val))

  (data stlc-type : Type
    (stlc-bool : stlc-type)
    (stlc--> : (->* stlc-type stlc-type stlc-type)))

  (data stlc-term : Type
    (var-->-stlc-term : (-> var stlc-term))
    (stlc-val-->-stlc-term : (-> stlc-val stlc-term))
    (stlc-term2151 : (->* stlc-term stlc-term stlc-term))
    (stlc-lambda : (->* var stlc-type stlc-term stlc-term))
    (stlc-cons : (->* stlc-term stlc-term stlc-term))
    (stlc-let : (->* var var stlc-term stlc-term))))

;; Define inference rules in a more natural notation, like so:
#;
(define-relation (has-type gamma term type)
  [(g : gamma)
   ------------------------ T-Unit
   (has-type g unitv Unit)]

  [(g : gamma) (x : var) (t : type)
   (== (maybe type) (lookup-gamma g x) (some type t))
   ------------------------ T-Var
   (has-type g (tvar x) t)]

  [(g : gamma) (e1 : term) (e2 : term) (t1 : type) (t2 : type)
   (has-type g e1 t1)
   (has-type g e2 t2)
   ---------------------- T-Pair
   (has-type g (pair e1 e2) (Pair t1 t2))]

  [(g : gamma) (e : term) (t1 : type) (t2 : type)
   (has-type g e (Pair t1 t2))
   ----------------------- T-Prj1
   (has-type g (prj z e) t1)]

  [(g : gamma) (e : term) (t1 : type) (t2 : type)
   (has-type g e (Pair t1 t2))
   ----------------------- T-Prj2
   (has-type g (prj (s z) e) t1)]

  [(g : gamma) (e1 : term) (t1 : type) (t2 : type) (x : var)
   (has-type (extend-gamma g x t1) e1 t2)
   ---------------------- T-Fun
   (has-type g (lam x t1 e1) (Fun t1 t2))]

  [(g : gamma) (e1 : term) (e2 : term) (t1 : type) (t2 : type)
   (has-type g e1 (Fun t1 t2))
   (has-type g e2 t1)
   ---------------------- T-App
   (has-type g (app e1 e2) t2)])

;; Generate Coq from Cur:

(begin-for-syntax
  (define (output-coq syn)
    (syntax-parse (cur-expand syn)
       #:literals (lambda forall data real-app case)
       [(lambda ~! (x:id (~datum :) t) body:expr)
        (format "(fun ~a : ~a => ~a)" (syntax-e #'x) (output-coq #'t)
                (output-coq #'body))]
       [(forall ~! (x:id (~datum :) t) body:expr)
        (format "(forall ~a : ~a, ~a)" (syntax-e #'x) (output-coq #'t)
                (output-coq #'body))]
       [(data ~! n:id (~datum :) t (x*:id (~datum :) t*) ...)
        (format "Inductive ~a : ~a :=~n~a."
                (syntax-e #'n)
                (output-coq #'t)
                (string-trim
                  (for/fold ([strs ""])
                            ([clause (syntax->list #'((x* : t*) ...))])
                    (syntax-parse clause
                      [(x (~datum :) t)
                       (format "~a~a : ~a~n| " strs (syntax-e #'x)
                               (output-coq #'t))]))
                  #px"\\s\\| $"
                  #:left? #f))]
       ;; TODO: Add "case". Will be slightly tricky since the syntax is
       ;; quite different from Coq.
       [(real-app e1 e2)
        (format "(~a ~a)" (output-coq #'e1) (output-coq #'e2))]
       [e:id (format "~a" (syntax->datum #'e))])))

(define-syntax (generate-coq syn)
  (syntax-parse syn
    [(_ (~optional (~seq #:file file)) body:expr)
     (parameterize ([current-output-port (if (attribute file)
                                             (syntax->datum #'file)
                                             (current-output-port))])
       (displayln (output-coq #'body))
       #'Type)]))

(module+ test
  (require "sugar.rkt")
  (begin-for-syntax
    (require rackunit)
    (check-equal?
      (format "Inductive nat : Type :=~nz : nat.")
      (output-coq #'(data nat : Type (z : nat))))
    (check-regexp-match
      "(forall .+ : Type, Type)"
      (output-coq #'(-> Type Type)))
    ;; TODO: Not sure why these tests are failing.
    (let ([t (output-coq #'(define-relation (meow gamma term type)
                             [(g : gamma) (e : term) (t : type)
                              --------------- T-Bla
                              (meow g e t)]))])
      (check-regexp-match
        "Inductive meow : (forall temp. : gamma, (forall temp. : term, (forall temp. : type, Type))) :="
        (first (string-split t "\n")))
      (check-regexp-match
        "T-Bla : (forall g : gamma, (forall e : term, (forall t : type, (((meow g) e) t))))\\."
        (second (string-split t "\n"))))))