#lang racket

(require rackunit
         "runtime.rkt")

(define fixture-path
  (build-path (current-directory)
              "prototypes"
              "star-lang"
              "fixtures"
              "email-enumeration.sexp"))

(define-values (rt outputs fixture)
  (run-example fixture-path))

(check-equal? (event-count rt 'transient-emitted) 3)
(check-equal? (event-count rt 'actor-result) 3)
(check-equal? (event-count rt 'tool-invoked) 1)
(check-equal? (length (runtime-persisted rt)) 1)
(check-equal? (doc-type (first (runtime-persisted rt))) 'final-review)
(check-equal? (length outputs) 1)
(check-equal? (document-ref (first outputs) 'found-emails)
              '("ada@gmail.com" "ada@proton.me"))
(check-equal? (dataflow-plan rt 'email-enumeration)
              expected-plan)

(define candidate
  (transient-document
   rt
   'email-candidate
   (list 'username "ada")
   (list 'email "ada@example.com")))

(check-exn
 (lambda (error)
   (and (exn:fail:star? error)
        (eq? (exn:fail:star-kind error) 'persistence)))
 (lambda () (persist! rt candidate)))

(define rejected
  (make-temporary-file "star-lang-racket-rejected-~a.sexp"))
(call-with-output-file rejected
  #:exists 'truncate
  (lambda (out)
    (display "#reader \"bad.rkt\"" out)))

(check-exn exn:fail:star?
           (lambda () (load-fixture rejected)))
(delete-file rejected)

(printf "Star-Lang Racket embedded baseline passed.~n")
(printf "Smoke benchmark: ~a seconds for 100 iterations.~n"
        (benchmark-example fixture-path 100))
