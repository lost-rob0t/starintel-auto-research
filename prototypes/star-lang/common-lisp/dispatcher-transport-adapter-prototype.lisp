(in-package #:star-lang.core-surface.prototype)

(export '(make-transport-dispatch-adapter
          run-transport-adapter
          run-transport-adapter-next
          transport-dispatch-adapter-held-count))

(defstruct (transport-dispatch-adapter
            (:constructor %make-transport-dispatch-adapter))
  dispatcher
  port
  (held (make-hash-table :test #'equal)))

(defun make-transport-dispatch-adapter (dispatcher port)
  (unless (deterministic-dispatcher-p dispatcher)
    (fail 'transport-port-error
          "Transport dispatch adapter requires a deterministic dispatcher."))
  (unless (transport-port-p port)
    (fail 'transport-port-error
          "Transport dispatch adapter requires a transport port."))
  (%make-transport-dispatch-adapter :dispatcher dispatcher :port port))

(defun transport-dispatch-adapter-held-count (adapter)
  (hash-table-count (transport-dispatch-adapter-held adapter)))

(defun transport-adapter-publish-outcomes (adapter outcomes)
  (dolist (outcome outcomes)
    (transport-publish (transport-dispatch-adapter-port adapter) outcome))
  outcomes)

(defun retry-delay-from-outcomes (outcomes)
  (let ((retry
          (find-if
           (lambda (envelope)
             (and (eq (getf envelope :kind) :ack)
                  (eq (getf (getf envelope :payload) :status) :retry)))
           outcomes)))
    (unless retry
      (fail 'transport-port-error
            "Retry dispatch completed without a retry acknowledgement."))
    (positive-integer
     (getf (getf retry :payload) :retry-after-ms)
     "transport retry delay")))

(defun held-delivery-key (command)
  (idempotency-scope-key command))

(defun hold-transport-delivery (adapter delivery)
  (let* ((command (transport-delivery-envelope delivery))
         (key (held-delivery-key command)))
    (setf (gethash key (transport-dispatch-adapter-held adapter)) delivery)
    delivery))

(defun string-value= (left right)
  (and (stringp left) (stringp right) (string= left right)))

(defun held-delivery-targeted-p (delivery cancel-envelope)
  (let* ((command (transport-delivery-envelope delivery))
         (payload (getf cancel-envelope :payload))
         (target-message-id (getf payload :target-message-id))
         (target-correlation-id (getf payload :target-correlation-id)))
    (or (string-value= (getf command :message-id) target-message-id)
        (string-value= (getf command :correlation-id)
                       target-correlation-id))))

(defun settle-held-for-cancel (adapter cancel-envelope)
  (let ((keys '())
        (port (transport-dispatch-adapter-port adapter)))
    (maphash
     (lambda (key delivery)
       (when (held-delivery-targeted-p delivery cancel-envelope)
         (push key keys)))
     (transport-dispatch-adapter-held adapter))
    (dolist (key keys)
      (let ((delivery
              (gethash key (transport-dispatch-adapter-held adapter))))
        (when delivery
          (transport-ack port delivery)
          (remhash key (transport-dispatch-adapter-held adapter)))))
    (length keys)))

(defun settle-command-result (adapter delivery result outcomes)
  (let* ((dispatcher (transport-dispatch-adapter-dispatcher adapter))
         (port (transport-dispatch-adapter-port adapter))
         (command (transport-delivery-envelope delivery)))
    (case result
      (:retry
       (let ((redelivery (redeliver-command dispatcher command))
             (delay-ms (retry-delay-from-outcomes outcomes)))
         (transport-requeue port delivery redelivery delay-ms)
         :requeued))
      (:deferred
       (hold-transport-delivery adapter delivery)
       :held)
      (otherwise
       (transport-ack port delivery)
       :acked))))

(defun process-command-delivery (adapter delivery)
  (let* ((dispatcher (transport-dispatch-adapter-dispatcher adapter))
         (command (transport-delivery-envelope delivery)))
    (submit-dispatch-envelope dispatcher command)
    (let ((result (run-dispatcher-next dispatcher))
          (outcomes (drain-dispatcher-emitted dispatcher)))
      (transport-adapter-publish-outcomes adapter outcomes)
      (settle-command-result adapter delivery result outcomes))))

(defun process-cancel-delivery (adapter delivery)
  (let* ((dispatcher (transport-dispatch-adapter-dispatcher adapter))
         (port (transport-dispatch-adapter-port adapter))
         (cancel-envelope (transport-delivery-envelope delivery)))
    (submit-dispatch-envelope dispatcher cancel-envelope)
    (transport-adapter-publish-outcomes
     adapter (drain-dispatcher-emitted dispatcher))
    (settle-held-for-cancel adapter cancel-envelope)
    (transport-ack port delivery)
    :acked))

(defun recover-after-transport-failure (adapter delivery)
  (let ((port (transport-dispatch-adapter-port adapter)))
    (transport-requeue
     port
     delivery
     (transport-delivery-envelope delivery)
     0)
    :transport-requeued))

(defun reject-poison-delivery (adapter delivery condition)
  (transport-reject
   (transport-dispatch-adapter-port adapter)
   delivery
   (princ-to-string condition))
  :rejected)

(defun run-transport-adapter-next (adapter)
  (let* ((port (transport-dispatch-adapter-port adapter))
         (delivery (transport-receive port)))
    (when delivery
      (handler-case
          (case (getf (transport-delivery-envelope delivery) :kind)
            (:command (process-command-delivery adapter delivery))
            (:cancel (process-cancel-delivery adapter delivery))
            (otherwise
             (fail 'invalid-envelope-error
                   "Transport adapter accepts command and cancel inputs.")))
        (transport-port-error ()
          (recover-after-transport-failure adapter delivery))
        (error (condition)
          (reject-poison-delivery adapter delivery condition))))))

(defun run-transport-adapter (adapter &key (limit 100))
  (unless (and (integerp limit) (> limit 0))
    (fail 'transport-port-error
          "Transport adapter run limit must be positive."))
  (loop repeat limit
        for result = (run-transport-adapter-next adapter)
        while result
        collect result))
