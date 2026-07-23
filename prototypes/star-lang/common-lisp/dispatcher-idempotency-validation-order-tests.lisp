(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "core-semantics-prototype.lisp" *load-truename*))
(load (merge-pathnames "canonical-json-prototype.lisp" *load-truename*))
(load (merge-pathnames "message-lifecycle-prototype.lisp" *load-truename*))
(load (merge-pathnames "deterministic-dispatcher-prototype.lisp" *load-truename*))
(load (merge-pathnames "dispatcher-idempotency-identity-prototype.lisp" *load-truename*))
(load (merge-pathnames "deferred-dispatch-completion-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-server-core-prototype.lisp" *load-truename*))
(load (merge-pathnames "bbp-domain-server-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun validation-order-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun validation-order-command ()
  (make-bbp-run-tool-command
   :message-id "validation-order-command"
   :program-id "program:validation-order"
   :run-id "run:validation-order:1"
   :tool 'subfinder
   :target "api.example.com"
   :idempotency-key "validation-order-key"))

(defun validation-order-complete-result ()
  (complete-dispatch
   :message-type +bbp-tool-run-completed-message+
   :payload
   '(("program-id" . "program:validation-order")
     ("run-id" . "run:validation-order:1")
     ("tool" . "subfinder")
     ("target" . "api.example.com")
     ("argv" . ("subfinder" "-silent" "-d" "api.example.com"))
     ("exit-code" . 0)
     ("stdout" . "ok")
     ("stderr" . ""))))

(defun test-lifecycle-validation-precedes-identity-check ()
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library tools domain actor))
    (let* ((calls (list 0))
           (command (validation-order-command))
           (dispatcher (make-deterministic-dispatcher manifest)))
      (register-dispatch-handler
       dispatcher
       (getf command :actor)
       (lambda (received)
         (declare (ignore received))
         (incf (car calls))
         (validation-order-complete-result)))
      (submit-dispatch-envelope dispatcher command)
      (unless (eq :completed (run-dispatcher-next dispatcher))
        (fail 'test-error "Initial validation-order command did not complete."))
      (drain-dispatcher-emitted dispatcher)
      (let ((malformed (copy-tree command))
            (invalid-signaled nil)
            (identity-conflict-signaled nil))
        (setf (getf malformed :message-id)
              "validation-order-malformed"
              (getf malformed :message-type)
              nil)
        (submit-dispatch-envelope dispatcher malformed)
        (handler-case
            (run-dispatcher-next dispatcher)
          (invalid-envelope-error ()
            (setf invalid-signaled t))
          (dispatcher-idempotency-conflict-error ()
            (setf identity-conflict-signaled t)))
        (validation-order-assert-true
         invalid-signaled
         "malformed command raises invalid-envelope-error")
        (validation-order-assert-true
         (not identity-conflict-signaled)
         "malformed command does not raise identity conflict")
        (validation-order-assert-true
         (= 1 (car calls))
         "malformed command does not invoke the handler")))))

(test-lifecycle-validation-precedes-identity-check)
(format t "Star-Lang dispatcher validation-order tests passed.~%")
