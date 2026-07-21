(in-package #:star-lang.core.tests)

(defparameter +single-effect-source+
  "(analysis single-effect
      (:version 1)
      (:effects (:actor))
      (sequence
        (from target)
        (through flaky-actor)))")

(defun make-single-effect-fixture (&key fail-first)
  (let ((registry (star-lang.core:make-core-registry))
        (dispatches 0))
    (star-lang.core:register-schema
     registry "target" 1 :persistent
     '(("name" :string t)))
    (star-lang.core:register-capability
     registry "flaky-actor" :actor "target" "target" '(:actor)
     (lambda (document runtime)
       (declare (ignore runtime))
       (incf dispatches)
       (when (and fail-first (= dispatches 1))
         (error "transient actor failure"))
       document))
    (values
     registry
     (star-lang.core:compile-source
      +single-effect-source+ registry
      :source-name "single-effect.star")
     (star-lang.core:make-core-document
      registry "target" '(("name" "Ada")))
     (lambda () dispatches))))

(defun test-command-retry-restart ()
  (multiple-value-bind (registry plan target dispatch-count)
      (make-single-effect-fixture :fail-first t)
    (let ((journal (star-lang.core:make-chained-memory-journal)))
      (handler-bind
          ((star-lang.core:command-dispatch-failed
             (lambda (condition)
               (declare (ignore condition))
               (invoke-restart 'star-lang.core::retry-command))))
        (multiple-value-bind (outputs runtime)
            (star-lang.core:run-plan-durable
             plan registry (list target) journal
             :run-id "retry-run")
          (ensure-equal 1 (length outputs) "retry output count")
          (ensure-equal 2
                        (star-lang.core:runtime-dispatch-count runtime)
                        "runtime retry dispatch count")))
      (ensure-equal 2 (funcall dispatch-count)
                    "capability retry call count")
      (let ((events
              (star-lang.core:journal-read-events journal "retry-run")))
        (ensure-equal 2 (count-events events :command-attempted)
                      "command attempt events")
        (ensure-equal 1 (count-events events :command-failed)
                      "command failed events")
        (ensure-equal 1 (count-events events :restart-selected)
                      "restart selected events")
        (ensure-true
         (star-lang.core:verify-journal-integrity journal "retry-run")
         "retry journal integrity")))))

(defun test-use-command-value-restart ()
  (multiple-value-bind (registry plan target dispatch-count)
      (make-single-effect-fixture :fail-first t)
    (let ((journal (star-lang.core:make-chained-memory-journal)))
      (handler-bind
          ((star-lang.core:command-dispatch-failed
             (lambda (condition)
               (declare (ignore condition))
               (invoke-restart
                'star-lang.core::use-command-value
                target))))
        (multiple-value-bind (outputs runtime)
            (star-lang.core:run-plan-durable
             plan registry (list target) journal
             :run-id "use-value-run")
          (ensure-equal 1 (length outputs) "use-value output count")
          (ensure-equal 1
                        (star-lang.core:runtime-dispatch-count runtime)
                        "use-value dispatch count")))
      (ensure-equal 1 (funcall dispatch-count)
                    "use-value capability calls")
      (let ((events
              (star-lang.core:journal-read-events journal "use-value-run")))
        (ensure-equal 1 (count-events events :command-failed)
                      "use-value failure event")
        (ensure-equal 1 (count-events events :command-result)
                      "use-value replacement result")))))

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
      (star-lang.core:run-plan-durable
       plan registry (list target) journal :run-id "nil-run")
      (star-lang.core:run-plan-durable
       plan registry (list target) journal :run-id "nil-run")
      (ensure-equal 1 dispatches
                    "nil command result is replayed, not redispatched"))))

(defun test-journal-hash-chain ()
  (multiple-value-bind (registry plan target dispatch-count)
      (make-single-effect-fixture)
    (declare (ignore dispatch-count))
    (let ((journal (star-lang.core:make-chained-memory-journal)))
      (star-lang.core:run-plan-durable
       plan registry (list target) journal :run-id "hash-run")
      (ensure-true
       (star-lang.core:verify-journal-integrity journal "hash-run")
       "valid journal hash chain")
      (let ((entries
              (star-lang.core:journal-read-entries journal "hash-run")))
        (setf (star-lang.core:journal-entry-hash (second entries))
              (make-string 64 :initial-element #\f)))
      (ensure-true
       (signals-code-p
        :journal-integrity-failure
        (lambda ()
          (star-lang.core:verify-journal-integrity journal "hash-run")))
       "journal corruption detected"))))

(defun simple-baseline-event-count ()
  (multiple-value-bind (registry plan target dispatch-count)
      (make-single-effect-fixture)
    (declare (ignore dispatch-count))
    (let ((journal (star-lang.core:make-memory-journal)))
      (star-lang.core:run-plan-durable
       plan registry (list target) journal :run-id "baseline")
      (length
       (star-lang.core:journal-read-events journal "baseline")))))

(defun test-every-event-crash-boundary ()
  (let ((event-count (simple-baseline-event-count)))
    (loop for boundary from 1 to event-count
          do
             (multiple-value-bind (registry plan target dispatch-count)
                 (make-single-effect-fixture)
               (let ((journal
                       (star-lang.core:make-chained-memory-journal))
                     (crashed nil))
                 (handler-case
                     (star-lang.core:run-plan-durable
                      plan registry (list target) journal
                      :run-id "boundary-run"
                      :crash-predicate
                      (lambda (event)
                        (when (and (not crashed)
                                   (= boundary
                                      (star-lang.core:run-event-sequence event)))
                          (setf crashed t)
                          t)))
                   (star-lang.core:simulated-runtime-crash () nil))
                 (ensure-true crashed
                              (format nil "crash boundary ~D reached" boundary))
                 (multiple-value-bind (outputs runtime)
                     (star-lang.core:run-plan-durable
                      plan registry (list target) journal
                      :run-id "boundary-run")
                   (declare (ignore runtime))
                   (ensure-equal 1 (length outputs)
                                 (format nil "boundary ~D output" boundary)))
                 (ensure-equal 1 (funcall dispatch-count)
                               (format nil
                                       "boundary ~D exactly-once capability call"
                                       boundary))
                 (ensure-true
                  (star-lang.core:verify-journal-integrity
                   journal "boundary-run")
                  (format nil "boundary ~D journal integrity" boundary)))))))

(defun run-durable-advanced-tests ()
  (test-command-retry-restart)
  (test-use-command-value-restart)
  (test-nil-result-replay)
  (test-journal-hash-chain)
  (test-every-event-crash-boundary)
  (format t "Star-Lang advanced durability tests passed.~%")
  t)

(defun run-super-advanced-tests ()
  (run-advanced-tests)
  (run-durable-advanced-tests)
  t)
