(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "core-semantics-prototype.lisp" *load-truename*))
(load (merge-pathnames "canonical-json-prototype.lisp" *load-truename*))
(load (merge-pathnames "message-lifecycle-prototype.lisp" *load-truename*))
(load (merge-pathnames "deterministic-dispatcher-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun dispatcher-condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun dispatcher-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun dispatcher-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S." label expected actual)))

(defun dispatcher-write-ndjson (pathname manifest envelopes)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (dolist (envelope envelopes)
      (write-string (canonical-lifecycle-envelope-json manifest envelope) stream)
      (terpri stream))))

(defun dispatcher-test-manifest ()
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

(defun dispatcher-test-command (&key
                                  (message-id "command-0001")
                                  (idempotency-key "fec:candidates:2026:1")
                                  deadline)
  (make-command-envelope
   :message-id message-id
   :message-type "org.starintel/fec@1/ingest-page"
   :actor "fec-importer"
   :sender "dispatcher-test"
   :idempotency-key idempotency-key
   :dataset "fec-2026"
   :deadline deadline
   :payload '(("endpoint" . "/candidates/search/")
              ("cycle" . 2026)
              ("page" . 1)
              ("results" . ())
              ("retrieved-at" . "2026-07-23T00:00:00Z"))))

(defun index-reply-payload ()
  '(("document" .
     (("schema" . "org.starintel/fec@1/candidate")
      ("id" . "H2OH03116")))
    ("source-endpoint" . "/candidates/search/")
    ("cycle" . 2026)))

(defun envelope-kinds (envelopes)
  (mapcar (lambda (envelope) (getf envelope :kind)) envelopes))

(defun test-completion-and-terminal-deduplication (manifest)
  (let* ((dispatcher
           (make-deterministic-dispatcher
            manifest :now "2026-07-23T00:00:01Z"))
         (command (dispatcher-test-command)))
    (register-dispatch-actor
     dispatcher "fec-importer"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (complete-dispatch
        :message-type "org.starintel/fec@1/index-fec-record"
        :payload (index-reply-payload))))
    (submit-dispatch-envelope dispatcher command)
    (dispatcher-assert-equal '(:completed) (run-dispatcher dispatcher)
                             "command completes")
    (let ((first-outcomes (drain-dispatcher-emitted dispatcher)))
      (dispatcher-assert-equal '(:ack :reply :ack)
                               (envelope-kinds first-outcomes)
                               "completion emits accepted, reply, completed")
      (dispatcher-assert-equal
       :accepted
       (getf (getf (first first-outcomes) :payload) :status)
       "first acknowledgement accepts responsibility")
      (dispatcher-assert-equal
       :completed
       (getf (getf (third first-outcomes) :payload) :status)
       "last acknowledgement completes command")
      (dispatcher-assert-equal
       1
       (gethash "fec-importer"
                (deterministic-dispatcher-handler-count dispatcher))
       "handler runs once")
      (let ((redelivery (redeliver-command dispatcher command
                                            :message-id "command-0001-redelivery")))
        (submit-dispatch-envelope dispatcher redelivery)
        (dispatcher-assert-equal '(:duplicate) (run-dispatcher dispatcher)
                                 "terminal duplicate replays stored outcome")
        (let ((replayed (drain-dispatcher-emitted dispatcher)))
          (dispatcher-assert-equal '(:reply :ack)
                                   (envelope-kinds replayed)
                                   "duplicate replays terminal reply and completion")
          (dispatcher-assert-equal
           1
           (gethash "fec-importer"
                    (deterministic-dispatcher-handler-count dispatcher))
           "duplicate does not rerun handler")
          (values first-outcomes replayed))))))

(defun test-retry-and-redelivery (manifest)
  (let* ((dispatcher
           (make-deterministic-dispatcher
            manifest :now "2026-07-23T00:00:01Z"))
         (command
           (dispatcher-test-command
            :message-id "retry-command"
            :idempotency-key "fec:candidates:2026:retry"))
         (calls 0))
    (register-dispatch-actor
     dispatcher "fec-importer"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (incf calls)
       (if (= calls 1)
           (retry-dispatch
            :retry-after-ms 2000
            :reason "FEC rate limit")
           (complete-dispatch
            :message-type "org.starintel/fec@1/index-fec-record"
            :payload (index-reply-payload)))))
    (submit-dispatch-envelope dispatcher command)
    (dispatcher-assert-equal '(:retry) (run-dispatcher dispatcher)
                             "first attempt requests retry")
    (let ((first-attempt (drain-dispatcher-emitted dispatcher)))
      (dispatcher-assert-equal '(:ack :ack)
                               (envelope-kinds first-attempt)
                               "retry attempt emits accepted and retry ack")
      (dispatcher-assert-equal
       :retry
       (getf (getf (second first-attempt) :payload) :status)
       "retry status recorded")
      (let ((redelivery
              (redeliver-command dispatcher command
                                 :message-id "retry-command-attempt-2")))
        (dispatcher-assert-equal 2 (getf redelivery :attempt)
                                 "redelivery increments attempt")
        (dispatcher-assert-equal "retry-command"
                                 (getf redelivery :correlation-id)
                                 "redelivery preserves correlation")
        (dispatcher-assert-equal "retry-command"
                                 (getf redelivery :causation-id)
                                 "redelivery records prior attempt as cause")
        (submit-dispatch-envelope dispatcher redelivery)
        (dispatcher-assert-equal '(:completed) (run-dispatcher dispatcher)
                                 "second attempt completes")
        (let ((second-attempt (drain-dispatcher-emitted dispatcher)))
          (dispatcher-assert-equal '(:ack :reply :ack)
                                   (envelope-kinds second-attempt)
                                   "successful redelivery emits completion chain")
          (dispatcher-assert-equal 2 calls "handler runs once per real attempt")
          (values first-attempt second-attempt))))))

