(in-package #:star-lang.core-surface.prototype)

(export '(advance-dispatcher-clock
          complete-dispatch
          defer-dispatch
          deterministic-dispatcher-emitted
          deterministic-dispatcher-handler-count
          deterministic-dispatcher-now
          deterministic-dispatcher-queue
          drain-dispatcher-emitted
          fail-dispatch
          make-deterministic-dispatcher
          redeliver-command
          register-dispatch-actor
          retry-dispatch
          run-dispatcher
          run-dispatcher-next
          submit-dispatch-envelope))

(defstruct (deterministic-dispatcher
            (:constructor %make-deterministic-dispatcher))
  manifest
  (actors (make-hash-table :test #'equal))
  (queue '())
  (emitted '())
  (idempotency (make-hash-table :test #'equal))
  (cancelled-messages (make-hash-table :test #'equal))
  (cancelled-correlations (make-hash-table :test #'equal))
  (handler-count (make-hash-table :test #'equal))
  (sequence 0)
  (now "1970-01-01T00:00:00Z"))

(defun make-deterministic-dispatcher (manifest &key
                                               (now "1970-01-01T00:00:00Z"))
  (unless (and (listp manifest) (= (getf manifest :wire-version) 1))
    (fail 'invalid-envelope-error
          "Deterministic dispatcher requires a version-one portable manifest."))
  (required-nonempty-string now "dispatcher clock")
  (%make-deterministic-dispatcher :manifest manifest :now now))

(defun advance-dispatcher-clock (dispatcher now)
  (required-nonempty-string now "dispatcher clock")
  (when (string< now (deterministic-dispatcher-now dispatcher))
    (fail 'invalid-envelope-error
          "Deterministic dispatcher clock cannot move backward."))
  (setf (deterministic-dispatcher-now dispatcher) now)
  now)

(defun dispatcher-next-message-id (dispatcher prefix)
  (incf (deterministic-dispatcher-sequence dispatcher))
  (format nil "~A-~6,'0D"
          prefix (deterministic-dispatcher-sequence dispatcher)))

(defun dispatcher-actor-contract (dispatcher actor-name)
  (find actor-name
        (getf (deterministic-dispatcher-manifest dispatcher) :actors)
        :key (lambda (actor) (getf actor :name))
        :test #'string=))

(defun register-dispatch-actor (dispatcher actor-name handler)
  (required-nonempty-string actor-name "actor name")
  (unless (functionp handler)
    (fail 'invalid-actor-error "Dispatcher actor handler must be a function."))
  (unless (dispatcher-actor-contract dispatcher actor-name)
    (fail 'invalid-actor-error
          "Actor ~A is absent from the portable manifest." actor-name))
  (setf (gethash actor-name (deterministic-dispatcher-actors dispatcher))
        handler)
  actor-name)

(defun complete-dispatch (&key message-type payload)
  (list :outcome :complete
        :message-type message-type
        :payload payload))

(defun retry-dispatch (&key retry-after-ms reason)
  (positive-integer retry-after-ms "dispatch retry-after-ms")
  (list :outcome :retry
        :retry-after-ms retry-after-ms
        :reason reason))

(defun fail-dispatch (&key code message retryable details)
  (list :outcome :fail
        :code (required-nonempty-string code "dispatch error code")
        :message (required-nonempty-string message "dispatch error message")
        :retryable (not (null retryable))
        :details details))

(defun defer-dispatch ()
  (list :outcome :defer))

(defun dispatcher-emit (dispatcher envelope)
  (setf (deterministic-dispatcher-emitted dispatcher)
        (append (deterministic-dispatcher-emitted dispatcher)
                (list envelope)))
  envelope)

(defun drain-dispatcher-emitted (dispatcher)
  (prog1 (deterministic-dispatcher-emitted dispatcher)
    (setf (deterministic-dispatcher-emitted dispatcher) '())))

(defun dispatcher-enqueue (dispatcher envelope)
  (setf (deterministic-dispatcher-queue dispatcher)
        (append (deterministic-dispatcher-queue dispatcher)
                (list envelope)))
  envelope)

(defun dispatcher-dequeue (dispatcher)
  (let ((queue (deterministic-dispatcher-queue dispatcher)))
    (when queue
      (setf (deterministic-dispatcher-queue dispatcher) (rest queue))
      (first queue))))

(defun command-idempotency-record (dispatcher command)
  (gethash (idempotency-scope-key command)
           (deterministic-dispatcher-idempotency dispatcher)))

(defun set-command-idempotency-record (dispatcher command record)
  (setf (gethash (idempotency-scope-key command)
                 (deterministic-dispatcher-idempotency dispatcher))
        record))

(defun dispatcher-cancelled-p (dispatcher command)
  (or (gethash (getf command :message-id)
               (deterministic-dispatcher-cancelled-messages dispatcher))
      (gethash (getf command :correlation-id)
               (deterministic-dispatcher-cancelled-correlations dispatcher))))

(defun deadline-expired-p (dispatcher command)
  (let ((deadline (getf command :deadline)))
    (and deadline
         (not (string< (deterministic-dispatcher-now dispatcher)
                       deadline)))))

(defun actor-accepts-message-p (contract message-type)
  (member message-type (getf contract :accepts) :test #'string=))

(defun validate-command-route (dispatcher command)
  (let* ((actor-name (getf command :actor))
         (contract (dispatcher-actor-contract dispatcher actor-name))
         (handler (gethash actor-name
                           (deterministic-dispatcher-actors dispatcher))))
    (unless contract
      (fail 'invalid-actor-error
            "Command targets unknown actor ~A." actor-name))
    (unless (actor-accepts-message-p contract (getf command :message-type))
      (fail 'invalid-actor-error
            "Actor ~A does not accept message type ~A."
            actor-name (getf command :message-type)))
    (unless handler
      (fail 'invalid-actor-error
            "Actor ~A has no registered deterministic handler." actor-name))
    handler))

(defun make-dispatch-ack (dispatcher command status &key reason retry-after-ms)
  (make-ack-envelope
   command
   :message-id (dispatcher-next-message-id dispatcher "ack")
   :actor (or (getf command :sender) "star.dispatcher")
   :sender (getf command :actor)
   :status status
   :reason reason
   :retry-after-ms retry-after-ms
   :sent-at (deterministic-dispatcher-now dispatcher)))

(defun make-dispatch-error (dispatcher command code message retryable
                            &optional details)
  (make-error-envelope
   command
   :message-id (dispatcher-next-message-id dispatcher "error")
   :actor (or (getf command :sender) "star.dispatcher")
   :sender (getf command :actor)
   :code code
   :message message
   :retryable retryable
   :details details
   :sent-at (deterministic-dispatcher-now dispatcher)))

(defun make-dispatch-reply (dispatcher command message-type payload)
  (make-reply-envelope
   command
   :message-id (dispatcher-next-message-id dispatcher "reply")
   :message-type message-type
   :actor (or (getf command :sender) "star.dispatcher")
   :sender (getf command :actor)
   :dataset (getf command :dataset)
   :sent-at (deterministic-dispatcher-now dispatcher)
   :payload payload))

(defun terminal-record (command outcomes)
  (list :status :terminal
        :command command
        :outcomes outcomes))

(defun in-progress-record (command accepted)
  (list :status :in-progress
        :command command
        :outcomes (list accepted)))

(defun retry-record (command outcomes)
  (list :status :retry
        :command command
        :outcomes outcomes))

(defun replay-terminal-outcomes (dispatcher record)
  (dolist (outcome (getf record :outcomes))
    (dispatcher-emit dispatcher outcome))
  :duplicate)

(defun increment-handler-count (dispatcher actor-name)
  (incf (gethash actor-name
                 (deterministic-dispatcher-handler-count dispatcher)
                 0)))

(defun complete-command (dispatcher command result)
  (let ((outcomes '())
        (message-type (getf result :message-type)))
    (when message-type
      (let ((reply
              (make-dispatch-reply
               dispatcher command message-type (getf result :payload))))
        (validate-lifecycle-envelope
         (deterministic-dispatcher-manifest dispatcher) reply)
        (dispatcher-emit dispatcher reply)
        (push reply outcomes)))
    (let ((completed (make-dispatch-ack dispatcher command :completed)))
      (dispatcher-emit dispatcher completed)
      (push completed outcomes))
    (set-command-idempotency-record
     dispatcher command (terminal-record command (nreverse outcomes)))
    :completed))

(defun retry-command (dispatcher command result)
  (let ((retry
          (make-dispatch-ack
           dispatcher command :retry
           :reason (getf result :reason)
           :retry-after-ms (getf result :retry-after-ms))))
    (dispatcher-emit dispatcher retry)
    (set-command-idempotency-record
     dispatcher command (retry-record command (list retry)))
    :retry))

(defun fail-command (dispatcher command result)
  (let* ((retryable (getf result :retryable))
         (error-envelope
           (make-dispatch-error
            dispatcher command
            (getf result :code)
            (getf result :message)
            retryable
            (getf result :details))))
    (dispatcher-emit dispatcher error-envelope)
    (set-command-idempotency-record
     dispatcher command
     (if retryable
         (retry-record command (list error-envelope))
         (terminal-record command (list error-envelope))))
    (if retryable :retry :failed)))

(defun cancel-command (dispatcher command)
  (let ((error-envelope
          (make-dispatch-error
           dispatcher command
           "star.cancelled"
           "Command was cancelled before completion."
           nil)))
    (dispatcher-emit dispatcher error-envelope)
    (set-command-idempotency-record
     dispatcher command (terminal-record command (list error-envelope)))
    :cancelled))

(defun expire-command (dispatcher command)
  (let ((error-envelope
          (make-dispatch-error
           dispatcher command
           "star.deadline-exceeded"
           "Command deadline expired before completion."
           nil
           (list :deadline (getf command :deadline)
                 :dispatcher-now (deterministic-dispatcher-now dispatcher)))))
    (dispatcher-emit dispatcher error-envelope)
    (set-command-idempotency-record
     dispatcher command (terminal-record command (list error-envelope)))
    :deadline-exceeded))

(defun process-command (dispatcher command)
  (let* ((record (command-idempotency-record dispatcher command))
         (status (getf record :status)))
    (cond
      ((eq status :terminal)
       (replay-terminal-outcomes dispatcher record))
      ((eq status :in-progress)
       (dispatcher-emit
        dispatcher
        (make-dispatch-ack dispatcher command :accepted
                           :reason "Command is already in progress."))
       :in-progress)
      ((dispatcher-cancelled-p dispatcher command)
       (cancel-command dispatcher command))
      ((deadline-expired-p dispatcher command)
       (expire-command dispatcher command))
      (t
       (let* ((handler (validate-command-route dispatcher command))
              (accepted (make-dispatch-ack dispatcher command :accepted)))
         (dispatcher-emit dispatcher accepted)
         (set-command-idempotency-record
          dispatcher command (in-progress-record command accepted))
         (increment-handler-count dispatcher (getf command :actor))
         (let ((result (funcall handler dispatcher command)))
           (ensure-plist result "deterministic dispatch result"
                         'invalid-envelope-error)
           (case (getf result :outcome)
             (:complete (complete-command dispatcher command result))
             (:retry (retry-command dispatcher command result))
             (:fail (fail-command dispatcher command result))
             (:defer :deferred)
             (otherwise
              (fail 'invalid-envelope-error
                    "Actor ~A returned unknown dispatch outcome ~S."
                    (getf command :actor) (getf result :outcome))))))))))

(defun active-record-targeted-p (record target-message-id target-correlation-id)
  (let ((command (getf record :command)))
    (and (member (getf record :status) '(:in-progress :retry) :test #'eq)
         (or (string= (getf command :message-id) target-message-id)
             (string= (getf command :correlation-id)
                      target-correlation-id)))))

(defun apply-cancel-envelope (dispatcher cancel)
  (let* ((payload (getf cancel :payload))
         (target-message-id (getf payload :target-message-id))
         (target-correlation-id (getf payload :target-correlation-id)))
    (setf (gethash target-message-id
                   (deterministic-dispatcher-cancelled-messages dispatcher))
          t)
    (setf (gethash target-correlation-id
                   (deterministic-dispatcher-cancelled-correlations dispatcher))
          t)
    (maphash
     (lambda (key record)
       (declare (ignore key))
       (when (active-record-targeted-p
              record target-message-id target-correlation-id)
         (cancel-command dispatcher (getf record :command))))
     (deterministic-dispatcher-idempotency dispatcher))
    :cancel-requested))

(defun submit-dispatch-envelope (dispatcher envelope)
  (validate-lifecycle-envelope
   (deterministic-dispatcher-manifest dispatcher) envelope)
  (case (getf envelope :kind)
    (:command (dispatcher-enqueue dispatcher envelope))
    (:cancel (apply-cancel-envelope dispatcher envelope))
    (otherwise
     (fail 'invalid-envelope-error
           "Deterministic dispatcher accepts command and cancel inputs, received ~A."
           (getf envelope :kind)))))

(defun run-dispatcher-next (dispatcher)
  (let ((envelope (dispatcher-dequeue dispatcher)))
    (when envelope
      (process-command dispatcher envelope))))

(defun run-dispatcher (dispatcher)
  (loop while (deterministic-dispatcher-queue dispatcher)
        collect (run-dispatcher-next dispatcher)))

(defun redeliver-command (dispatcher command &key message-id)
  (validate-lifecycle-envelope
   (deterministic-dispatcher-manifest dispatcher) command)
  (unless (eq (getf command :kind) :command)
    (fail 'invalid-envelope-error "Only commands may be redelivered."))
  (let ((redelivery (copy-tree command)))
    (setf (getf redelivery :message-id)
          (or message-id (dispatcher-next-message-id dispatcher "redelivery")))
    (setf (getf redelivery :causation-id) (getf command :message-id))
    (incf (getf redelivery :attempt))
    redelivery))
