(load (string-append (getcwd) "/prototypes/star-lang/scheme/baseline.scm"))

(define fixture-path
  "prototypes/star-lang/fixtures/email-enumeration.sexp")

(define (assert-equal expected actual label)
  (unless (equal? expected actual)
    (error label expected actual)))

(define result (run-example fixture-path))
(define rt (car result))
(define outputs (cadr result))

(assert-equal 3 (event-count rt 'transient-emitted) "transient candidates")
(assert-equal 3 (event-count rt 'actor-result) "actor results")
(assert-equal 1 (event-count rt 'tool-invoked) "tool calls")
(assert-equal 1 (length (runtime-persisted rt)) "persisted count")
(assert-equal 'final-review
              (doc-type (car (runtime-persisted rt)))
              "persisted type")
(assert-equal '("ada@gmail.com" "ada@proton.me")
              (document-ref (car outputs) 'found-emails)
              "found emails")
(assert-equal expected-plan
              (dataflow-plan rt 'email-enumeration)
              "normalized plan")

(define transient
  (transient-document rt 'email-candidate
    (list 'username "ada")
    (list 'email "ada@example.com")))

(assert-equal #t
  (catch star-error-tag
    (lambda () (persist! rt transient) #f)
    (lambda (tag kind message) (eq? kind 'persistence)))
  "transient persistence rejection")

(display "Star-Lang Guile Scheme baseline passed.\n")
(format #t "Smoke benchmark: ~a seconds for 100 iterations.\n"
        (benchmark-example fixture-path 100))