(defun test-in-progress-deduplication-and-cancellation (manifest)
  (let* ((dispatcher
           (make-deterministic-dispatcher
            manifest :now "2026-07-23T00:00:01Z"))
         (command
           (dispatcher-test-command
            :message-id "deferred-command"
            :idempotency-key "fec:candidates:2026:deferred")))
    (register-dispatch-actor
     dispatcher "fec-importer"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (defer-dispatch)))
    (submit-dispatch-envelope dispatcher command)
    (dispatcher-assert-equal '(:deferred) (run-dispatcher dispatcher)
                             "handler defers command")
    (drain-dispatcher-emitted dispatcher)
    (let ((duplicate
            (redeliver-command dispatcher command
                               :message-id "deferred-command-duplicate")))
      (submit-dispatch-envelope dispatcher duplicate)
      (dispatcher-assert-equal '(:in-progress) (run-dispatcher dispatcher)
                               "in-progress duplicate is not rerun")
      (let ((duplicate-outcomes (drain-dispatcher-emitted dispatcher)))
        (dispatcher-assert-equal '(:ack) (envelope-kinds duplicate-outcomes)
                                 "in-progress duplicate receives accepted ack")
        (dispatcher-assert-equal
         1
         (gethash "fec-importer"
                  (deterministic-dispatcher-handler-count dispatcher))
         "deferred duplicate does not rerun handler")))
    (let ((cancel
            (make-cancel-envelope
             command
             :message-id "cancel-deferred-command"
             :actor "fec-importer"
             :sender "dispatcher-test"
             :reason "test cancellation")))
      (dispatcher-assert-equal
       :cancel-requested
       (submit-dispatch-envelope dispatcher cancel)
       "cancellation request applied")
      (let ((cancel-outcomes (drain-dispatcher-emitted dispatcher)))
        (dispatcher-assert-equal '(:error) (envelope-kinds cancel-outcomes)
                                 "active cancellation produces terminal error")
        (dispatcher-assert-equal
         "star.cancelled"
         (getf (getf (first cancel-outcomes) :payload) :code)
         "cancellation error has stable code")
        (values duplicate-outcomes cancel-outcomes)))))

(defun test-deadline-before-handler (manifest)
  (let* ((dispatcher
           (make-deterministic-dispatcher
            manifest :now "2026-07-23T00:05:00Z"))
         (command
           (dispatcher-test-command
            :message-id "expired-command"
            :idempotency-key "fec:candidates:2026:expired"
            :deadline "2026-07-23T00:04:59Z")))
    (register-dispatch-actor
     dispatcher "fec-importer"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (complete-dispatch)))
    (submit-dispatch-envelope dispatcher command)
    (dispatcher-assert-equal '(:deadline-exceeded)
                             (run-dispatcher dispatcher)
                             "expired command fails before handler")
    (let ((outcomes (drain-dispatcher-emitted dispatcher)))
      (dispatcher-assert-equal '(:error) (envelope-kinds outcomes)
                               "deadline emits terminal error")
      (dispatcher-assert-equal
       "star.deadline-exceeded"
       (getf (getf (first outcomes) :payload) :code)
       "deadline error has stable code")
      (dispatcher-assert-equal
       nil
       (gethash "fec-importer"
                (deterministic-dispatcher-handler-count dispatcher))
       "expired command never invokes handler")
      outcomes)))

(defun test-route-validation (manifest)
  (let ((dispatcher (make-deterministic-dispatcher manifest)))
    (dispatcher-assert-true
     (dispatcher-condition-signaled-p
      'invalid-actor-error
      (lambda ()
        (register-dispatch-actor dispatcher "missing-actor"
                                 (lambda (runtime envelope)
                                   (declare (ignore runtime envelope))))))
     "unmanifested actor registration rejected")
    (register-dispatch-actor
     dispatcher "fec-importer"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (complete-dispatch)))
    (let ((command (dispatcher-test-command)))
      (setf (getf command :message-type)
            "org.starintel/fec@1/resolve-amendments")
      (dispatcher-assert-true
       (dispatcher-condition-signaled-p
        'invalid-actor-error
        (lambda ()
          (submit-dispatch-envelope dispatcher command)
          (run-dispatcher dispatcher)))
       "actor input contract enforced"))))

(defun run-deterministic-dispatcher-tests ()
  (let ((manifest (dispatcher-test-manifest)))
    (multiple-value-bind (completed replayed)
        (test-completion-and-terminal-deduplication manifest)
      (dispatcher-write-ndjson
       "star-lang-dispatch-completion.ndjson"
       manifest (append completed replayed)))
    (multiple-value-bind (first second)
        (test-retry-and-redelivery manifest)
      (dispatcher-write-ndjson
       "star-lang-dispatch-retry.ndjson"
       manifest (append first second)))
    (multiple-value-bind (duplicate cancelled)
        (test-in-progress-deduplication-and-cancellation manifest)
      (dispatcher-write-ndjson
       "star-lang-dispatch-cancel.ndjson"
       manifest (append duplicate cancelled)))
    (dispatcher-write-ndjson
     "star-lang-dispatch-deadline.ndjson"
     manifest (test-deadline-before-handler manifest))
    (test-route-validation manifest)
    (format t "Star-Lang deterministic dispatcher tests passed.~%")
    t))

(unless (run-deterministic-dispatcher-tests)
  (error "Star-Lang deterministic dispatcher tests failed."))
