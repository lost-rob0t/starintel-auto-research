(in-package #:star-lang.core-surface.prototype)

(export '(finish-held-transport-dispatch
          held-transport-delivery
          make-transport-dispatch-adapter
          run-transport-adapter
          run-transport-adapter-next
          transport-dispatch-adapter-held-count
          transport-dispatch-adapter-pending-count))

(defstruct (transport-publication-record
            (:constructor make-transport-publication-record
                (&key kind result outcomes)))
  kind
  result
  (outcomes '())
  (next-index 0))

(defstruct (transport-dispatch-adapter
            (:constructor %make-transport-dispatch-adapter))
  dispatcher
  port
  (held (make-hash-table :test #'equal))
  (pending (make-hash-table :test #'equal)))

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

(defun transport-dispatch-adapter-pending-count (adapter)
  (hash-table-count (transport-dispatch-adapter-pending adapter)))

(defun transport-delivery-message-id (delivery)
  (required-nonempty-string
   (getf (transport-delivery-envelope delivery) :message-id)
   "transport delivery message-id"))

(defun pending-publication-record (adapter delivery)
  (gethash (transport-delivery-message-id delivery)
           (transport-dispatch-adapter-pending adapter)))

(defun store-pending-publication (adapter delivery kind result outcomes)
  (let ((record
          (make-transport-publication-record
           :kind kind
           :result result
           :outcomes (copy-list outcomes))))
    (setf (gethash (transport-delivery-message-id delivery)
                   (transport-dispatch-adapter-pending adapter))
          record)
    record))

(defun clear-pending-publication (adapter delivery)
  (remhash (transport-delivery-message-id delivery)
           (transport-dispatch-adapter-pending adapter)))

(defun transport-adapter-publish-record (adapter record)
  (let ((outcomes (transport-publication-record-outcomes record))
        (port (transport-dispatch-adapter-port adapter)))
    (loop while (< (transport-publication-record-next-index record)
                   (length outcomes))
          for index = (transport-publication-record-next-index record)
          for outcome = (nth index outcomes)
          do (transport-publish port outcome)
             (incf (transport-publication-record-next-index record)))
    outcomes))

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

(defun held-transport-delivery (adapter command)
  (gethash (held-delivery-key command)
           (transport-dispatch-adapter-held adapter)))

(defun remove-held-transport-delivery (adapter command)
  (remhash (held-delivery-key command)
           (transport-dispatch-adapter-held adapter)))

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

(defun settle-cancel-result (adapter delivery)
  (let ((port (transport-dispatch-adapter-port adapter))
        (cancel-envelope (transport-delivery-envelope delivery)))
    (settle-held-for-cancel adapter cancel-envelope)
    (transport-ack port delivery)
    :acked))

(defun complete-pending-publication (adapter delivery record)
  (transport-adapter-publish-record adapter record)
  (let ((settlement
          (ecase (transport-publication-record-kind record)
            (:command
             (settle-command-result
              adapter
              delivery
              (transport-publication-record-result record)
              (transport-publication-record-outcomes record)))
            (:cancel
             (settle-cancel-result adapter delivery)))))
    (clear-pending-publication adapter delivery)
    settlement))

(defun process-command-delivery (adapter delivery)
  (let* ((dispatcher (transport-dispatch-adapter-dispatcher adapter))
         (command (transport-delivery-envelope delivery)))
    (submit-dispatch-envelope dispatcher command)
    (let* ((result (run-dispatcher-next dispatcher))
           (outcomes (drain-dispatcher-emitted dispatcher))
           (record
             (store-pending-publication
              adapter delivery :command result outcomes)))
      (complete-pending-publication adapter delivery record))))

(defun process-cancel-delivery (adapter delivery)
  (let* ((dispatcher (transport-dispatch-adapter-dispatcher adapter))
         (cancel-envelope (transport-delivery-envelope delivery)))
    (submit-dispatch-envelope dispatcher cancel-envelope)
    (let ((record
            (store-pending-publication
             adapter
             delivery
             :cancel
             :acked
             (drain-dispatcher-emitted dispatcher))))
      (complete-pending-publication adapter delivery record))))

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

(defun finish-held-transport-dispatch (adapter command result)
  (let ((delivery (held-transport-delivery adapter command)))
    (unless delivery
      (if (eq (deferred-dispatch-status
               (transport-dispatch-adapter-dispatcher adapter)
               command)
              :terminal)
          (return-from finish-held-transport-dispatch :late-terminal)
          (fail 'transport-port-error
                "No held transport delivery exists for command ~A."
                (getf command :message-id))))
    (let* ((dispatcher (transport-dispatch-adapter-dispatcher adapter))
           (dispatch-result (finish-deferred-dispatch dispatcher command result)))
      (when (eq dispatch-result :late-terminal)
        (return-from finish-held-transport-dispatch :late-terminal))
      (let* ((outcomes (drain-dispatcher-emitted dispatcher))
             (record
               (store-pending-publication
                adapter delivery :command dispatch-result outcomes)))
        (handler-case
            (prog1 (complete-pending-publication adapter delivery record)
              (remove-held-transport-delivery adapter command))
          (transport-port-error ()
            (remove-held-transport-delivery adapter command)
            (recover-after-transport-failure adapter delivery)))))))

(defun resume-or-process-delivery (adapter delivery)
  (let ((pending (pending-publication-record adapter delivery)))
    (if pending
        (complete-pending-publication adapter delivery pending)
        (case (getf (transport-delivery-envelope delivery) :kind)
          (:command (process-command-delivery adapter delivery))
          (:cancel (process-cancel-delivery adapter delivery))
          (otherwise
           (fail 'invalid-envelope-error
                 "Transport adapter accepts command and cancel inputs."))))))

(defun run-transport-adapter-next (adapter)
  (let* ((port (transport-dispatch-adapter-port adapter))
         (delivery (transport-receive port)))
    (when delivery
      (handler-case
          (resume-or-process-delivery adapter delivery)
        (transport-port-error ()
          (recover-after-transport-failure adapter delivery))
        ((or invalid-envelope-error invalid-actor-error) (condition)
          (reject-poison-delivery adapter delivery condition))
        (error (condition)
          (if (pending-publication-record adapter delivery)
              (recover-after-transport-failure adapter delivery)
              (reject-poison-delivery adapter delivery condition)))))))

(defun run-transport-adapter (adapter &key (limit 100))
  (unless (and (integerp limit) (> limit 0))
    (fail 'transport-port-error
          "Transport adapter run limit must be positive."))
  (loop repeat limit
        for result = (run-transport-adapter-next adapter)
        while result
        collect result))