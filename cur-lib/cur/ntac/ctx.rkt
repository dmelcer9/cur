#lang racket/base

;; API and implementation for NtacCtx
;; - the context for an ntac proof tree node

;; NOTE:
;; This is different/unrelated to Turnstile+'s type environment representation,
;; which is implemented with a Racket defintion context.
;;
;; More specifically, tactics require different operations, eg
;; - removing items (generalize, destruct, induction)
;; - searching for a ctxt item and splitting ctxt (destruct, induction)
;; - updating previous items (while preserving scoping) (destruct, induction)

;; An NtacCtx is an (ctx (listof CtxItem))
;; - list items are in *reverse* order of normal left-to-right scope
;; - ie, first entry in the list has innermost scope
;; - but all *user-facing* syntax has typical outermost-in, left-to-right scoping, eg
;;   - iteration starts with outermost scope 
;;   - append and ctx-adds args: among args, first arg has outermost scope
;;   - accessors also return bindings and types left-to-right
;;
;; A CtxItem is a (ctxitem Id Type), where
;; An Id is a stx identifier
;; A Type is a stx obj with the appropriate ': property

(provide mk-empty-ctx

         ctx-ids
         ctx-types

         ctx-add
         ctx-add/id
         ctx-adds
         ctx-adds/ids
         ctx-map
         ctx-fold
         ctx-splitf
         ctx-splitf/ty/outerin
         ctx-partitionf
         ctx-partition/ty
         ctx-append
         ctx-lookup
         ctx-lookup/split
         ctx-remove
         ctx-remove/id
         ctx-removes
         ctx-remove-inner
         ctx-has-id?

         ctx->stx
         ctx-tys->stx
         ctx->env
         ctx-difference)

(require racket/list
         syntax/stx)

