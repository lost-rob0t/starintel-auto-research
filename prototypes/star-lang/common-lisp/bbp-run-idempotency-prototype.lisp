(in-package #:star-lang.core-surface.prototype)

(export '(bbp-program-run-result
          bbp-run-id-conflict-error))

(define-condition bbp-run-id-conflict-error (bbp-domain-error) ())

(defun bbp-program-run-result (engine program-id run-id)
  (let ((state
          (domain-server-engine-instance-state engine program-id)))
    (when state
      (let ((result
              (find run-id
                    (bbp-program-state-runs state)
                    :key (lambda (run)
                           (bbp-payload-value run :run-id))
                    :test #'string=)))
        (and result (copy-tree result))))))

(defun bbp-run-request-identity (payload engine)
  (let* ((program-id
           (required-bbp-payload payload :program-id "run-tool"))
         (run-id
           (required-bbp-payload payload :run-id "run-tool"))
         (tool
           (bbp-tool-by-name
            engine
            (required-bbp-payload payload :tool "run-tool")))
         (target
           (required-bbp-payload payload :target "run-tool")))
    (unless (and (stringp program-id)
                 (stringp run-id)
                 (stringp target))
      (fail 'bbp-domain-error
            "run-tool requires string program-id, run-id, and target."))
    (list :program-id program-id
          :run-id run-id
          :tool (getf tool :name)
          :target target)))

(defun bbp-run-result-matches-request-p (result identity)
  (and (string=
        (bbp-payload-value result :program-id)
        (getf identity :program-id))
       (string=
        (bbp-payload-value result :run-id)
        (getf identity :run-id))
       (string=
        (bbp-payload-value result :tool)
        (getf identity :tool))
       (string=
        (bbp-payload-value result :target)
        (getf identity :target))))

(defvar *bbp-run-tool-handler-without-idempotency*
  (symbol-function 'bbp-run-tool-handler))

(defun bbp-run-tool-handler (instance payload engine)
  (let* ((state (require-bbp-program-state instance))
         (identity (bbp-run-request-identity payload engine))
         (program-id (getf identity :program-id))
         (run-id (getf identity :run-id))
         (existing
           (find run-id
                 (bbp-program-state-runs state)
                 :key (lambda (run)
                        (bbp-payload-value run :run-id))
                 :test #'string=)))
    (unless (string= program-id
                     (bbp-program-state-program-id state))
      (fail 'bbp-domain-error
            "run-tool program ~A does not match domain key ~A."
            program-id
            (domain-server-instance-key instance)))
    (cond
      ((null existing)
       (funcall *bbp-run-tool-handler-without-idempotency*
                instance payload engine))
      ((bbp-run-result-matches-request-p existing identity)
       (copy-tree existing))
      (t
       (fail 'bbp-run-id-conflict-error
             "BBP run-id ~A was already used for a different tool request."
             run-id)))))

(defun bbp-invoke-command (engine command)
  (handler-case
      (let* ((message-type (getf command :message-type))
             (program-id (bbp-command-program-id command))
             (payload
               (invoke-domain-operation
                engine program-id message-type (getf command :payload))))
        (complete-dispatch
         :message-type (bbp-result-message-type message-type)
         :payload payload))
    (bbp-run-id-conflict-error (condition)
      (fail-dispatch
       :code "star.bbp.run-id-conflict"
       :message (princ-to-string condition)
       :retryable nil))
    (bbp-scope-error (condition)
      (fail-dispatch
       :code "star.bbp.out-of-scope"
       :message (princ-to-string condition)
       :retryable nil))
    ((or bbp-domain-error domain-tool-error domain-server-core-error) (condition)
      (fail-dispatch
       :code "star.bbp.domain-error"
       :message (princ-to-string condition)
       :retryable nil))
    (error (condition)
      (fail-dispatch
       :code "star.bbp.unexpected-error"
       :message (princ-to-string condition)
       :retryable nil))))
