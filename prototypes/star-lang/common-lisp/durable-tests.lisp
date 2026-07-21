(in-package #:star-lang.core.tests)

(defun strictly-sequential-events-p (events)
  (loop for event in events
        for expected from 1
        always (= expected (star-lang.core:run-event-sequence event))))

(defun test-crash-and-resume ()
  (let* ((registry (make-registry))
         (plan (star-lang.core:compile-source
                +analysis-source+ registry
                :source-name "durable-analysis.star"))
         (target (make-target registry))
         (journal (star-lang.core:make-memory-journal))
         (crashed nil))
    (handler-case
        (star-lang.core:run-plan-durable
         plan registry (list target) journal
         :run-id "durable-run"
         :crash-predicate
         (lambda (event)
           (when (and (not crashed)
                      (eq (star-lang.core:run-event-type event)
                          :command-result))
             (setf crashed t)
             t)))
      (star-lang.core:simulated-runtime-crash () nil))
    (ensure-true crashed "simulated crash occurred")
    (let ((prefix
            (star-lang.core:journal-read-events journal "durable-run")))
      (ensure-equal 1 (count-events prefix :command-result)
                    "recorded result before crash")
      (ensure-true (strictly-sequential-events-p prefix)
                   "prefix event sequence"))
    (multiple-value-bind (outputs resumed-runtime)
        (star-lang.core:run-plan-durable
         plan registry (list target) journal
         :run-id "durable-run")
      (ensure-equal 1 (length outputs) "resumed output count")
      (ensure-equal 3
                    (star-lang.core:runtime-dispatch-count resumed-runtime)
                    "resume dispatches only missing effects")
      (ensure-equal
       '("ada@gmail.com" "ada@proton.me")
       (star-lang.core:document-field
        (first outputs) "found-emails")
       "resumed found emails"))
    (let ((history
            (star-lang.core:journal-read-events journal "durable-run")))
      (ensure-true (strictly-sequential-events-p history)
                   "complete event sequence")
      (ensure-true (find-event history :run-resumed)
                   "run-resumed event")
      (ensure-true (find-event history :run-completed)
                   "run-completed event"))
    (multiple-value-bind (outputs replayed-runtime)
        (star-lang.core:run-plan-durable
         plan registry (list target) journal
         :run-id "durable-run")
      (ensure-equal 1 (length outputs) "second resume output count")
      (ensure-equal 0
                    (star-lang.core:runtime-dispatch-count replayed-runtime)
                    "completed effects are never redispatched"))))

(defun test-checkpoint-store-contract ()
  (let* ((store (star-lang.core:make-memory-checkpoint-store))
         (checkpoint
           (star-lang.core:make-run-checkpoint
            :run-id "checkpoint-run"
            :plan-hash "plan-hash"
            :event-sequence 42
            :state '(:node "n-42"))))
    (star-lang.core:write-run-checkpoint store checkpoint)
    (ensure-equal
     checkpoint
     (star-lang.core:read-run-checkpoint
      store "checkpoint-run" "plan-hash")
     "checkpoint read")
    (ensure-true
     (star-lang.core:delete-run-checkpoint
      store "checkpoint-run" "plan-hash")
     "checkpoint deletion")
    (ensure-equal
     nil
     (star-lang.core:read-run-checkpoint
      store "checkpoint-run" "plan-hash")
     "checkpoint deleted")))

(defun test-recovery-without-checkpoint ()
  (let* ((registry (make-registry))
         (plan (star-lang.core:compile-source
                +analysis-source+ registry
                :source-name "checkpointless-analysis.star"))
         (target (make-target registry))
         (journal (star-lang.core:make-memory-journal))
         (store (star-lang.core:make-memory-checkpoint-store))
         (crashed nil))
    (handler-case
        (star-lang.core:run-plan-durable
         plan registry (list target) journal
         :run-id "checkpointless-run"
         :crash-predicate
         (lambda (event)
           (when (and (not crashed)
                      (eq (star-lang.core:run-event-type event)
                          :command-result))
             (setf crashed t)
             t)))
      (star-lang.core:simulated-runtime-crash () nil))
    (ensure-true crashed "checkpointless crash after durable result")
    (ensure-equal
     nil
     (star-lang.core:read-run-checkpoint
      store "checkpointless-run"
      (star-lang.core:analysis-plan-hash plan))
     "no checkpoint exists")
    (multiple-value-bind (outputs runtime)
        (star-lang.core:run-plan-durable
         plan registry (list target) journal
         :run-id "checkpointless-run")
      (ensure-equal 1 (length outputs)
                    "checkpointless recovery output")
      (ensure-true
       (< (star-lang.core:runtime-dispatch-count runtime) 4)
       "checkpointless recovery reused recorded effects"))))

(defun test-journal-rejects-out-of-order-events ()
  (let* ((journal (star-lang.core:make-memory-journal))
         (event
           (star-lang.core::make-run-event
            :sequence 2
            :type :run-created
            :run-id "bad-run"
            :plan-hash "p"
            :node-id nil
            :payload nil)))
    (ensure-true
     (signals-code-p
      :invalid-event-sequence
      (lambda ()
        (star-lang.core:journal-append-event journal event)))
     "journal rejects sequence gaps")))

(defun run-durable-tests ()
  (test-crash-and-resume)
  (test-checkpoint-store-contract)
  (test-recovery-without-checkpoint)
  (test-journal-rejects-out-of-order-events)
  (format t "Star-Lang durable recovery tests passed.~%")
  t)

(defun run-advanced-tests ()
  (run-complete-tests)
  (run-durable-tests)
  t)
