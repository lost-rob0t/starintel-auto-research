(in-package #:star-lang.core-surface.prototype)

(export '(finish-deferred-dispatch
          deferred-dispatch-status))

(defun deferred-dispatch-status (dispatcher command)
  (let ((record (command-idempotency-record dispatcher command)))
    (and record (getf record :status))))

(defun require-deferred-dispatch-record (dispatcher command)
  (let ((record (command-idempotency-record dispatcher command)))
    (unless record
      (fail 'invalid-envelope-error
            "Deferred completion has no idempotency record for command ~A."
            (getf command :message-id)))
    record))

(defun finish-deferred-dispatch (dispatcher command result)
  (unless (deterministic-dispatcher-p dispatcher)
    (fail 'invalid-envelope-error
          "Deferred completion requires a deterministic dispatcher."))
  (validate-lifecycle-envelope
   (deterministic-dispatcher-manifest dispatcher)
   command)
  (ensure-plist result "deferred dispatch result" 'invalid-envelope-error)
  (let* ((record (require-deferred-dispatch-record dispatcher command))
         (status (getf record :status)))
    (cond
      ((eq status :terminal)
       :late-terminal)
      ((not (eq status :in-progress))
       (fail 'invalid-envelope-error
             "Command ~A is not awaiting deferred completion; status is ~S."
             (getf command :message-id) status))
      (t
       (case (getf result :outcome)
         (:complete
          (complete-command dispatcher command result))
         (:retry
          (retry-command dispatcher command result))
         (:fail
          (fail-command dispatcher command result))
         (:defer
          (fail 'invalid-envelope-error
                "A deferred actor result cannot defer the same command again."))
         (otherwise
          (fail 'invalid-envelope-error
                "Deferred actor returned unknown outcome ~S."
                (getf result :outcome))))))))