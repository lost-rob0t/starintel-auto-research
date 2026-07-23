(in-package #:star-lang.core-surface.prototype)

(export '(cl-gserver-runtime-facade-actor
          cl-gserver-runtime-facade-job-count
          make-cl-gserver-runtime-facade
          make-cl-gserver-runtime-port
          shutdown-cl-gserver-runtime-facade
          start-cl-gserver-runtime-facade))

(define-condition cl-gserver-runtime-error (star-lang-core-error) ())

(defstruct (cl-gserver-runtime-port
            (:constructor %make-cl-gserver-runtime-port))
  actor-of-fn
  tell-fn
  stop-fn
  shutdown-fn)

(defun make-cl-gserver-runtime-port (&key actor-of tell stop shutdown)
  (dolist (operation
           (list (cons "actor-of" actor-of)
                 (cons "tell" tell)
                 (cons "stop" stop)
                 (cons "shutdown" shutdown)))
    (unless (functionp (cdr operation))
      (fail 'cl-gserver-runtime-error
            "cl-gserver runtime operation ~A must be a function."
            (car operation))))
  (%make-cl-gserver-runtime-port
   :actor-of-fn actor-of
   :tell-fn tell
   :stop-fn stop
   :shutdown-fn shutdown))

(defun runtime-operation-error (operation condition)
  (fail 'cl-gserver-runtime-error
        "cl-gserver runtime operation ~A failed: ~A"
        operation condition))

(defun runtime-actor-of (port context name receive)
  (handler-case
      (funcall (cl-gserver-runtime-port-actor-of-fn port)
               context name receive)
    (cl-gserver-runtime-error (condition) (error condition))
    (error (condition) (runtime-operation-error "actor-of" condition))))

(defun runtime-tell (port actor message &optional sender)
  (handler-case
      (funcall (cl-gserver-runtime-port-tell-fn port)
               actor message sender)
    (cl-gserver-runtime-error (condition) (error condition))
    (error (condition) (runtime-operation-error "tell" condition))))

(defun runtime-stop (port context actor)
  (handler-case
      (funcall (cl-gserver-runtime-port-stop-fn port) context actor)
    (cl-gserver-runtime-error (condition) (error condition))
    (error (condition) (runtime-operation-error "stop" condition))))

(defun runtime-shutdown (port context)
  (handler-case
      (funcall (cl-gserver-runtime-port-shutdown-fn port) context)
    (cl-gserver-runtime-error (condition) (error condition))
    (error (condition) (runtime-operation-error "shutdown" condition))))

(defstruct (cl-gserver-runtime-job
            (:constructor make-cl-gserver-runtime-job
                (&key id actor-name command)))
  id
  actor-name
  command)

