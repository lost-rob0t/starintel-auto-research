(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "core-semantics-prototype.lisp" *load-truename*))
(load (merge-pathnames "canonical-json-prototype.lisp" *load-truename*))
(load (merge-pathnames "message-lifecycle-prototype.lisp" *load-truename*))
(load (merge-pathnames "deterministic-dispatcher-prototype.lisp" *load-truename*))
(load (merge-pathnames "transport-port-prototype.lisp" *load-truename*))
(load (merge-pathnames "dispatcher-transport-adapter-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun transport-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun transport-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S."
          label expected actual)))

(defun transport-test-manifest ()
  (let* ((fixture (merge-pathnames "../fixtures/fec-core.star" *load-truename*))
         (library (compile-core-library (load-star-form fixture)))
         (actor
           (compile-actor
            '(actor fec-importer
              (:runtime external
               :protocol star-message-v1
               :endpoint "fake:star.fec.ingest"
               :accepts (ingest-page)
               :produces (index-fec-record)
               :restart permanent
               :mailbox (bounded 1024)))
            library)))
    (emit-core-manifest library (list actor))))

(defun transport-test-command (&key
                                (message-id "transport-command-1")
                                (idempotency-key "transport:fec:1"))
  (make-command-envelope
   :message-id message-id
   :message-type "org.starintel/fec@1/ingest-page"
   :actor "fec-importer"
   :sender "transport-test"
   :idempotency-key idempotency-key
   :dataset "fec-2026"
   :payload '(("endpoint" . "/candidates/search/")
              ("cycle" . 2026)
              ("page" . 1)
              ("results" . ())
              ("retrieved-at" . "2026-07-23T00:00:00Z"))))

(defun transport-index-payload ()
  '(("document" .
     (("schema" . "org.starintel/fec@1/candidate")
      ("id" . "H2OH03116")))
    ("source-endpoint" . "/candidates/search/")
    ("cycle" . 2026)))

(defun transport-envelope-kinds (envelopes)
  (mapcar (lambda (envelope) (getf envelope :kind)) envelopes))

(defun transport-settlement-actions (transport)
  (mapcar (lambda (settlement) (getf settlement :action))
          (fake-transport-settlements transport)))

(defun write-transport-ndjson (pathname manifest envelopes)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (dolist (envelope envelopes)
      (write-string (canonical-lifecycle-envelope-json manifest envelope) stream)
      (terpri stream))))

(defun make-transport-test-runtime (manifest &key (publish-failures 0))
  (let* ((dispatcher
           (make-deterministic-dispatcher
            manifest :now "2026-07-23T00:00:01Z"))
         (transport
           (make-fake-transport :publish-failures publish-failures))
         (port (bind-fake-transport-port transport))
         (adapter (make-transport-dispatch-adapter dispatcher port)))
    (values dispatcher transport adapter)))

(defun register-completing-importer (dispatcher &optional counter)
  (register-dispatch-actor
   dispatcher "fec-importer"
   (lambda (runtime envelope)
     (declare (ignore runtime envelope))
     (when counter (incf (car counter)))
     (complete-dispatch
      :message-type "org.starintel/fec@1/index-fec-record"
      :payload (transport-index-payload)))))

(defun test-success-and-broker-duplicate (manifest)
  (multiple-value-bind (dispatcher transport adapter)
      (make-transport-test-runtime manifest)
    (let ((calls (list 0))
          (command (transport-test-command)))
      (register-completing-importer dispatcher calls)
      (fake-transport-submit transport command)
      (transport-assert-equal
       :acked (run-transport-adapter-next adapter)
       "successful delivery is acknowledged")
      (transport-assert-equal
       '(:ack :reply :ack)
       (transport-envelope-kinds (fake-transport-published transport))
       "successful delivery publishes accepted, reply, completed")
      (transport-assert-equal 1 (car calls) "handler runs once")
      (fake-transport-submit transport command :redelivery-count 1)
      (transport-assert-equal
       :acked (run-transport-adapter-next adapter)
       "broker duplicate is acknowledged")
      (transport-assert-equal 1 (car calls)
                              "broker duplicate does not repeat side effects")
      (transport-assert-equal
       '(:ack :reply :ack :reply :ack)
       (transport-envelope-kinds (fake-transport-published transport))
       "broker duplicate replays terminal outcomes only")
      (transport-assert-equal
       '(:ack :ack)
       (transport-settlement-actions transport)
       "both deliveries are settled")
      (fake-transport-published transport))))

(defun test-retry-schedules-redelivery (manifest)
  (multiple-value-bind (dispatcher transport adapter)
      (make-transport-test-runtime manifest)
    (let ((calls 0)
          (command
            (transport-test-command
             :message-id "transport-retry-1"
             :idempotency-key "transport:fec:retry")))
      (register-dispatch-actor
       dispatcher "fec-importer"
       (lambda (runtime envelope)
         (declare (ignore runtime envelope))
         (incf calls)
         (if (= calls 1)
             (retry-dispatch
              :retry-after-ms 2000
              :reason "rate limit")
             (complete-dispatch
              :message-type "org.starintel/fec@1/index-fec-record"
              :payload (transport-index-payload)))))
      (fake-transport-submit transport command)
      (transport-assert-equal
       :requeued (run-transport-adapter-next adapter)
       "retry outcome requeues through transport")
      (transport-assert-equal
       '(:requeue)
       (transport-settlement-actions transport)
       "first transport delivery is requeued")
      (let* ((redelivery (first (fake-transport-inbound transport)))
             (envelope (transport-delivery-envelope redelivery)))
        (transport-assert-equal 2 (getf envelope :attempt)
                                "scheduled redelivery increments attempt")
        (transport-assert-equal "transport-retry-1"
                                (getf envelope :correlation-id)
                                "scheduled redelivery preserves correlation")
        (transport-assert-equal "transport-retry-1"
                                (getf envelope :causation-id)
                                "scheduled redelivery records direct cause")
        (transport-assert-equal 1
                                (transport-delivery-redelivery-count redelivery)
                                "transport tracks broker redelivery count"))
      (transport-assert-equal nil (run-transport-adapter-next adapter)
                              "redelivery remains hidden before delay")
      (advance-fake-transport-clock transport 2000)
      (transport-assert-equal
       :acked (run-transport-adapter-next adapter)
       "visible redelivery completes")
      (transport-assert-equal 2 calls "handler runs once per logical attempt")
      (transport-assert-equal
       '(:requeue :ack)
       (transport-settlement-actions transport)
       "retry then success settlement sequence")
      (fake-transport-published transport))))