(struct ctx (items) #:transparent
  #:property prop:sequence
  (λ (ctxt)
    (make-do-sequence
     (λ ()
       (values (λ (lst) ; pos->element
                 (let ([i (car lst)])
                   (values (ctxitem-id i) (ctxitem-type i))))
               cdr      ; next-pos
               (reverse ; initial pos = listof ctxitem, first item has outermost scope
                (ctx-items ctxt))
               pair? ; ie not null? ; continue-with-pos?
               #f #f)))))
(struct ctxitem (id type) #:transparent)

(define (ctx-types ctxt)
  (reverse (map ctxitem-type (ctx-items ctxt))))
(define (ctx-ids ctxt)
  (reverse (map ctxitem-id (ctx-items ctxt))))

;; ctxitem-id=? : CtxItem CtxItem -> Bool
;; Returns true if the ids of the two ctxitems are free-id=?
(define (ctxitem-id=? i j)
  (free-identifier=? (ctxitem-id i) (ctxitem-id j)))

(define ((ctxitem-id=x? x) i)
  (free-identifier=? (ctxitem-id i) x))

;; (require racket/dict)
;; ;; TODO: change ctxt representation
;; ;; - it must be ordered? so list of x+tys?
;; ;;   - eg, destruct must also change all types in ctxt that are in the scope of destructed var
;; (define (identifier-hash) (make-immutable-custom-hash free-identifier=?))

;; returns empty NtacCtx
(define (mk-empty-ctx) (ctx null))

;; ctx-add : NtacCtx Id Type -> NtacCtx
;; adds given id and type to NtacCtx
(define (ctx-add ctxt x ty)
  (ctx (cons (ctxitem x ty) (ctx-items ctxt))))

;; ctx-add/id : Id Type -> (-> NtacCtx NtacCtx)
;; curried version of ctx-add
(define ((ctx-add/id x ty) ctxt) (ctx-add ctxt x ty))

;; ctx-adds : NtacCtx (listof Id) (listof Type) -> NtacCtx
;; adds given ids and types to NtacCtx
;; - `f` is applied to each ty, with the intermediate ctxt,
;;   before it's added to the ctxt;
(define (ctx-adds ctxt xs tys #:do [f (λ (t tmp-ctxt) t)])
  (foldl (ctx-add/fold f) ctxt (stx->list xs) (stx->list tys)))

;; ctx-adds/ids : (listof Id) (listof Type) -> (-> NtacCtx NtacCtx)
;; curried version of ctx-adds
(define ((ctx-adds/ids xs tys) ctxt) (ctx-adds ctxt xs tys))

;; ctx-add/fold : Id Type NtacCtx -> NtacCtx
;; adds given id and type to NtacCtx
;; - unlike ctx-add, ctx is third arg, for use with folds
(define ((ctx-add/fold f) x ty ctxt)
  (ctx-add ctxt x (f ty ctxt)))

;; ctx-remove : NtacCtx Id -> NtacCtx
;; removes CtxItem with id x
(define (ctx-remove ctxt x)
  (ctx (remove (ctxitem x #'Tmp) (ctx-items ctxt) ctxitem-id=?)))

;; ctx-remove/id : Id -> (-> NtacCtx NtacCtx)
;; curried version of ctx-remove
(define ((ctx-remove/id x) ctxt) (ctx-remove ctxt x))

(define (ctx-remove/fold x ctxt) (ctx-remove ctxt x))

;; ctx-removes : NtacCtx (listof Id) -> NtacCtx
;; removes CtxItems with ids xs
(define (ctx-removes ctxt xs)
  (foldl ctx-remove/fold ctxt xs))

;; removes innermost entry from ctxt,
;; does nothing if ctxt is empty
(define (ctx-remove-inner ctxt)
  (if (null? (ctx-items ctxt))
      ctxt
      (ctx (cdr (ctx-items ctxt)))))

;; ctx-lookup : NtacCtx Id -> Type or #f
;; looks up id in ctxt, starting with innermost scope
(define (ctx-lookup ctxt x)
  (define res/#f (findf (ctxitem-id=x? x) (ctx-items ctxt)))
  (and res/#f (ctxitem-type res/#f)))

;; ctx-lookup/split : NtacCtx Id -> NtacCtx NtacCtx
;; splits given ctxt into 2, at the given id
;; - lookup starts with innermost scope
;; - given id is first entry of second returned ctx
(define (ctx-lookup/split ctxt id)
  (ctx-splitf ctxt (λ (item) (not ((ctxitem-id=x? id) item)))))

;; ctx-splitf : NtacCtx (-> CtxItem Bool) -> NtacCtx NtacCtx
;; splits given ctxt into two partitions using predicate p?
;; - (like splitf) applying p? to left partition = #t, respectively
;;   and right element on right is first #f
(define (ctx-splitf ctxt p?)
  (let-values ([(inner outer) (splitf-at (ctx-items ctxt) p?)])
    (values (ctx outer) (ctx inner))))

;; ctx-splitf/ty : NtacCtx (-> Type Bool) -> NtacCtx NtacCtx
;; splits given ctxt into two partitions using predicate p? on ctxitem type
;; - unlike ctx-splitf, which starts with innermost scope,
;;   this starts with outermost scope first
;; - stops at first ctxitem satisfying p?
;;   - this item will be outermost item in `inner`
(define (ctx-splitf/ty/outerin ctxt p?)
  (let-values ([(outer inner)
                (splitf-at (reverse (ctx-items ctxt))
                           (λ (item) (p? (ctxitem-type item))))])
    (values (ctx (reverse outer)) (ctx (reverse inner)))))

;; ctx-partitionf : NtacCtx (-> CtxItem Bool) -> NtacCtx NtacCtx
;; splits given ctxt into two partitions using predicate p? on ctxitem
;; - unlike ctx-splitf, which starts with innermost scope,
;;   this starts with outermost scope first
;; - unlike ctx-splitf/ty/outerin, which stops at first ctxitem satisfying p?,
;;   this always checks every ctx item
(define (ctx-partitionf ctxt p?)
  (let-values ([(yes no)
                (partition p? (reverse (ctx-items ctxt)))])
    (values (ctx (reverse yes)) (ctx (reverse no)))))

;; ctx-partition/ty : NtacCtx (-> Type Bool) -> NtacCtx NtacCtx
;; splits given ctxt into two partitions using predicate p? on ctxitem type
;; - unlike ctx-splitf, which starts with innermost scope,
;;   this starts with outermost scope first
;; - unlike ctx-splitf/ty/outerin, which stops at first ctxitem satisfying p?,
;;   this always checks every ctx item
(define (ctx-partition/ty ctxt p?)
  (ctx-partitionf ctxt (λ (ctx-item) (p? (ctxitem-type ctx-item)))))

;; appends zero or more NtacCtxs together
;; - first arg is "inner" scope
(define (ctx-append . ctxs)
  (ctx (apply append (reverse (map ctx-items ctxs)))))

;; maps f over types in ctx
(define (ctx-map f ctxt)
  (ctx
   (map
    (λ (i)
      (ctxitem (ctxitem-id i) (f (ctxitem-type i))))
    (reverse (ctx-items ctxt)))))

(define (ctx-fold f ctxt init-ctxt)
  (foldl
   (λ (i tmp-ctxt)
     (ctx-add tmp-ctxt (ctxitem-id i) (f (ctxitem-type i) tmp-ctxt)))
   init-ctxt
   (reverse (ctx-items ctxt))))

(define (ctx-tys->stx ctxt #:do [ty-fn (λ (x) x)])
  (for/list ([(_ ty) ctxt]) (ty-fn ty)))

(define (ctx->stx ctxt #:do [ty-fn (λ (x) x)])
  (for/list ([(x ty) ctxt]) (list x ': (ty-fn ty))))

;; converts NtacCtx to Turnstile+ env
;; - NOTE: does not reverse scoping order, so first item is innermost scope
(define (ctx->env c)
  (map item->stx (ctx-items c)))

;; converts a CtxItem to stx object for use with turnstile+
(define (item->stx i)
  (cons (ctxitem-id i) (ctxitem-type i)))

;; TODO: is this needed?
(define (ctx-has-id? ctxt x)
  (ctx-lookup ctxt x))


(require syntax/parse)
(provide ctx-introduce)
(define (datum=? e1 e2) (equal? (syntax->datum e1) (syntax->datum e2)))

;; replaces all ids in stx with analogous bindings in ctxt
;; TODO: this is hacky; what's a better way?
(define (ctx-introduce stx ctxt)
  (define ids (ctx-ids ctxt))
  (let L ([stx stx])
    (syntax-parse stx
      [x:id #:do[(define y (findf (λ (id) (datum=? id #'x)) ids))] (or y #'x)]
      [(x ...) (datum->syntax stx (stx-map L #'(x ...)) stx stx)]
      [_ stx])))

;; NtacCtx NtacCtx -> NtacCtx
;; Find all context items that exist in the first argument but not the second
(define (ctx-difference base-ctx subtr-ctx)
  (define-values (result _)
    (ctx-partitionf base-ctx
                    (λ (item)
                      (define id (ctxitem-id item))
                      (define item-in-subtr (ctx-lookup subtr-ctx id))
                      (not item-in-subtr))))
  result)