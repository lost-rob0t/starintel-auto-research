(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "core-semantics-prototype.lisp" *load-truename*))
(load (merge-pathnames "canonical-json-prototype.lisp" *load-truename*))
(load (merge-pathnames "message-lifecycle-prototype.lisp" *load-truename*))
(load (merge-pathnames "message-lifecycle-bindings-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun lifecycle-condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun lifecycle-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun lifecycle-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S." label expected actual)))

(defun lifecycle-write-file (pathname content)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string content stream)))

(defun lifecycle-fec-manifest ()
  (let* ((fixture (merge-pathnames "../fixtures/fec-core.star" *load-truename*))
         (library (compile-core-library (load-star-form fixture)))
         (actor
           (compile-actor
            '(actor fec-importer
              (:runtime external
               :protocol star-message-v1
               :endpoint "rabbitmq:star.fec.ingest"
               :accepts (ingest-page)
               :produces (candidate committee filing)
               :restart permanent
               :mailbox (bounded 1024)))
            library)))
    (emit-core-manifest library (list actor))))

(defun sample-command ()
  (make-command-envelope
   :message-id "cmd-0001"
   :message-type "org.starintel/fec@1/ingest-page"
   :actor "fec-importer"
   :sender "research-test"
   :idempotency-key "fec:/candidates/search/:2026:1"
   :dataset "fec-2026"
   :reply-to "star.reply.cmd-0001"
   :sent-at "2026-07-22T23:00:00Z"
   :deadline "2026-07-22T23:05:00Z"
   :payload '(("endpoint" . "/candidates/search/")
              ("cycle" . 2026)
              ("page" . 1)
              ("results" . ())
              ("retrieved-at" . "2026-07-22T23:00:00Z"))))

(defun test-command-envelope (manifest command)
  (lifecycle-assert-true
   (validate-lifecycle-envelope manifest command)
   "command envelope validates")
  (lifecycle-assert-equal "cmd-0001" (getf command :correlation-id)
                          "command starts its correlation chain")
  (lifecycle-assert-equal
   '("fec-importer" "org.starintel/fec@1/ingest-page"
     "fec:/candidates/search/:2026:1")
   (idempotency-scope-key command)
   "idempotency scope includes actor, message type, and key")
  (let ((json (canonical-lifecycle-envelope-json manifest command)))
    (lifecycle-assert-true (search "\"kind\":\"command\"" json)
                           "command kind serialized")
    (lifecycle-assert-true (search "\"idempotency_key\"" json)
                           "idempotency key serialized")
    json))

(defun test-reply-envelope (manifest command)
  (let ((reply
          (make-reply-envelope
           command
           :message-id "reply-0001"
           :message-type "org.starintel/fec@1/index-fec-record"
           :actor "research-test"
           :sender "fec-importer"
           :payload '(("document" .
                       (("schema" . "org.starintel/fec@1/candidate")
                        ("id" . "H2OH03116")))
                      ("source-endpoint" . "/candidates/search/")
                      ("cycle" . 2026)))))
    (lifecycle-assert-equal "cmd-0001" (getf reply :correlation-id)
                            "reply preserves correlation")
    (lifecycle-assert-equal "cmd-0001" (getf reply :causation-id)
                            "reply records causation")
    (lifecycle-assert-true
     (validate-lifecycle-envelope manifest reply)
     "reply payload validates")
    (canonical-lifecycle-envelope-json manifest reply)))

(defun test-acknowledgements (manifest command)
  (let ((accepted
          (make-ack-envelope command
                             :message-id "ack-accepted"
                             :actor "research-test"
                             :sender "fec-importer"
                             :status :accepted))
        (completed
          (make-ack-envelope command
                             :message-id "ack-completed"
                             :actor "research-test"
                             :sender "fec-importer"
                             :status :completed))
        (retry
          (make-ack-envelope command
                             :message-id "ack-retry"
                             :actor "research-test"
                             :sender "fec-importer"
                             :status :retry
                             :retry-after-ms 5000
                             :reason "upstream rate limit")))
    (lifecycle-assert-equal :accepted (delivery-outcome accepted)
                            "accepted acknowledgement outcome")
    (lifecycle-assert-true (not (terminal-lifecycle-envelope-p accepted))
                           "accepted is not terminal")
    (lifecycle-assert-true (terminal-lifecycle-envelope-p completed)
                           "completed is terminal")
    (lifecycle-assert-equal :retry (delivery-outcome retry)
                            "retry acknowledgement outcome")
    (lifecycle-assert-true
     (search "\"retry_after_ms\":5000"
             (canonical-lifecycle-envelope-json manifest retry))
     "retry delay serialized")
    (lifecycle-assert-true
     (lifecycle-condition-signaled-p
      'invalid-envelope-error
      (lambda ()
        (make-ack-envelope command
                           :message-id "ack-invalid"
                           :actor "research-test"
                           :status :retry)))
     "retry acknowledgement requires delay")
    (values accepted completed retry)))

