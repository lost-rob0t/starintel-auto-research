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

(defun runtime-test-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S."
          label expected actual)))

(defun runtime-test-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun runtime-test-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defstruct fake-runtime-actor
  name
  receive
  (stopped-p nil))

(defstruct (fake-runtime-system
            (:constructor make-fake-runtime-system
                (&key (tell-failures-remaining 0))))
  (actors (make-hash-table :test #'equal))
  (mailbox '())
  (actor-of-calls '())
  (tell-calls '())
  (stop-calls '())
  (tell-failures-remaining 0)
  (shutdown-p nil))

(defun fake-actor-of (system name receive)
  (when (gethash name (fake-runtime-system-actors system))
    (error "Actor already exists: ~A" name))
  (let ((actor (make-fake-runtime-actor :name name :receive receive)))
    (setf (gethash name (fake-runtime-system-actors system)) actor)
    (setf (fake-runtime-system-actor-of-calls system)
          (append (fake-runtime-system-actor-of-calls system)
                  (list name)))
    actor))

(defun fake-tell (system actor message sender)
  (when (> (fake-runtime-system-tell-failures-remaining system) 0)
    (decf (fake-runtime-system-tell-failures-remaining system))
    (error "Injected tell failure."))
  (unless (and (fake-runtime-actor-p actor)
               (not (fake-runtime-actor-stopped-p actor)))
    (error "Cannot tell invalid or stopped actor."))
  (setf (fake-runtime-system-tell-calls system)
        (append (fake-runtime-system-tell-calls system)
                (list (list :actor (fake-runtime-actor-name actor)
                            :message (copy-tree message)
                            :sender sender))))
  (setf (fake-runtime-system-mailbox system)
        (append (fake-runtime-system-mailbox system)
                (list (list :actor actor :message message))))
  :sent)

(defun fake-stop (system actor)
  (setf (fake-runtime-actor-stopped-p actor) t)
  (setf (fake-runtime-system-stop-calls system)
        (append (fake-runtime-system-stop-calls system)
                (list (fake-runtime-actor-name actor))))
  :stopped)

(defun fake-shutdown (system)
  (setf (fake-runtime-system-shutdown-p system) t)
  :shutdown)

(defun fake-runtime-port (system)
  (make-cl-gserver-runtime-port
   :actor-of
   (lambda (context name receive)
     (unless (eq context system)
       (error "Unexpected runtime context."))
     (fake-actor-of system name receive))
   :tell
   (lambda (actor message sender)
     (fake-tell system actor message sender))
   :stop
   (lambda (context actor)
     (unless (eq context system)
       (error "Unexpected runtime context."))
     (fake-stop system actor))
   :shutdown
   (lambda (context)
     (unless (eq context system)
       (error "Unexpected runtime context."))
     (fake-shutdown system))))

(defun fake-runtime-step (system)
  (let ((entry (first (fake-runtime-system-mailbox system))))
    (when entry
      (setf (fake-runtime-system-mailbox system)
            (rest (fake-runtime-system-mailbox system)))
      (funcall
       (fake-runtime-actor-receive (getf entry :actor))
       (getf entry :message)))))

(defun fake-runtime-drain (system &key (limit 100))
  (loop repeat limit
        while (fake-runtime-system-mailbox system)
        collect (fake-runtime-step system)))

(defun runtime-library ()
  (compile-core-library
   (load-star-form
    (merge-pathnames "../fixtures/fec-core.star" *load-truename*))))

(defun runtime-native-contract (library)
  (compile-actor
   '(actor fec-native-importer
     (:runtime native
      :accepts (ingest-page)
      :produces (index-fec-record)
      :handler fec-native-handler
      :restart permanent
      :mailbox (bounded 128)))
   library))

(defun runtime-command (&key
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

(defun runtime-index-result ()
  (complete-dispatch
   :message-type "org.starintel/fec@1/index-fec-record"
   :payload
   '(("document" .
      (("schema" . "org.starintel/fec@1/candidate")
       ("id" . "H2OH03116")))
     ("source-endpoint" . "/candidates/search/")
     ("cycle" . 2026))))

(defun envelope-kinds (envelopes)
  (mapcar (lambda (envelope) (getf envelope :kind)) envelopes))

(defun settlement-actions (transport)
  (mapcar (lambda (settlement) (getf settlement :action))
          (fake-transport-settlements transport)))

(defstruct runtime-test-environment
  manifest
  dispatcher
  transport
  adapter
  system
  facade)

(defun make-runtime-environment
    (&key handler (tell-failures 0) (retry-delay-ms 1000))
  (let* ((library (runtime-library))
         (contract (runtime-native-contract library))
         (manifest (emit-core-manifest library (list contract)))
         (dispatcher
           (make-deterministic-dispatcher
            manifest :now "2026-07-23T00:00:01Z"))
         (transport (make-fake-transport))
         (adapter
           (make-transport-dispatch-adapter
            dispatcher (bind-fake-transport-port transport)))
         (system
           (make-fake-runtime-system
            :tell-failures-remaining tell-failures))
         (facade
           (make-cl-gserver-runtime-facade
            :context system
            :runtime-port (fake-runtime-port system)
            :dispatcher dispatcher
            :transport-adapter adapter
            :native-contracts (list contract)
            :handlers
            (list
             (cons "fec-native-handler"
                   (or handler
                       (lambda (command)
                         (declare (ignore command))
                         (runtime-index-result)))))
            :retry-delay-ms retry-delay-ms)))
    (start-cl-gserver-runtime-facade facade)
    (make-runtime-test-environment
     :manifest manifest
     :dispatcher dispatcher
     :transport transport
     :adapter adapter
     :system system
     :facade facade)))

(defun test-runtime-completion ()
  (let ((calls 0))
    (let* ((environment
             (make-runtime-environment
              :handler
              (lambda (command)
                (declare (ignore command))
                (incf calls)
                (runtime-index-result))))
           (transport (runtime-test-environment-transport environment))
           (adapter (runtime-test-environment-adapter environment))
           (system (runtime-test-environment-system environment))
           (facade (runtime-test-environment-facade environment)))
      (runtime-test-equal
       '("star-runtime-coordinator" "fec-native-importer")
       (fake-runtime-system-actor-of-calls system)
       "actor-of creates coordinator and native actor")
      (fake-transport-submit transport (runtime-command))
      (runtime-test-equal :held
                          (run-transport-adapter-next adapter)
                          "async native command holds source delivery")
      (runtime-test-equal
       '(:ack)
       (envelope-kinds (fake-transport-published transport))
       "accepted publishes before native result")
      (runtime-test-equal 1
                          (cl-gserver-runtime-facade-job-count facade)
                          "runtime job is pending")
      (runtime-test-equal :result-sent
                          (fake-runtime-step system)
                          "native actor sends result to coordinator")
      (runtime-test-equal :acked
                          (fake-runtime-step system)
                          "coordinator publishes result and settles source")
      (runtime-test-equal 1 calls "native handler executes once")
      (runtime-test-equal 0
                          (cl-gserver-runtime-facade-job-count facade)
                          "completed runtime job clears")
      (runtime-test-equal
       '(:ack :reply :ack)
       (envelope-kinds (fake-transport-published transport))
       "completion lifecycle sequence")
      (runtime-test-equal
       '(:ack)
       (settlement-actions transport)
       "source acknowledges after result publication")
      (shutdown-cl-gserver-runtime-facade facade)
      (runtime-test-true
       (fake-runtime-system-shutdown-p system)
       "runtime shutdown invoked"))))

(defun test-runtime-retry ()
  (let ((calls 0))
    (let* ((environment
             (make-runtime-environment
              :handler
              (lambda (command)
                (declare (ignore command))
                (incf calls)
                (if (= calls 1)
                    (retry-dispatch
                     :retry-after-ms 1500
                     :reason "native rate limit")
                    (runtime-index-result)))))
           (transport (runtime-test-environment-transport environment))
           (adapter (runtime-test-environment-adapter environment))
           (system (runtime-test-environment-system environment)))
      (fake-transport-submit
       transport
       (runtime-command
        :message-id "runtime-retry-1"
        :idempotency-key "runtime:fec:retry"))
      (runtime-test-equal :held
                          (run-transport-adapter-next adapter)
                          "first runtime attempt holds source")
      (fake-runtime-drain system)
      (runtime-test-equal
       '(:requeue)
       (settlement-actions transport)
       "native retry requeues source")
      (let* ((delivery (first (fake-transport-inbound transport)))
             (redelivery (transport-delivery-envelope delivery)))
        (runtime-test-equal 2 (getf redelivery :attempt)
                            "runtime retry increments attempt")
        (runtime-test-equal "runtime-retry-1"
                            (getf redelivery :correlation-id)
                            "runtime retry preserves correlation"))
      (advance-fake-transport-clock transport 1500)
      (runtime-test-equal :held
                          (run-transport-adapter-next adapter)
                          "second runtime attempt is delivered")
      (fake-runtime-drain system)
      (runtime-test-equal 2 calls
                          "native handler executes once per explicit attempt")
      (runtime-test-equal
       '(:requeue :ack)
       (settlement-actions transport)
       "retry then completion settlements"))))

(defun test-runtime-tell-failure ()
  (let* ((environment
           (make-runtime-environment
            :tell-failures 1
            :retry-delay-ms 750))
         (transport (runtime-test-environment-transport environment))
         (adapter (runtime-test-environment-adapter environment))
         (system (runtime-test-environment-system environment)))
    (fake-transport-submit
     transport
     (runtime-command
      :message-id "runtime-tell-failure"
      :idempotency-key "runtime:fec:tell-failure"))
    (runtime-test-equal :requeued
                        (run-transport-adapter-next adapter)
                        "failed tell becomes explicit retry")
    (runtime-test-equal nil
                        (fake-runtime-system-mailbox system)
                        "failed tell queues no native message")
    (runtime-test-equal
     '(:ack :ack)
     (envelope-kinds (fake-transport-published transport))
     "accepted and retry acknowledgements publish")
    (let ((delivery (first (fake-transport-inbound transport))))
      (runtime-test-equal 750
                          (transport-delivery-visible-at delivery)
                          "tell retry uses configured delay"))))

(defun test-runtime-handler-error ()
  (let* ((environment
           (make-runtime-environment
            :handler
            (lambda (command)
              (declare (ignore command))
              (error "native handler exploded"))))
         (transport (runtime-test-environment-transport environment))
         (adapter (runtime-test-environment-adapter environment))
         (system (runtime-test-environment-system environment)))
    (fake-transport-submit
     transport
     (runtime-command
      :message-id "runtime-handler-error"
      :idempotency-key "runtime:fec:handler-error"))
    (runtime-test-equal :held
                        (run-transport-adapter-next adapter)
                        "handler execution is asynchronous")
    (fake-runtime-drain system)
    (runtime-test-equal
     '(:ack :error)
     (envelope-kinds (fake-transport-published transport))
     "handler condition becomes terminal lifecycle error")
    (runtime-test-equal
     "star.native-handler-error"
     (getf (getf (second (fake-transport-published transport))
                 :payload)
           :code)
     "native handler error has stable code")
    (runtime-test-equal
     '(:ack)
     (settlement-actions transport)
     "terminal native failure acknowledges source")))

(defun test-runtime-cancel-race ()
  (let* ((environment (make-runtime-environment))
         (transport (runtime-test-environment-transport environment))
         (adapter (runtime-test-environment-adapter environment))
         (system (runtime-test-environment-system environment))
         (facade (runtime-test-environment-facade environment))
         (command
           (runtime-command
            :message-id "runtime-cancel-race"
            :idempotency-key "runtime:fec:cancel-race")))
    (fake-transport-submit transport command)
    (runtime-test-equal :held
                        (run-transport-adapter-next adapter)
                        "runtime job is held before actor step")
    (fake-transport-submit
     transport
     (make-cancel-envelope
      command
      :message-id "runtime-cancel-control"
      :actor "fec-native-importer"
      :sender "runtime-test"
      :reason "operator request"))
    (runtime-test-equal :acked
                        (run-transport-adapter-next adapter)
                        "cancel settles held and control deliveries")
    (runtime-test-equal 1
                        (cl-gserver-runtime-facade-job-count facade)
                        "job remains until late result arrives")
    (runtime-test-equal :result-sent
                        (fake-runtime-step system)
                        "cooperative actor may still produce late result")
    (runtime-test-equal :late-terminal
                        (fake-runtime-step system)
                        "late result cannot reopen cancelled command")
    (runtime-test-equal 0
                        (cl-gserver-runtime-facade-job-count facade)
                        "late terminal result clears job")
    (runtime-test-equal
     '(:ack :error)
     (envelope-kinds (fake-transport-published transport))
     "late result emits no new lifecycle output")))

(defun test-runtime-handler-registration ()
  (let* ((library (runtime-library))
         (contract (runtime-native-contract library))
         (manifest (emit-core-manifest library (list contract)))
         (dispatcher (make-deterministic-dispatcher manifest))
         (transport (make-fake-transport))
         (adapter
           (make-transport-dispatch-adapter
            dispatcher (bind-fake-transport-port transport)))
         (system (make-fake-runtime-system)))
    (runtime-test-true
     (runtime-test-signaled-p
      'cl-gserver-runtime-error
      (lambda ()
        (make-cl-gserver-runtime-facade
         :context system
         :runtime-port (fake-runtime-port system)
         :dispatcher dispatcher
         :transport-adapter adapter
         :native-contracts (list contract)
         :handlers '())))
     "native actor requires registered handler")))

(defun run-cl-gserver-runtime-tests ()
  (test-runtime-completion)
  (test-runtime-retry)
  (test-runtime-tell-failure)
  (test-runtime-handler-error)
  (test-runtime-cancel-race)
  (test-runtime-handler-registration)
  (format t "Star-Lang cl-gserver runtime facade tests passed.~%")
  t)

(unless (run-cl-gserver-runtime-tests)
  (error "Star-Lang cl-gserver runtime facade tests failed."))