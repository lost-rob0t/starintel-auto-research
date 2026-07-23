(load (merge-pathnames "transport-port-tests.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun make-second-publish-failing-port (transport)
  (let ((base (bind-fake-transport-port transport))
        (attempts 0))
    (make-transport-port
     :name "fake-second-publish-failure"
     :receive (lambda () (transport-receive base))
     :publish (lambda (envelope)
                (incf attempts)
                (if (= attempts 2)
                    (fail 'transport-port-error
                          "Injected second-publish failure.")
                    (transport-publish base envelope)))
     :ack (lambda (delivery) (transport-ack base delivery))
     :requeue (lambda (delivery replacement delay-ms)
                (transport-requeue base delivery replacement delay-ms))
     :reject (lambda (delivery reason)
               (transport-reject base delivery reason))
     :now (lambda () (transport-now base)))))

(defun test-partial-publication-resumes-at-next-envelope (manifest)
  (let* ((dispatcher
           (make-deterministic-dispatcher
            manifest :now "2026-07-23T00:00:01Z"))
         (transport (make-fake-transport))
         (port (make-second-publish-failing-port transport))
         (adapter (make-transport-dispatch-adapter dispatcher port))
         (calls (list 0))
         (command
           (transport-test-command
            :message-id "transport-partial-publish"
            :idempotency-key "transport:fec:partial-publish")))
    (register-completing-importer dispatcher calls)
    (fake-transport-submit transport command)
    (transport-assert-equal
     :transport-requeued
     (run-transport-adapter-next adapter)
     "partial publication failure requeues source delivery")
    (transport-assert-equal 1 (car calls)
                            "handler executes before partial publication failure")
    (transport-assert-equal 1
                            (transport-dispatch-adapter-pending-count adapter)
                            "publication cursor remains pending")
    (transport-assert-equal
     '(:ack)
     (transport-envelope-kinds (fake-transport-published transport))
     "first successfully published envelope is retained")
    (transport-assert-equal
     :acked
     (run-transport-adapter-next adapter)
     "redelivery resumes remaining publications and acknowledges")
    (transport-assert-equal 1 (car calls)
                            "publication resume does not rerun handler")
    (transport-assert-equal 0
                            (transport-dispatch-adapter-pending-count adapter)
                            "publication cursor clears after settlement")
    (transport-assert-equal
     '(:ack :reply :ack)
     (transport-envelope-kinds (fake-transport-published transport))
     "resume publishes only the remaining reply and completion")
    (fake-transport-published transport)))

(defun test-deferred-accepted-publication-recovery (manifest)
  (multiple-value-bind (dispatcher transport adapter)
      (make-transport-test-runtime manifest :publish-failures 1)
    (let ((calls 0)
          (command
            (transport-test-command
             :message-id "transport-deferred-publish"
             :idempotency-key "transport:fec:deferred-publish")))
      (register-dispatch-actor
       dispatcher "fec-importer"
       (lambda (runtime envelope)
         (declare (ignore runtime envelope))
         (incf calls)
         (defer-dispatch)))
      (fake-transport-submit transport command)
      (transport-assert-equal
       :transport-requeued
       (run-transport-adapter-next adapter)
       "failed accepted publication requeues deferred command")
      (transport-assert-equal 1
                              (transport-dispatch-adapter-pending-count adapter)
                              "deferred result remains in publication outbox")
      (transport-assert-equal 0
                              (transport-dispatch-adapter-held-count adapter)
                              "delivery is not held before accepted publication")
      (transport-assert-equal
       :held
       (run-transport-adapter-next adapter)
       "redelivery publishes accepted and restores held state")
      (transport-assert-equal 1 calls
                              "deferred publication recovery does not rerun actor")
      (transport-assert-equal 0
                              (transport-dispatch-adapter-pending-count adapter)
                              "deferred publication clears after hold")
      (transport-assert-equal 1
                              (transport-dispatch-adapter-held-count adapter)
                              "redelivered command is retained in flight")
      (fake-transport-published transport))))

(defun test-cancel-publication-recovery (manifest)
  (multiple-value-bind (dispatcher transport adapter)
      (make-transport-test-runtime manifest)
    (let ((calls 0)
          (command
            (transport-test-command
             :message-id "transport-cancel-publish"
             :idempotency-key "transport:fec:cancel-publish")))
      (register-dispatch-actor
       dispatcher "fec-importer"
       (lambda (runtime envelope)
         (declare (ignore runtime envelope))
         (incf calls)
         (defer-dispatch)))
      (fake-transport-submit transport command)
      (transport-assert-equal :held (run-transport-adapter-next adapter)
                              "command is held before cancellation")
      (setf (fake-transport-publish-failures-remaining transport) 1)
      (fake-transport-submit
       transport
       (make-cancel-envelope
        command
        :message-id "transport-cancel-publish-control"
        :actor "fec-importer"
        :sender "transport-test"
        :reason "operator request"))
      (transport-assert-equal
       :transport-requeued
       (run-transport-adapter-next adapter)
       "failed cancellation publication requeues cancel delivery")
      (transport-assert-equal 1
                              (transport-dispatch-adapter-pending-count adapter)
                              "terminal cancellation remains pending")
      (transport-assert-equal 1
                              (transport-dispatch-adapter-held-count adapter)
                              "held command remains unsettled until error publishes")
      (transport-assert-equal
       :acked
       (run-transport-adapter-next adapter)
       "cancel redelivery publishes terminal outcome and settles inputs")
      (transport-assert-equal 1 calls
                              "cancel publication recovery never reruns actor")
      (transport-assert-equal 0
                              (transport-dispatch-adapter-pending-count adapter)
                              "cancel outbox clears after publication")
      (transport-assert-equal 0
                              (transport-dispatch-adapter-held-count adapter)
                              "held command clears only after terminal publication")
      (transport-assert-equal
       '(:ack :error)
       (transport-envelope-kinds (fake-transport-published transport))
       "accepted command and recovered cancellation error are published")
      (transport-assert-equal
       '(:requeue :ack :ack)
       (transport-settlement-actions transport)
       "cancel failure requeues, then acknowledges held and control deliveries")
      (fake-transport-published transport))))

(defun run-transport-outbox-tests ()
  (let ((manifest (transport-test-manifest)))
    (write-transport-ndjson
     "star-lang-transport-partial-publication.ndjson"
     manifest
     (test-partial-publication-resumes-at-next-envelope manifest))
    (write-transport-ndjson
     "star-lang-transport-deferred-publication.ndjson"
     manifest
     (test-deferred-accepted-publication-recovery manifest))
    (write-transport-ndjson
     "star-lang-transport-cancel-publication.ndjson"
     manifest
     (test-cancel-publication-recovery manifest))
    (format t "Star-Lang transport publication outbox tests passed.~%")
    t))

(unless (run-transport-outbox-tests)
  (error "Star-Lang transport publication outbox tests failed."))