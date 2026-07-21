(in-package #:star-lang.core)

(defparameter *canonical-surface-value-before-actor-protocols*
  (symbol-function 'canonical-surface-value))

(defun canonical-surface-value (value)
  (cond
    ((message-contract-p value)
     (format nil "(message-contract ~A ~A)"
             (message-contract-name value)
             (message-contract-schema value)))
    ((supervisor-spec-p value)
     (format nil "(supervisor ~A ~A ~D ~A)"
             (supervisor-spec-name value)
             (supervisor-spec-strategy value)
             (supervisor-spec-max-restarts value)
             (supervisor-spec-on-exhausted value)))
    ((actor-protocol-p value)
     (format nil "(actor-protocol ~A ~A ~A ~A)"
             (actor-protocol-actor-name value)
             (canonical-surface-value (actor-protocol-accepts value))
             (canonical-surface-value (actor-protocol-supervisor value))
             (canonical-surface-value
              (actor-protocol-restart-policy value))))
    (t
     (funcall *canonical-surface-value-before-actor-protocols* value))))
