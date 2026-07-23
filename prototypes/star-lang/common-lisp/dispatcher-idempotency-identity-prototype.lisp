(in-package #:star-lang.core-surface.prototype)

(export '(command-idempotency-identity
          dispatcher-idempotency-conflict-error))

(define-condition dispatcher-idempotency-conflict-error
    (invalid-envelope-error) ())

(defun command-idempotency-identity (command)
  (list :star-version (getf command :star-version)
        :kind (getf command :kind)
        :message-type (getf command :message-type)
        :actor (getf command :actor)
        :sender (getf command :sender)
        :correlation-id (getf command :correlation-id)
        :idempotency-key (getf command :idempotency-key)
        :dataset (getf command :dataset)
        :reply-to (getf command :reply-to)
        :deadline (getf command :deadline)
        :payload (copy-tree (getf command :payload))))

(defun dispatcher-command-record-if-addressable (dispatcher command)
  (when (and (deterministic-dispatcher-p dispatcher)
             (listp command))
    (let ((actor (getf command :actor))
          (idempotency-key (getf command :idempotency-key)))
      (when (and (stringp actor)
                 (stringp idempotency-key))
        (gethash
         (list actor idempotency-key)
         (deterministic-dispatcher-idempotency dispatcher))))))

(defun ensure-dispatcher-command-identity-compatible
    (record command)
  (let ((recorded-command (getf record :command)))
    (unless (equal (command-idempotency-identity recorded-command)
                   (command-idempotency-identity command))
      (fail 'dispatcher-idempotency-conflict-error
            "Idempotency key ~A for actor ~A is already bound to a different command identity."
            (getf command :idempotency-key)
            (getf command :actor))))
  command)

(defvar *process-command-without-idempotency-identity*
  (symbol-function 'process-command))

(defun process-command (dispatcher command)
  (unless (deterministic-dispatcher-p dispatcher)
    (fail 'invalid-envelope-error
          "process-command requires a dispatcher."))
  (validate-lifecycle-envelope
   (deterministic-dispatcher-manifest dispatcher)
   command)
  (let ((record
          (dispatcher-command-record-if-addressable
           dispatcher command)))
    (when record
      (ensure-dispatcher-command-identity-compatible
       record command)))
  (funcall *process-command-without-idempotency-identity*
           dispatcher command))