(defun test-errors (manifest command)
  (let ((retryable
          (make-error-envelope
           command
           :message-id "error-retryable"
           :actor "research-test"
           :sender "fec-importer"
           :code "fec.rate-limited"
           :message "FEC API rate limited the request"
           :retryable t
           :details '(("http_status" . 429))))
        (terminal
          (make-error-envelope
           command
           :message-id "error-terminal"
           :actor "research-test"
           :sender "fec-importer"
           :code "fec.invalid-request"
           :message "The request cannot be processed"
           :retryable nil)))
    (lifecycle-assert-equal :retry (delivery-outcome retryable)
                            "retryable error outcome")
    (lifecycle-assert-equal :failed (delivery-outcome terminal)
                            "non-retryable error outcome")
    (lifecycle-assert-true (terminal-lifecycle-envelope-p terminal)
                           "non-retryable error is terminal")
    (lifecycle-assert-true
     (search "\"retryable\":false"
             (canonical-lifecycle-envelope-json manifest terminal))
     "false retryable flag serialized as boolean")
    (values retryable terminal)))

(defun test-cancellation (manifest command)
  (let ((cancel
          (make-cancel-envelope
           command
           :message-id "cancel-0001"
           :actor "fec-importer"
           :sender "research-test"
           :reason "request no longer needed")))
    (lifecycle-assert-equal :cancel-requested (delivery-outcome cancel)
                            "cancel outcome")
    (lifecycle-assert-equal "cmd-0001"
                            (getf (getf cancel :payload) :target-message-id)
                            "cancel targets original message")
    (canonical-lifecycle-envelope-json manifest cancel)))

(defun test-invalid-command-inputs (manifest)
  (lifecycle-assert-true
   (lifecycle-condition-signaled-p
    'invalid-envelope-error
    (lambda ()
      (make-command-envelope
       :message-id "bad-command"
       :message-type "org.starintel/fec@1/ingest-page"
       :actor "fec-importer"
       :payload '())))
   "commands require idempotency keys")
  (let ((command (sample-command)))
    (setf (getf command :attempt) 0)
    (lifecycle-assert-true
     (lifecycle-condition-signaled-p
      'invalid-envelope-error
      (lambda () (validate-lifecycle-envelope manifest command)))
     "attempt zero rejected"))
  (let ((command (sample-command)))
    (setf (getf command :payload) '(("page" . 1)))
    (lifecycle-assert-true
     (lifecycle-condition-signaled-p
      'invalid-envelope-error
      (lambda () (canonical-lifecycle-envelope-json manifest command)))
     "lifecycle command payload uses message contract")))

(defun test-lifecycle-bindings ()
  (let ((python (generate-python-lifecycle-bindings))
        (typescript (generate-typescript-lifecycle-bindings)))
    (lifecycle-assert-true (search "class StarEnvelopeBase" python)
                           "Python lifecycle envelope generated")
    (lifecycle-assert-true (search "AckStatus = Literal" python)
                           "Python ack status generated")
    (lifecycle-assert-true (search "export interface StarEnvelopeBase" typescript)
                           "TypeScript lifecycle envelope generated")
    (lifecycle-assert-true (search "star.protocol/error@1" typescript)
                           "TypeScript error envelope generated")
    (values python typescript)))

(defun run-message-lifecycle-tests ()
  (let* ((manifest (lifecycle-fec-manifest))
         (command (sample-command))
         (command-json (test-command-envelope manifest command))
         (reply-json (test-reply-envelope manifest command))
         (cancel-json (test-cancellation manifest command)))
    (multiple-value-bind (accepted completed retry)
        (test-acknowledgements manifest command)
      (declare (ignore completed retry))
      (lifecycle-write-file
       "star-lang-lifecycle-ack.json"
       (canonical-lifecycle-envelope-json manifest accepted)))
    (multiple-value-bind (retryable terminal)
        (test-errors manifest command)
      (declare (ignore retryable))
      (lifecycle-write-file
       "star-lang-lifecycle-error.json"
       (canonical-lifecycle-envelope-json manifest terminal)))
    (test-invalid-command-inputs manifest)
    (multiple-value-bind (python typescript)
        (test-lifecycle-bindings)
      (lifecycle-write-file "star_protocol.py" python)
      (lifecycle-write-file "star_protocol.ts" typescript))
    (lifecycle-write-file "star-lang-lifecycle-command.json" command-json)
    (lifecycle-write-file "star-lang-lifecycle-reply.json" reply-json)
    (lifecycle-write-file "star-lang-lifecycle-cancel.json" cancel-json)
    (format t "Star-Lang message lifecycle tests passed.~%")
    t))

(unless (run-message-lifecycle-tests)
  (error "Star-Lang message lifecycle tests failed."))
