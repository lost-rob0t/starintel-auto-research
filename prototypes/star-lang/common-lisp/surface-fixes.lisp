(in-package #:star-lang.core)

(defun proper-surface-list-p (value)
  (loop
    (cond
      ((null value) (return t))
      ((consp value) (setf value (cdr value)))
      (t (return nil)))))

(defun canonical-surface-value (value)
  (cond
    ((surface-node-p value)
     (format nil "(~A ~A ~A)"
             (surface-node-id value)
             (surface-node-operation value)
             (canonical-surface-value (surface-node-arguments value))))
    ((actor-spec-p value)
     (format nil "(actor ~A ~A ~A ~A ~A ~A ~A)"
             (actor-spec-name value)
             (actor-spec-external-name value)
             (actor-spec-handler value)
             (canonical-surface-value (actor-spec-state value))
             (canonical-surface-value (actor-spec-dispatcher value))
             (canonical-surface-value (actor-spec-queue-size value))
             (canonical-surface-value (actor-spec-parent value))))
    ((source-spec-p value)
     (format nil "(source ~A ~A ~A)"
             (source-spec-name value)
             (source-spec-kind value)
             (canonical-surface-value (source-spec-options value))))
    ((symbol-literal-p value)
     (format nil "'~A" (symbol-literal-name value)))
    ((consp value)
     (if (proper-surface-list-p value)
         (format nil "(~{~A~^ ~})"
                 (mapcar #'canonical-surface-value value))
         (format nil "(~A . ~A)"
                 (canonical-surface-value (car value))
                 (canonical-surface-value (cdr value)))))
    (t
     (canonical-value value))))
