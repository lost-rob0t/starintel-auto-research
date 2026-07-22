(load "prototypes/star-lang/common-lisp/spec-domain-prototype.lisp")

(in-package #:star-lang.spec-domain.prototype)

(defun condition-signaled-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun run-ci-test (name function)
  (format t "Running ~A...~%" name)
  (funcall function)
  (format t "Passed ~A.~%" name))

(mapc
 (lambda (entry)
   (run-ci-test (car entry) (cdr entry)))
 (list
  (cons "remote digest requirement"
        #'test-remote-library-requires-digest)
  (cons "import lock mismatch rejection"
        #'test-import-lock-mismatch-rejected)
  (cons "exact import lock acceptance"
        #'test-exact-import-lock-accepted)
  (cons "additive extension enforcement"
        #'test-extension-is-additive)
  (cons "relation type constraints"
        #'test-relation-type-constraints)
  (cons "dataset destination filtering"
        #'test-dataset-destination-filter)
  (cons "email actor output"
        #'test-email-actor-output)
  (cons "domain-server metadata"
        #'test-domain-server-metadata)))

(multiple-value-bind (runtime emails relations employer) (run-example)
  (declare (ignore runtime employer))
  (format t "Star-Lang specification and domain-server prototype tests passed.~%")
  (format t "Employment relations: ~D~%" (length relations))
  (format t "Generated emails: ~S~%" emails))
