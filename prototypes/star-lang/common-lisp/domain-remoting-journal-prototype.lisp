(in-package #:star-lang.core-surface.prototype)

(export '(configure-main-domain-gateway-journal
          main-domain-gateway-journal-configured-p
          redeliver-main-domain-gateway-pending
          restore-main-domain-gateway-journal))

(defstruct (main-domain-journal-state
            (:constructor %make-main-domain-journal-state))
  port
  (delivered (make-hash-table :test #'equal))
  (restored-p nil))

(defvar *main-domain-gateway-journals* (make-hash-table :test #'eq))

(defun main-domain-gateway-journal-state (gateway)
  (gethash gateway *main-domain-gateway-journals*))

(defun main-domain-gateway-journal-configured-p (gateway)
  (not (null (main-domain-gateway-journal-state gateway))))

(defun configure-main-domain-gateway-journal (gateway port)
  (unless (main-domain-gateway-p gateway)
    (fail 'runtime-journal-error
          "Gateway journal configuration requires a main domain gateway."))
  (unless (runtime-journal-port-p port)
    (fail 'runtime-journal-error
          "Gateway journal configuration requires a runtime journal port."))
  (when (main-domain-gateway-journal-state gateway)
    (fail 'runtime-journal-error
          "Main domain gateway already has a runtime journal."))
  (setf (gethash gateway *main-domain-gateway-journals*)
        (%make-main-domain-journal-state :port port))
  gateway)

(defun gateway-journal-event (gateway kind command &optional result)
  (let ((dispatcher (main-domain-gateway-dispatcher gateway)))
    (append
     (list :kind kind
           :dispatcher-sequence
           (deterministic-dispatcher-sequence dispatcher)
           :dispatcher-now
           (deterministic-dispatcher-now dispatcher)
           :command (copy-tree command))
     (when result
       (list :result (copy-tree result))))))

(defun append-gateway-journal-event
    (gateway kind command &optional result)
  (let ((state (main-domain-gateway-journal-state gateway)))
    (when state
      (runtime-journal-append
       (main-domain-journal-state-port state)
       (gateway-journal-event gateway kind command result)))))

(defun restore-dispatcher-position (dispatcher event)
  (let ((sequence (getf event :dispatcher-sequence))
        (now (getf event :dispatcher-now)))
    (when (> sequence (deterministic-dispatcher-sequence dispatcher))
      (setf (deterministic-dispatcher-sequence dispatcher) sequence))
    (when (string< (deterministic-dispatcher-now dispatcher) now)
      (advance-dispatcher-clock dispatcher now)))
  dispatcher)

(defun restore-in-progress-command (gateway command)
  (let ((dispatcher (main-domain-gateway-dispatcher gateway)))
    (validate-lifecycle-envelope
     (deterministic-dispatcher-manifest dispatcher)
     command)
    (set-command-idempotency-record
     dispatcher
     command
     (list :status :in-progress
           :command (copy-tree command)
           :outcomes '()))
    (setf (gethash (getf command :message-id)
                   (main-domain-gateway-pending gateway))
          (copy-tree command)))
  command)

(defun restore-settled-command (gateway event &key completed-p)
  (let* ((dispatcher (main-domain-gateway-dispatcher gateway))
         (command (getf event :command))
         (message-id (getf command :message-id))
         (result (getf event :result)))
    (unless (command-idempotency-record dispatcher command)
      (restore-in-progress-command gateway command))
    (restore-dispatcher-position dispatcher event)
    (let ((completion
            (finish-deferred-dispatch dispatcher command result)))
      (drain-dispatcher-emitted dispatcher)
      (remhash message-id (main-domain-gateway-pending gateway))
      (remhash message-id
               (main-domain-journal-state-delivered
                (main-domain-gateway-journal-state gateway)))
      (when completed-p
        (setf (gethash message-id
                       (main-domain-gateway-completed gateway))
              completion))
      completion)))

(defun restore-main-domain-gateway-journal (gateway)
  (let ((state (main-domain-gateway-journal-state gateway)))
    (unless state
      (fail 'runtime-journal-error
            "Cannot restore a gateway without a configured journal."))
    (when (main-domain-journal-state-restored-p state)
      (fail 'runtime-journal-error
            "Main domain gateway journal was already restored."))
    (unless (and (zerop (hash-table-count
                         (main-domain-gateway-pending gateway)))
                 (zerop (hash-table-count
                         (main-domain-gateway-completed gateway)))
                 (zerop (hash-table-count
                         (deterministic-dispatcher-idempotency
                          (main-domain-gateway-dispatcher gateway)))))
      (fail 'runtime-journal-error
            "Gateway journal restoration requires fresh runtime state."))
    (dolist (event
             (runtime-journal-replay
              (main-domain-journal-state-port state)))
      (restore-dispatcher-position
       (main-domain-gateway-dispatcher gateway)
       event)
      (case (getf event :kind)
        (:pending
         (restore-in-progress-command gateway (getf event :command)))
        (:route-result
         (restore-settled-command gateway event :completed-p nil))
        (:remote-result
         (restore-settled-command gateway event :completed-p t))))
    (setf (main-domain-journal-state-restored-p state) t)
    gateway))

(defun journal-pending-message-ids (gateway)
  (let ((message-ids '()))
    (maphash
     (lambda (message-id command)
       (declare (ignore command))
       (push message-id message-ids))
     (main-domain-gateway-pending gateway))
    (sort message-ids #'string<)))

(defun redeliver-main-domain-gateway-pending (gateway)
  (let ((state (main-domain-gateway-journal-state gateway))
        (redelivered '()))
    (unless state
      (return-from redeliver-main-domain-gateway-pending '()))
    (dolist (message-id (journal-pending-message-ids gateway))
      (unless (gethash message-id
                       (main-domain-journal-state-delivered state))
        (let* ((command
                 (gethash message-id
                          (main-domain-gateway-pending gateway)))
               (node (and command (select-domain-node gateway command))))
          (when node
            (handler-case
                (progn
                  (remoting-tell
                   (main-domain-gateway-remoting-port gateway)
                   (remote-domain-node-ref node)
                   (list :kind :star-domain-command
                         :domain "bbp"
                         :node-id (remote-domain-node-node-id node)
                         :command (copy-tree command))
                   (main-domain-gateway-actor gateway))
                  (setf (gethash message-id
                                 (main-domain-journal-state-delivered state))
                        t)
                  (push message-id redelivered))
              (domain-remoting-error () nil))))))
    (nreverse redelivered)))

(defvar *main-domain-register-node-without-journal*
  (symbol-function 'main-domain-register-node))

(defvar *main-domain-route-command-without-journal*
  (symbol-function 'main-domain-route-command))

(defvar *main-domain-complete-command-without-journal*
  (symbol-function 'main-domain-complete-command))

(defun main-domain-register-node (gateway message)
  (prog1
      (funcall *main-domain-register-node-without-journal*
               gateway message)
    (when (main-domain-gateway-journal-state gateway)
      (redeliver-main-domain-gateway-pending gateway))))

(defun main-domain-route-command (gateway command)
  (let* ((state (main-domain-gateway-journal-state gateway))
         (node (and state (select-domain-node gateway command))))
    (unless state
      (return-from main-domain-route-command
        (funcall *main-domain-route-command-without-journal*
                 gateway command)))
    (when node
      (append-gateway-journal-event gateway :pending command))
    (let ((result
            (funcall *main-domain-route-command-without-journal*
                     gateway command)))
      (if (eq (getf result :outcome) :defer)
          (progn
            (unless node
              (fail 'runtime-journal-error
                    "Gateway deferred a command without a selected node."))
            (setf (gethash
                   (getf command :message-id)
                   (main-domain-journal-state-delivered state))
                  t))
          (progn
            (append-gateway-journal-event
             gateway :route-result command result)
            (remhash
             (getf command :message-id)
             (main-domain-journal-state-delivered state))))
      result)))

(defun main-domain-complete-command (gateway message)
  (let ((state (main-domain-gateway-journal-state gateway)))
    (unless state
      (return-from main-domain-complete-command
        (funcall *main-domain-complete-command-without-journal*
                 gateway message)))
    (ensure-plist message "domain result" 'domain-remoting-error)
    (let* ((message-id
             (required-nonempty-string
              (getf message :message-id)
              "domain result message-id"))
           (command
             (gethash message-id
                      (main-domain-gateway-pending gateway))))
      (when command
        (let ((result (getf message :result)))
          (ensure-plist result
                        "domain dispatch result"
                        'domain-remoting-error)
          (append-gateway-journal-event
           gateway :remote-result command result)))
      (prog1
          (funcall *main-domain-complete-command-without-journal*
                   gateway message)
        (remhash message-id
                 (main-domain-journal-state-delivered state))))))
