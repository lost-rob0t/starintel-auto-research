(load "prototypes/star-lang/common-lisp/spec-domain-prototype.lisp")

(in-package #:star-lang.spec-domain.prototype)

(unless (run-tests)
  (error "Star-Lang specification and domain-server prototype tests failed."))

(multiple-value-bind (runtime emails relations employer) (run-example)
  (declare (ignore runtime employer))
  (format t "Star-Lang specification and domain-server prototype tests passed.~%")
  (format t "Employment relations: ~D~%" (length relations))
  (format t "Generated emails: ~S~%" emails))
