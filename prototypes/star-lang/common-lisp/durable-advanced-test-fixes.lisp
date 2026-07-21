(in-package #:star-lang.core.tests)

(defun test-nil-result-replay ()
  (let ((registry (star-lang.core:make-core-registry))
        (dispatches 0))
    (star-lang.core:register-schema
     registry "target" 1 :persistent
     '(("name" :string t)))
    (star-lang.core:register-capability
     registry "flaky-actor" :actor "target" nil '(:actor)
     (lambda (document runtime)
       (declare (ignore document runtime))
       (incf dispatches)
       nil))
    (let* ((plan
             (star-lang.core:compile-source
              +single-effect-source+ registry
              :source-name "nil-result.star"))
           (target
             (star-lang.core:make-core-document
              registry "target" '(("name" "Ada"))))
           (journal (star-lang.core:make-memory-journal)))
      (ignore-errors
        (star-lang.core:run-plan-durable
         plan registry (list target) journal :run-id "nil-run"))
      (ensure-equal 1 dispatches "first nil command dispatch")
      (ignore-errors
        (star-lang.core:run-plan-durable
         plan registry (list target) journal :run-id "nil-run"))
      (ensure-equal 1 dispatches
                    "nil command result is replayed, not redispatched"))))