(defstruct (cl-gserver-runtime-facade
            (:constructor %make-cl-gserver-runtime-facade))
  context
  runtime-port
  dispatcher
  transport-adapter
  (native-contracts '())
  (handlers (make-hash-table :test #'equal))
  (actors (make-hash-table :test #'equal))
  coordinator
  (jobs (make-hash-table :test #'equal))
  (sequence 0)
  (retry-delay-ms 1000)
  (started-p nil))

(defun native-runtime-contract-p (contract)
  (and (listp contract)
       (eq (getf contract :kind) :actor)
       (eq (getf contract :runtime) :native)))

(defun actor-contract-in-manifest (manifest actor-name)
  (find actor-name
        (getf manifest :actors)
        :key (lambda (actor) (getf actor :name))
        :test #'string=))

(defun make-handler-table (handlers)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (entry handlers)
      (unless (and (consp entry)
                   (stringp (car entry))
                   (functionp (cdr entry)))
        (fail 'cl-gserver-runtime-error
              "Runtime handlers must be (handler-name . function) pairs."))
      (when (gethash (car entry) table)
        (fail 'cl-gserver-runtime-error
              "Duplicate runtime handler ~A."
              (car entry)))
      (setf (gethash (car entry) table) (cdr entry)))
    table))

(defun validate-native-runtime-contracts (dispatcher contracts handlers)
  (let ((manifest (deterministic-dispatcher-manifest dispatcher)))
    (dolist (contract contracts)
      (unless (native-runtime-contract-p contract)
        (fail 'cl-gserver-runtime-error
              "Runtime facade accepts compiled native actor contracts only."))
      (let* ((actor-name (getf contract :name))
             (portable (actor-contract-in-manifest manifest actor-name))
             (handler-name (getf contract :handler)))
        (unless (and portable (eq (getf portable :runtime) :native))
          (fail 'cl-gserver-runtime-error
                "Native actor ~A is absent from the portable manifest."
                actor-name))
        (unless (gethash handler-name handlers)
          (fail 'cl-gserver-runtime-error
                "Native actor ~A references unregistered handler ~A."
                actor-name handler-name))))
    contracts))

(defun make-cl-gserver-runtime-facade
    (&key context runtime-port dispatcher transport-adapter
          native-contracts handlers (retry-delay-ms 1000))
  (unless (cl-gserver-runtime-port-p runtime-port)
    (fail 'cl-gserver-runtime-error
          "Runtime facade requires a cl-gserver runtime port."))
  (unless (deterministic-dispatcher-p dispatcher)
    (fail 'cl-gserver-runtime-error
          "Runtime facade requires a deterministic dispatcher."))
  (unless (transport-dispatch-adapter-p transport-adapter)
    (fail 'cl-gserver-runtime-error
          "Runtime facade requires a transport dispatch adapter."))
  (unless (eq dispatcher
              (transport-dispatch-adapter-dispatcher transport-adapter))
    (fail 'cl-gserver-runtime-error
          "Runtime facade and transport adapter must share one dispatcher."))
  (unless (and (integerp retry-delay-ms) (> retry-delay-ms 0))
    (fail 'cl-gserver-runtime-error
          "Runtime tell retry delay must be a positive integer."))
  (let ((handler-table (make-handler-table handlers)))
    (validate-native-runtime-contracts
     dispatcher native-contracts handler-table)
    (%make-cl-gserver-runtime-facade
     :context context
     :runtime-port runtime-port
     :dispatcher dispatcher
     :transport-adapter transport-adapter
     :native-contracts (copy-list native-contracts)
     :handlers handler-table
     :retry-delay-ms retry-delay-ms)))

(defun cl-gserver-runtime-facade-actor (facade actor-name)
  (gethash actor-name (cl-gserver-runtime-facade-actors facade)))

(defun cl-gserver-runtime-facade-job-count (facade)
  (hash-table-count (cl-gserver-runtime-facade-jobs facade)))

(defun runtime-next-job-id (facade)
  (incf (cl-gserver-runtime-facade-sequence facade))
  (format nil "runtime-job-~6,'0D"
          (cl-gserver-runtime-facade-sequence facade)))

(defun runtime-job-message (job)
  (list :kind :star-runtime-job
        :job-id (cl-gserver-runtime-job-id job)
        :actor-name (cl-gserver-runtime-job-actor-name job)
        :command (copy-tree (cl-gserver-runtime-job-command job))))

(defun runtime-result-message (job-id result)
  (list :kind :star-runtime-result
        :job-id job-id
        :result (copy-tree result)))

(defun require-runtime-job (facade job-id)
  (or (gethash job-id (cl-gserver-runtime-facade-jobs facade))
      (fail 'cl-gserver-runtime-error
            "Runtime result references unknown job ~A."
            job-id)))

(defun complete-runtime-job (facade message)
  (unless (eq (getf message :kind) :star-runtime-result)
    (fail 'cl-gserver-runtime-error
          "Runtime coordinator received invalid message ~S."
          (getf message :kind)))
  (let* ((job-id (required-nonempty-string
                  (getf message :job-id)
                  "runtime result job-id"))
         (job (require-runtime-job facade job-id))
         (result (getf message :result))
         (command (cl-gserver-runtime-job-command job))
         (settlement
           (finish-held-transport-dispatch
            (cl-gserver-runtime-facade-transport-adapter facade)
            command
            result)))
    (remhash job-id (cl-gserver-runtime-facade-jobs facade))
    settlement))

(defun runtime-coordinator-receive (facade)
  (lambda (message)
    (complete-runtime-job facade message)))

(defun native-handler-result (handler command)
  (handler-case
      (let ((result (funcall handler command)))
        (ensure-plist result "native actor result" 'invalid-envelope-error)
        result)
    (error (condition)
      (fail-dispatch
       :code "star.native-handler-error"
       :message (princ-to-string condition)
       :retryable nil))))

(defun native-actor-receive (facade contract)
  (let* ((handler-name (getf contract :handler))
         (handler (gethash handler-name
                           (cl-gserver-runtime-facade-handlers facade))))
    (lambda (message)
      (unless (eq (getf message :kind) :star-runtime-job)
        (fail 'cl-gserver-runtime-error
              "Native actor ~A received invalid runtime message ~S."
              (getf contract :name)
              (getf message :kind)))
      (let* ((job-id (required-nonempty-string
                      (getf message :job-id)
                      "native runtime job-id"))
             (command (getf message :command))
             (result (native-handler-result handler command)))
        (runtime-tell
         (cl-gserver-runtime-facade-runtime-port facade)
         (cl-gserver-runtime-facade-coordinator facade)
         (runtime-result-message job-id result)
         (cl-gserver-runtime-facade-actor facade
                                         (getf contract :name)))
        :result-sent))))

(defun submit-native-runtime-job (facade actor-name command)
  (let ((actor (cl-gserver-runtime-facade-actor facade actor-name)))
    (unless actor
      (fail 'cl-gserver-runtime-error
            "Native actor ~A has not been started."
            actor-name))
    (let* ((job-id (runtime-next-job-id facade))
           (job (make-cl-gserver-runtime-job
                 :id job-id
                 :actor-name actor-name
                 :command (copy-tree command))))
      (setf (gethash job-id (cl-gserver-runtime-facade-jobs facade)) job)
      (handler-case
          (progn
            (runtime-tell
             (cl-gserver-runtime-facade-runtime-port facade)
             actor
             (runtime-job-message job)
             (cl-gserver-runtime-facade-coordinator facade))
            job-id)
        (cl-gserver-runtime-error (condition)
          (declare (ignore condition))
          (remhash job-id (cl-gserver-runtime-facade-jobs facade))
          nil)))))

(defun runtime-proxy-handler (facade actor-name)
  (lambda (dispatcher command)
    (declare (ignore dispatcher))
    (if (submit-native-runtime-job facade actor-name command)
        (defer-dispatch)
        (retry-dispatch
         :retry-after-ms
         (cl-gserver-runtime-facade-retry-delay-ms facade)
         :reason "cl-gserver tell failed before actor acceptance"))))

(defun start-runtime-coordinator (facade)
  (setf (cl-gserver-runtime-facade-coordinator facade)
        (runtime-actor-of
         (cl-gserver-runtime-facade-runtime-port facade)
         (cl-gserver-runtime-facade-context facade)
         "star-runtime-coordinator"
         (runtime-coordinator-receive facade))))

(defun start-native-runtime-actor (facade contract)
  (let* ((name (getf contract :name))
         (actor
           (runtime-actor-of
            (cl-gserver-runtime-facade-runtime-port facade)
            (cl-gserver-runtime-facade-context facade)
            name
            (native-actor-receive facade contract))))
    (setf (gethash name (cl-gserver-runtime-facade-actors facade)) actor)
    (register-dispatch-actor
     (cl-gserver-runtime-facade-dispatcher facade)
     name
     (runtime-proxy-handler facade name))
    actor))

(defun start-cl-gserver-runtime-facade (facade)
  (when (cl-gserver-runtime-facade-started-p facade)
    (fail 'cl-gserver-runtime-error
          "cl-gserver runtime facade is already started."))
  (start-runtime-coordinator facade)
  (dolist (contract (cl-gserver-runtime-facade-native-contracts facade))
    (start-native-runtime-actor facade contract))
  (setf (cl-gserver-runtime-facade-started-p facade) t)
  facade)

(defun shutdown-cl-gserver-runtime-facade (facade)
  (when (cl-gserver-runtime-facade-started-p facade)
    (maphash
     (lambda (name actor)
       (declare (ignore name))
       (runtime-stop
        (cl-gserver-runtime-facade-runtime-port facade)
        (cl-gserver-runtime-facade-context facade)
        actor))
     (cl-gserver-runtime-facade-actors facade))
    (when (cl-gserver-runtime-facade-coordinator facade)
      (runtime-stop
       (cl-gserver-runtime-facade-runtime-port facade)
       (cl-gserver-runtime-facade-context facade)
       (cl-gserver-runtime-facade-coordinator facade)))
    (runtime-shutdown
     (cl-gserver-runtime-facade-runtime-port facade)
     (cl-gserver-runtime-facade-context facade))
    (setf (cl-gserver-runtime-facade-started-p facade) nil))
  :stopped)