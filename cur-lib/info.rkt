#lang info
(define collection 'multi)
(define deps
  '(("base" #:version "7.0")
    ("turnstile-lib" #:version "0.5")
    ("macrotypes-lib" #:version "0.3.3")
    "reprovide-lang-lib"
    "rosette"
    ))
(define build-deps '())
(define pkg-desc "implementation (no documentation, tests) part of \"cur\".")
(define version "0.5")
(define pkg-authors '(wilbowma stchang))
