(load "prototypes/star-lang/common-lisp/prototype.lisp")

(in-package #:star-lang.prototype)

(let ((fixture "prototypes/star-lang/fixtures/email-enumeration.sexp"))
  (test-reader-rejects-dispatch)
  (multiple-value-bind (runtime outputs loaded-fixture) (run-example fixture)
    (declare (ignore outputs loaded-fixture))
    (test-transient-persistence-rejected runtime))
  (unless (run-tests fixture)
    (error "Star-Lang Common Lisp baseline tests failed."))
  (format t "Star-Lang Common Lisp baseline tests passed.~%")
  (format t "Benchmark (100 iterations): ~,6F seconds.~%"
          (benchmark-example fixture 100)))
