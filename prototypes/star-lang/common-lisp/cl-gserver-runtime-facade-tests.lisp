(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "core-semantics-prototype.lisp" *load-truename*))
(load (merge-pathnames "canonical-json-prototype.lisp" *load-truename*))
(load (merge-pathnames "message-lifecycle-prototype.lisp" *load-truename*))
(load (merge-pathnames "deterministic-dispatcher-prototype.lisp" *load-truename*))
(load (merge-pathnames "deferred-dispatch-completion-prototype.lisp" *load-truename*))
(load (merge-pathnames "transport-port-prototype.lisp" *load-truename*))
(load (merge-pathnames "dispatcher-transport-adapter-prototype.lisp" *load-truename*))
(load (merge-pathnames "cl-gserver-runtime-facade-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun runtime-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S."
          label expected actual)))

(defun runtime-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun runtime-condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defstruct (fake-runtime-actor
            (:constructor make-fake-runtime-actor (&key name receive)))
  name
  receive
  (stopped-p nil))

(defstruct (fake-cl-gserver-system
            (:constructor make-fake-cl-gserver-system
                (&key (tell-failures 0))))
  (actors (make-hash-table :test #'equal))
  (mailbox '())
  (actor-of-calls '())
  (tell-calls '())
  (stop-calls '())
  (tell-failures-remaining 0)
  (shutdown-p nil))

(defun fake-runtime-actor-of (system name receive)
  (when (gethash name (fake-cl-gserver-system-actors system))
    (error "Actor already exists: ~A" name))
  (let ((actor (make-fake-runtime-actor :name name :receive receive)))
    (setf (gethash name (fake-cl-gserver-system-actors system)) actor)
    (setf (fake-cl-gserver-system-actor-of-calls system)
          (append (fake-cl-gserver-system-actor-of-calls system)
                  (list name)))
    actor))

(defun fake-runtime-tell (system actor message sender)
  (when (> (fake-cl-gserver-system-tell-failures-remaining system) 0)
    (decf (fake-cl-gserver-system-tell-failures-remaining system))
    (error "Injected fake cl-gserver tell failure."))
  (unless (and (fake-runtime-actor-p actor)
               (not (fake-runtime-actor-stopped-p actor)))
    (error "Cannot tell stopped or invalid actor."))
  (setf (fake-cl-gserver-system-tell-calls system)
        (append (fake-cl-gserver-system-tell-calls system)
                (list (list :actor (fake-runtime-actor-name actor)
                            :message (copy-tree message)
                            :sender sender))))
  (setf (fake-cl-gserver-system-mailbox system)
        (append (fake-cl-gserver-system-mailbox system)
                (list (list :actor actor
                            :message message
                            :sender sender))))
  :sent)

(defun fake-runtime-stop (system actor)
  (setf (fake-runtime-actor-stopped-p actor) t)
  (setf (fake-cl-gserver-system-stop-calls system)
        (append (fake-cl-gserver-system-stop-calls system)
                (list (fake-runtime-actor-name actor))))
  :stopped)

(defun fake-runtime-shutdown (system)
  (setf (fake-cl-gserver-system-shutdown-p system) t)
  :shutdown)

(defun bind-fake-cl-gserver-runtime-port (system)
  (make-cl-gserver-runtime-port
   :actor-of (lambda (context name receive)
               (unless (eq context system)
                 (error "Unexpected fake runtime context."))
               (fake-runtime-actor-of system name receive))
   :tell (lambda (actor message sender)
           (fake-runtime-tell system actor message sender))
   :stop (lambda (context actor)
           (unless (eq context system)
             (error "Unexpected fake runtime context."))
           (fake-runtime-stop system actor))
   :shutdown (lambda (context)
               (unless (eq context system)
                 (error "Unexpected fake runtime context."))
               (fake-runtime-shutdown system))))

(defun run-fake-runtime-next (system)
  (let ((entry (first (fake-cl-gserver-system-mailbox system))))
    (when entry
      (setf (fake-cl-gserver-system-mailbox system)
            (rest (fake-cl-gserver-system-mailbox system)))
      (funcall (fake-runtime-actor-receive (getf entry :actor))
               (getf entry :message)))))

(defun run-fake-runtime (system &key (limit 100))
  (loop repeat limit
        while (fake-cl-gserver-system-mailbox system)
        collect (run-fake-runtime-next system)))

(defun runtime-test-library ()
  (let ((fixture (merge-pathnames "../fixtures/fec-core.star" *load-truename*)))
    (compile-core-library (load-star-form fixture))))

(defun runtime-test-native-contract (library)
  (compile-actor
   '(actor fec-native-importer
     (:runtime native
      :accepts (ingest-page)
      :produces (index-fec-record)
      :handler fec-native-handler
      :restart permanent
      :mailbox (bounded 128)))
   library))

(defun runtime-test-command (&key
                             (message-id "runtime-command-1")
                             (idempotency-key "runtime:fec:1"))
  (make-command-envelope
   :message-id message-id
   :message-type "org.starintel/fec@1/ingest-page"
   :actor "fec-native-importer"
   :sender "runtime-test"
   :idempotency-key idempotency-key
   :dataset "fec-2026"
   :payload '(("endpoint" . "/candidates/search/")
              ("cycle" . 2026)
              ("page" . 1)
              ("results" . ())
              ("retrieved-at" . "2026-07-23T00:00:00Z"))))

(defun runtime-index-payload ()
  '(("document" .
     (("schema" . "org.starintel/fec@1/candidate")
      ("id" . "H2OH03116")))
    ("source-endpoint" . "/candidates/search/")
    ("cycle" . 2026)))

(defun runtime-envelope-kinds (envelopes)
  (mapcar (lambda (envelope) (getf envelope :kind)) envelopes))

(defun runtime-settlement-actions (transport)
  (mapcar (lambda (settlement) (getf settlement :action))
          (fake-transport-settlements transport)))

(defun make-runtime-test-environment
    (&key handler (tell-failures 0) (retry-delay-ms 1000))
  (let* ((library (runtime-test-library))
         (contract (runtime-test-native-contract library))
         (manifest (emit-core-manifest library (list contract)))
         (dispatcher
           (make-deterministic-dispatcher
            manifest :now "2026-07-23T00:00:01Z"))
         (transport (make-fake-transport))
         (transport-adapter
           (make-transport-dispatch-adapter
            dispatcher
            (bind-fake-transport-port transport)))
         (system
           (make-fake-cl-gserver-system
            :tell-failures tell-failures))
         (facade
           (make-cl-gserver-runtime-facade
            :context system
            :runtime-port (bind-fake-cl-gserver-runtime-port system)
            :dispatcher dispatcher
            :transport-adapter transport-adapter
            :native-contracts (list contract)
            :handlers
            (list (cons "fec-native-handler"
                        (or handler
                            (lambda (command)
                              (declare (ignore command))
                              (complete-dispatch
                               :message-type
                               "org.starintel/fec@1/index-fec-record"
                               :payload (runtime-index-payload)))))
            :retry-delay-ms retry-delay-ms)))
    (start-cl-gserver-runtime-facade facade)
    (values library contract manifest dispatcher transport transport-adapter
            system facade)))

(defun test-runtime-start-and-completion ()
  (let ((calls 0))
    (multiple-value-bind
          (library contract manifest dispatcher transport adapter system facade)
        (make-runtime-test-environment
         :handler
         (lambda (command)
           (declare (ignore command))
           (incf calls)
           (complete-dispatch
            :message-type "org.starintel/fec@1/index-fec-record"
            :payload (runtime-index-payload))))
      (declare (ignore library contract manifest dispatcher))
      (runtime-assert-equal
       '("star-runtime-coordinator" "fec-native-importer")
       (fake-cl-gserver-system-actor-of-calls system)
       "runtime creates coordinator and native actor through actor-of")
      (fake-transport-submit transport (runtime-test-command))
      (runtime-assert-equal :held (run-transport-adapter-next adapter)
                            "transport delivery is held after async tell")
      (runtime-assert-equal '(:ack)
                            (runtime-envelope-kinds
                             (fake-transport-published transport))
                            "accepted publishes before native completion")
      (runtime-assert-equal 1
                            (cl-gserver-runtime-facade-job-count facade)
                            "runtime job remains pending")
      (runtime-assert-equal 1
                            (transport-dispatch-adapter-held-count adapter)
                            "source delivery remains held")
      (runtime-assert-equal :result-sent (run-fake-runtime-next system)
                            "native actor handles runtime job")
      (runtime-assert-equal :acked (run-fake-runtime-next system)
                            "coordinator completes and settles delivery")
      (runtime-assert-equal 1 calls "native handler runs once")
      (runtime-assert-equal 0
                            (cl-gserver-runtime-facade-job-count facade)
                            "completed job clears")
      (runtime-assert-equal 0
                            (transport-dispatch-adapter-held-count adapter)
                            "completed delivery clears held state")
      (runtime-assert-equal
       '(:ack :reply :ack)
       (runtime-envelope-kinds (fake-transport-published transport))
       "completion publishes accepted, reply, completed")
      (runtime-assert-equal '(:ack)
                            (runtime-settlement-actions transport)
                            "source delivery acknowledged after result publication")
      (shutdown-cl-gserver-runtime-facade facade)
      (runtime-assert-equal
       '("fec-native-importer" "star-runtime-coordinator")
       (fake-cl-gserver-system-stop-calls system)
       "shutdown stops native actor and coordinator")
      (runtime-assert-true
       (fake-cl-gserver-system-shutdown-p system)
       "runtime system shutdown invoked"))))

(defun test-runtime-retry-and-redelivery ()
  (let ((calls 0))
    (multiple-value-bind
          (library contract manifest dispatcher transport adapter system facade)
        (make-runtime-test-environment
         :handler
         (lambda (command)
           (declare (ignore command))
           (incf calls)
           (if (= calls 1)
               (retry-dispatch :retry-after-ms 1500
                               :reason "native rate limit")
               (complete-dispatch
                :message-type "org.starintel/fec@1/index-fec-record"
                :payload (runtime-index-payload)))))
      (declare (ignore library contract manifest dispatcher facade))
      (fake-transport-submit
       transport
       (runtime-test-command
        :message-id "runtime-retry-1"
        :idempotency-key "runtime:fec:retry"))
      (runtime-assert-equal :held (run-transport-adapter-next adapter)
                            "first runtime attempt is held")
      (run-fake-runtime system)
      (runtime-assert-equal '(:requeue)
                            (runtime-settlement-actions transport)
                            "runtime retry requeues source delivery")
      (let* ((delivery (first (fake-transport-inbound transport)))
             (redelivery (transport-delivery-envelope delivery)))
        (runtime-assert-equal 2 (getf redelivery :attempt)
                              "runtime retry increments Star-Lang attempt")
        (runtime-assert-equal "runtime-retry-1"
                              (getf redelivery :correlation-id)
                              "runtime retry preserves correlation"))
      (runtime-assert-equal nil (run-transport-adapter-next adapter)
                            "runtime retry remains delayed")
      (advance-fake-transport-clock transport 1500)
      (runtime-assert-equal :held (run-transport-adapter-next adapter)
                            "second runtime attempt is delivered")
      (run-fake-runtime system)
      (runtime-assert-equal 2 calls
                            "native actor executes once for each explicit attempt")
      (runtime-assert-equal '(:requeue :ack)
                            (runtime-settlement-actions transport)
                            "retry then completion settlements")
      (runtime-assert-equal
       '(:ack :ack :ack :reply :ack)
       (runtime-envelope-kinds (fake-transport-published transport))
       "runtime retry and completion lifecycle sequence"))))

(defun test-runtime-tell-failure-becomes-explicit-retry ()
  (multiple-value-bind
        (library contract manifest dispatcher transport adapter system facade)
      (make-runtime-test-environment
       :tell-failures 1
       :retry-delay-ms 750)
    (declare (ignore library contract manifest dispatcher facade))
    (fake-transport-submit
     transport
     (runtime-test-command
      :message-id "runtime-tell-failure"
      :idempotency-key "runtime:fec:tell-failure"))
    (runtime-assert-equal :requeued (run-transport-adapter-next adapter)
                          "tell failure becomes Star-Lang retry")
    (runtime-assert-equal 0
                          (length (fake-cl-gserver-system-mailbox system))
                          "failed tell queues no runtime message")
    (runtime-assert-equal '(:requeue)
                          (runtime-settlement-actions transport)
                          "tell failure requeues through transport")
    (runtime-assert-equal
     '(:ack :ack)
     (runtime-envelope-kinds (fake-transport-published transport))
     "dispatcher acceptance and retry acknowledgement publish")
    (let* ((delivery (first (fake-transport-inbound transport)))
           (redelivery (transport-delivery-envelope delivery)))
      (runtime-assert-equal 750
                            (transport-delivery-visible-at delivery)
                            "runtime tell retry uses configured delay")
      (runtime-assert-equal 2 (getf redelivery :attempt)
                            "tell retry creates next attempt"))))

(defun test-runtime-handler-failure-is-terminal ()
  (multiple-value-bind
        (library contract manifest dispatcher transport adapter system facade)
      (make-runtime-test-environment
       :handler
       (lambda (command)
         (declare (ignore command))
         (error "native handler exploded")))
    (declare (ignore library contract manifest dispatcher facade))
    (fake-transport-submit
     transport
     (runtime-test-command
      :message-id "runtime-handler-error"
      :idempotency-key "runtime:fec:handler-error"))
    (runtime-assert-equal :held (run-transport-adapter-next adapter)
                          "failing native handler begins asynchronously")
    (run-fake-runtime system)
    (runtime-assert-equal '(:ack :error)
                          (runtime-envelope-kinds
                           (fake-transport-published transport))
                          "handler failure publishes terminal error")
    (runtime-assert-equal "star.native-handler-error"
                          (getf (getf (second
                                      (fake-transport-published transport))
                                     :payload)
                                :code)
                          "handler failure has stable code")
    (runtime-assert-equal '(:ack)
                          (runtime-settlement-actions transport)
                          "terminal handler failure acknowledges source")))

(defun test-runtime-late-result-after-cancellation ()
  (multiple-value-bind
        (library contract manifest dispatcher transport adapter system facade)
      (make-runtime-test-environment)
    (declare (ignore library contract manifest dispatcher))
    (let ((command
            (runtime-test-command
             :message-id "runtime-cancel-race"
             :idempotency-key "runtime:fec:cancel-race")))
      (fake-transport-submit transport command)
      (runtime-assert-equal :held (run-transport-adapter-next adapter)
                            "runtime command is held before actor execution")
      (fake-transport-submit
       transport
       (make-cancel-envelope
        command
        :message-id "runtime-cancel-control"
        :actor "fec-native-importer"
        :sender "runtime-test"
        :reason "operator request"))
      (runtime-assert-equal :acked (run-transport-adapter-next adapter)
                            "cancel settles control and held source")
      (runtime-assert-equal 1
                            (cl-gserver-runtime-facade-job-count facade)
                            "runtime job remains until late actor result arrives")
      (runtime-assert-equal :result-sent (run-fake-runtime-next system)
                            "cancelled actor message may still execute cooperatively")
      (runtime-assert-equal :late-terminal (run-fake-runtime-next system)
                            "late result cannot reopen terminal command")
      (runtime-assert-equal 0
                            (cl-gserver-runtime-facade-job-count facade)
                            "late terminal result clears runtime job")
      (runtime-assert-equal '(:ack :error)
                            (runtime-envelope-kinds
                             (fake-transport-published transport))
                            "late result emits no new lifecycle output")
      (runtime-assert-equal '(:ack :ack)
                            (runtime-settlement-actions transport)
                            "cancel acknowledges held and control deliveries"))))

(defun test-runtime-contract-requires-handler ()
  (let* ((library (runtime-test-library))
         (contract (runtime-test-native-contract library))
         (manifest (emit-core-manifest library (list contract)))
         (dispatcher (make-deterministic-dispatcher manifest))
         (transport (make-fake-transport))
         (adapter
           (make-transport-dispatch-adapter
            dispatcher (bind-fake-transport-port transport)))
         (system (make-fake-cl-gserver-system)))
    (runtime-assert-true
     (runtime-condition-signaled-p
      'cl-gserver-runtime-error
      (lambda ()
        (make-cl-gserver-runtime-facade
         :context system
         :runtime-port (bind-fake-cl-gserver-runtime-port system)
         :dispatcher dispatcher
         :transport-adapter adapter
         :native-contracts (list contract)
         :handlers '())))
     "native contract cannot start without registered handler")))

(defun run-cl-gserver-runtime-facade-tests ()
  (test-runtime-start-and-completion)
  (test-runtime-retry-and-redelivery)
  (test-runtime-tell-failure-becomes-explicit-retry)
  (test-runtime-handler-failure-is-terminal)
  (test-runtime-late-result-after-cancellation)
  (test-runtime-contract-requires-handler)
  (format t "Star-Lang cl-gserver runtime facade tests passed.~%")
  t)

(unless (run-cl-gserver-runtime-facade-tests)
  (error "Star-Lang cl-gserver runtime facade tests failed."))