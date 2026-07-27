#lang racket

(require rackunit
         "embedded/runtime.rkt"
         "examples/email-enumeration.rkt")

(define fixture-path
  (build-path (current-directory)
              "prototypes"
              "star-lang"
              "fixtures"
              "email-enumeration.sexp"))

(define fixture
  (load-fixture fixture-path))

(check-true (runtime? (star-program fixture)))

(define-values (rt outputs ignored-fixture)
  (run-star-example fixture-path))

(check-equal? (length outputs) 1)
(check-equal? (doc-type (first outputs)) 'final-review)
(check-equal? (document-ref (first outputs) 'found-emails)
              '("ada@gmail.com" "ada@proton.me"))
(check-equal? (event-count rt 'tool-invoked) 1)

(printf "Star-Lang #lang boundary baseline passed.~n")