(defun test-deferred-cancellation-settles-held-delivery (manifest)
  (multiple-value-bind (dispatcher transport adapter)
      (make-transport-test-runtime manifest)
    (let ((command
            (transport-test-command
             :message-id "transport-held-1"
             :idempotency-key "transport:fec:held")))
      (register-dispatch-actor
       dispatcher "fec-importer"
       (lambda (runtime envelope)
         (declare (ignore runtime envelope))
         (defer-dispatch)))
      (fake-transport-submit transport command)
      (transport-assert-equal :held (run-transport-adapter-next adapter)
                              "deferred command remains unsettled")
      (transport-assert-equal 1
                              (transport-dispatch-adapter-held-count adapter)
                              "adapter tracks held delivery")
      (transport-assert-equal 1
                              (hash-table-count
                               (fake-transport-in-flight transport))
                              "held delivery remains in flight")
      (let ((cancel
              (make-cancel-envelope
               command
               :message-id "transport-cancel-1"
               :actor "fec-importer"
               :sender "transport-test"
               :reason "operator request")))
        (fake-transport-submit transport cancel)
        (transport-assert-equal
         :acked (run-transport-adapter-next adapter)
         "cancel control delivery is acknowledged"))
      (transport-assert-equal 0
                              (transport-dispatch-adapter-held-count adapter)
                              "cancel clears held delivery")
      (transport-assert-equal 0
                              (hash-table-count
                               (fake-transport-in-flight transport))
                              "cancel settles both deliveries")
      (transport-assert-equal
       '(:ack :ack)
       (transport-settlement-actions transport)
       "held command and cancel are acknowledged")
      (transport-assert-equal
       '(:ack :error)
       (transport-envelope-kinds (fake-transport-published transport))
       "cancel publishes accepted then terminal cancellation")
      (fake-transport-published transport))))

(defun test-publish-before-settlement-recovery (manifest)
  (multiple-value-bind (dispatcher transport adapter)
      (make-transport-test-runtime manifest :publish-failures 1)
    (let ((calls (list 0))
          (command
            (transport-test-command
             :message-id "transport-publish-failure"
             :idempotency-key "transport:fec:publish-failure")))
      (register-completing-importer dispatcher calls)
      (fake-transport-submit transport command)
      (transport-assert-equal
       :transport-requeued (run-transport-adapter-next adapter)
       "publish failure requeues input instead of acknowledging it")
      (transport-assert-equal nil (fake-transport-published transport)
                              "failed publish emits nothing")
      (transport-assert-equal 1 (car calls)
                              "handler completed before injected failure")
      (transport-assert-equal
       '(:requeue)
       (transport-settlement-actions transport)
       "input remains redeliverable after publish failure")
      (transport-assert-equal
       :acked (run-transport-adapter-next adapter)
       "redelivery resumes retained outcomes and acknowledges")
      (transport-assert-equal 1 (car calls)
                              "publication recovery does not rerun handler")
      (transport-assert-equal
       '(:ack :reply :ack)
       (transport-envelope-kinds (fake-transport-published transport))
       "outbox repairs every outcome that failed to publish")
      (transport-assert-equal
       '(:requeue :ack)
       (transport-settlement-actions transport)
       "recovered delivery is finally acknowledged")
      (fake-transport-published transport))))

(defun test-poison-delivery-is-rejected (manifest)
  (multiple-value-bind (dispatcher transport adapter)
      (make-transport-test-runtime manifest)
    (register-completing-importer dispatcher)
    (let ((command
            (transport-test-command
             :message-id "transport-poison"
             :idempotency-key "transport:fec:poison")))
      (setf (getf command :actor) "missing-actor")
      (fake-transport-submit transport command)
      (transport-assert-equal :rejected
                              (run-transport-adapter-next adapter)
                              "invalid route is rejected")
      (transport-assert-equal 1
                              (length (fake-transport-dead-letters transport))
                              "poison delivery enters dead letter collection")
      (transport-assert-equal
       '(:reject)
       (transport-settlement-actions transport)
       "poison delivery has terminal transport settlement"))))

(defun run-transport-port-tests ()
  (let ((manifest (transport-test-manifest)))
    (write-transport-ndjson
     "star-lang-transport-success.ndjson"
     manifest (test-success-and-broker-duplicate manifest))
    (write-transport-ndjson
     "star-lang-transport-retry.ndjson"
     manifest (test-retry-schedules-redelivery manifest))
    (write-transport-ndjson
     "star-lang-transport-cancel.ndjson"
     manifest (test-deferred-cancellation-settles-held-delivery manifest))
    (write-transport-ndjson
     "star-lang-transport-publish-recovery.ndjson"
     manifest (test-publish-before-settlement-recovery manifest))
    (test-poison-delivery-is-rejected manifest)
    (format t "Star-Lang transport port tests passed.~%")
    t))

(unless (run-transport-port-tests)
  (error "Star-Lang transport port tests failed."))