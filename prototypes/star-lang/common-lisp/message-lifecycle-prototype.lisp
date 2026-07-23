(in-package #:star-lang.core-surface.prototype)

(export '(canonical-lifecycle-envelope-json
          delivery-outcome
          idempotency-scope-key
          make-ack-envelope
          make-cancel-envelope
          make-command-envelope
          make-error-envelope
          make-event-envelope
          make-reply-envelope
          terminal-lifecycle-envelope-p
          validate-lifecycle-envelope))

(defparameter *lifecycle-kinds*
  '(:command :event :reply :ack :error :cancel))

(defparameter *ack-statuses*
  '(:accepted :completed :rejected :retry))

(defun required-nonempty-string (value context)
  (unless (and (stringp value) (> (length value) 0))
    (fail 'invalid-envelope-error "~A requires a non-empty string." context))
  value)

(defun positive-integer (value context)
  (unless (and (integerp value) (> value 0))
    (fail 'invalid-envelope-error "~A requires a positive integer." context))
  value)

(defun normalize-lifecycle-kind (value)
  (let ((kind
          (cond
            ((keywordp value) value)
            ((or (stringp value) (symbolp value))
             (intern (string-upcase (identifier-string value)) :keyword))
            (t nil))))
    (unless (member kind *lifecycle-kinds* :test #'eq)
      (fail 'invalid-envelope-error
            "Lifecycle kind must be one of ~S." *lifecycle-kinds*))
    kind))

(defun normalize-ack-status (value)
  (let ((status
          (cond
            ((keywordp value) value)
            ((or (stringp value) (symbolp value))
             (intern (string-upcase (identifier-string value)) :keyword))
            (t nil))))
    (unless (member status *ack-statuses* :test #'eq)
      (fail 'invalid-envelope-error
            "Acknowledgement status must be one of ~S." *ack-statuses*))
    status))

(defun lifecycle-base (&key kind message-id message-type actor sender
                            correlation-id causation-id attempt idempotency-key
                            dataset reply-to sent-at deadline payload)
  (list :star-version 1
        :kind (normalize-lifecycle-kind kind)
        :message-id (required-nonempty-string message-id "message-id")
        :message-type (required-nonempty-string message-type "message-type")
        :actor (required-nonempty-string actor "actor")
        :sender sender
        :correlation-id
        (required-nonempty-string correlation-id "correlation-id")
        :causation-id causation-id
        :attempt (positive-integer attempt "attempt")
        :idempotency-key idempotency-key
        :dataset dataset
        :reply-to reply-to
        :sent-at sent-at
        :deadline deadline
        :payload payload))

(defun make-command-envelope (&key message-id message-type actor sender payload
                                   idempotency-key correlation-id causation-id
                                   dataset reply-to sent-at deadline (attempt 1))
  (lifecycle-base
   :kind :command
   :message-id message-id
   :message-type message-type
   :actor actor
   :sender sender
   :correlation-id (or correlation-id message-id)
   :causation-id causation-id
   :attempt attempt
   :idempotency-key
   (required-nonempty-string idempotency-key "command idempotency-key")
   :dataset dataset
   :reply-to reply-to
   :sent-at sent-at
   :deadline deadline
   :payload payload))

(defun make-event-envelope (&key message-id message-type actor sender payload
                                 correlation-id causation-id dataset sent-at
                                 (attempt 1))
  (lifecycle-base
   :kind :event
   :message-id message-id
   :message-type message-type
   :actor actor
   :sender sender
   :correlation-id (or correlation-id message-id)
   :causation-id causation-id
   :attempt attempt
   :dataset dataset
   :sent-at sent-at
   :payload payload))

(defun source-correlation-id (source)
  (or (getf source :correlation-id) (getf source :message-id)))

(defun make-reply-envelope (source &key message-id message-type actor sender payload
                                        dataset sent-at deadline)
  (validate-lifecycle-envelope nil source :validate-payload nil)
  (lifecycle-base
   :kind :reply
   :message-id message-id
   :message-type message-type
   :actor actor
   :sender sender
   :correlation-id (source-correlation-id source)
   :causation-id (getf source :message-id)
   :attempt 1
   :dataset (or dataset (getf source :dataset))
   :sent-at sent-at
   :deadline deadline
   :payload payload))

(defun make-ack-envelope (source &key message-id actor sender status reason
                                      retry-after-ms sent-at)
  (validate-lifecycle-envelope nil source :validate-payload nil)
  (let ((normalized-status (normalize-ack-status status)))
    (when (eq normalized-status :retry)
      (positive-integer retry-after-ms "retry-after-ms"))
    (when (and retry-after-ms (not (eq normalized-status :retry)))
      (fail 'invalid-envelope-error
            "retry-after-ms is valid only for retry acknowledgements."))
    (lifecycle-base
     :kind :ack
     :message-id message-id
     :message-type "star.protocol/ack@1"
     :actor actor
     :sender sender
     :correlation-id (source-correlation-id source)
     :causation-id (getf source :message-id)
     :attempt 1
     :dataset (getf source :dataset)
     :sent-at sent-at
     :payload (list :status normalized-status
                    :for-message-id (getf source :message-id)
                    :reason reason
                    :retry-after-ms retry-after-ms))))

(defun make-error-envelope (source &key message-id actor sender code message
                                        retryable details sent-at)
  (validate-lifecycle-envelope nil source :validate-payload nil)
  (lifecycle-base
   :kind :error
   :message-id message-id
   :message-type "star.protocol/error@1"
   :actor actor
   :sender sender
   :correlation-id (source-correlation-id source)
   :causation-id (getf source :message-id)
   :attempt 1
   :dataset (getf source :dataset)
   :sent-at sent-at
   :payload (list :for-message-id (getf source :message-id)
                  :code (required-nonempty-string code "error code")
                  :message (required-nonempty-string message "error message")
                  :retryable (not (null retryable))
                  :details details)))

(defun make-cancel-envelope (source &key message-id actor sender reason sent-at)
  (validate-lifecycle-envelope nil source :validate-payload nil)
  (lifecycle-base
   :kind :cancel
   :message-id message-id
   :message-type "star.protocol/cancel@1"
   :actor actor
   :sender sender
   :correlation-id (source-correlation-id source)
   :causation-id (getf source :message-id)
   :attempt 1
   :dataset (getf source :dataset)
   :sent-at sent-at
   :payload (list :target-message-id (getf source :message-id)
                  :target-correlation-id (source-correlation-id source)
                  :reason reason)))

(defun validate-control-payload (envelope)
  (let ((kind (getf envelope :kind))
        (payload (getf envelope :payload)))
    (ensure-plist payload "lifecycle control payload" 'invalid-envelope-error)
    (ecase kind
      (:ack
       (let ((status (normalize-ack-status
                      (required-option payload :status "ack payload"
                                       'invalid-envelope-error)))
             (for-message-id
               (required-option payload :for-message-id "ack payload"
                                'invalid-envelope-error))
             (retry-after-ms (getf payload :retry-after-ms)))
         (setf (getf payload :status) status)
         (required-nonempty-string for-message-id "ack for-message-id")
         (when (eq status :retry)
           (positive-integer retry-after-ms "ack retry-after-ms"))
         (when (and retry-after-ms (not (eq status :retry)))
           (fail 'invalid-envelope-error
                 "Only retry acknowledgements may carry retry-after-ms."))))
      (:error
       (required-nonempty-string
        (required-option payload :for-message-id "error payload"
                         'invalid-envelope-error)
        "error for-message-id")
       (required-nonempty-string
        (required-option payload :code "error payload" 'invalid-envelope-error)
        "error code")
       (required-nonempty-string
        (required-option payload :message "error payload" 'invalid-envelope-error)
        "error message")
       (unless (plist-has-key-p payload :retryable)
         (fail 'invalid-envelope-error
               "error payload requires explicit retryable boolean."))
       (unless (member (getf payload :retryable) '(t nil) :test #'eq)
         (fail 'invalid-envelope-error "error retryable must be boolean.")))
      (:cancel
       (required-nonempty-string
        (required-option payload :target-message-id "cancel payload"
                         'invalid-envelope-error)
        "cancel target-message-id")
       (required-nonempty-string
        (required-option payload :target-correlation-id "cancel payload"
                         'invalid-envelope-error)
        "cancel target-correlation-id")))))

(defun validate-lifecycle-envelope (manifest envelope &key (validate-payload t))
  (ensure-plist envelope "lifecycle envelope" 'invalid-envelope-error)
  (unless (eql (getf envelope :star-version) 1)
    (fail 'invalid-envelope-error "Unsupported lifecycle wire version."))
  (let ((kind (normalize-lifecycle-kind (getf envelope :kind))))
    (setf (getf envelope :kind) kind)
    (required-nonempty-string (getf envelope :message-id) "message-id")
    (required-nonempty-string (getf envelope :message-type) "message-type")
    (required-nonempty-string (getf envelope :actor) "actor")
    (required-nonempty-string (getf envelope :correlation-id) "correlation-id")
    (positive-integer (getf envelope :attempt) "attempt")
    (when (member kind '(:reply :ack :error :cancel) :test #'eq)
      (required-nonempty-string (getf envelope :causation-id) "causation-id"))
    (when (eq kind :command)
      (required-nonempty-string
       (getf envelope :idempotency-key) "command idempotency-key"))
    (when (and (getf envelope :deadline)
               (not (stringp (getf envelope :deadline))))
      (fail 'invalid-envelope-error "deadline must be an ISO datetime string."))
    (when validate-payload
      (cond
        ((member kind '(:command :event :reply) :test #'eq)
         (unless manifest
           (fail 'invalid-envelope-error
                 "Data lifecycle envelopes require a portable manifest."))
         (let ((contract
                 (message-contract manifest (getf envelope :message-type))))
           (unless contract
             (fail 'invalid-envelope-error
                   "Unknown lifecycle message type ~A."
                   (getf envelope :message-type)))
           (wire-fields-object
            manifest (getf contract :fields) (getf envelope :payload)
            (format nil "Message ~A" (getf envelope :message-type)))))
        (t (validate-control-payload envelope)))))
  t)

(defun lifecycle-common-json-entries (envelope)
  (let ((entries
          (list (cons "star_version" 1)
                (cons "kind" (identifier-string (getf envelope :kind)))
                (cons "message_id" (getf envelope :message-id))
                (cons "message_type" (getf envelope :message-type))
                (cons "actor" (getf envelope :actor))
                (cons "correlation_id" (getf envelope :correlation-id))
                (cons "attempt" (getf envelope :attempt)))))
    (dolist (mapping '((:sender . "sender")
                       (:causation-id . "causation_id")
                       (:idempotency-key . "idempotency_key")
                       (:dataset . "dataset")
                       (:reply-to . "reply_to")
                       (:sent-at . "sent_at")
                       (:deadline . "deadline")))
      (let ((value (getf envelope (car mapping))))
        (when value (push (cons (cdr mapping) value) entries))))
    entries))

(defun control-payload-json (envelope)
  (let ((payload (getf envelope :payload)))
    (ecase (getf envelope :kind)
      (:ack
       (%make-json-object
        (remove nil
                (list
                 (cons "status" (identifier-string (getf payload :status)))
                 (cons "for_message_id" (getf payload :for-message-id))
                 (and (getf payload :reason)
                      (cons "reason" (getf payload :reason)))
                 (and (getf payload :retry-after-ms)
                      (cons "retry_after_ms" (getf payload :retry-after-ms)))))))
      (:error
       (%make-json-object
        (remove nil
                (list
                 (cons "for_message_id" (getf payload :for-message-id))
                 (cons "code" (getf payload :code))
                 (cons "message" (getf payload :message))
                 (cons "retryable"
                       (if (getf payload :retryable)
                           +json-true+ +json-false+))
                 (and (getf payload :details)
                      (cons "details"
                            (generic-wire-json-value (getf payload :details))))))))
      (:cancel
       (%make-json-object
        (remove nil
                (list
                 (cons "target_message_id" (getf payload :target-message-id))
                 (cons "target_correlation_id"
                       (getf payload :target-correlation-id))
                 (and (getf payload :reason)
                      (cons "reason" (getf payload :reason))))))))))

(defun canonical-lifecycle-envelope-json (manifest envelope)
  (validate-lifecycle-envelope manifest envelope)
  (let* ((kind (getf envelope :kind))
         (payload-json
           (if (member kind '(:command :event :reply) :test #'eq)
               (let ((contract
                       (message-contract manifest (getf envelope :message-type))))
                 (wire-fields-object
                  manifest (getf contract :fields) (getf envelope :payload)
                  (format nil "Message ~A" (getf envelope :message-type))))
               (control-payload-json envelope)))
         (entries (lifecycle-common-json-entries envelope)))
    (push (cons "payload" payload-json) entries)
    (canonical-json-string (%make-json-object entries))))

(defun delivery-outcome (envelope)
  (case (normalize-lifecycle-kind (getf envelope :kind))
    (:ack
     (case (normalize-ack-status (getf (getf envelope :payload) :status))
       (:accepted :accepted)
       (:completed :completed)
       (:rejected :rejected)
       (:retry :retry)))
    (:error
     (if (getf (getf envelope :payload) :retryable)
         :retry
         :failed))
    (:cancel :cancel-requested)
    (otherwise :pending)))

(defun terminal-lifecycle-envelope-p (envelope)
  (not (null
        (member (delivery-outcome envelope)
                '(:completed :rejected :failed)
                :test #'eq))))

(defun idempotency-scope-key (envelope)
  (unless (eq (normalize-lifecycle-kind (getf envelope :kind)) :command)
    (fail 'invalid-envelope-error
          "Idempotency scope keys are defined for command envelopes."))
  (list (getf envelope :actor)
        (getf envelope :message-type)
        (required-nonempty-string
         (getf envelope :idempotency-key) "command idempotency-key")))
