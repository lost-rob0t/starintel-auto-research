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

(defun compile-surface-expression (syntax)
  (let ((datum (syntax-object-datum syntax)))
    (cond
      ((null datum)
       (make-surface-node*
        :literal
        (list :value nil)
        (syntax-object-span syntax)))
      ((source-symbol-p datum)
       (if (source-symbol-keyword-p datum)
           (make-surface-node*
            :literal
            (list :value
                  (make-symbol-literal
                   :name (source-symbol-name datum)))
            (syntax-object-span syntax))
           (make-surface-node*
            :variable
            (list :name (source-symbol-name datum))
            (syntax-object-span syntax))))
      ((not (listp datum))
       (make-surface-node*
        :literal
        (list :value datum)
        (syntax-object-span syntax)))
      (t
       (compile-surface-call syntax)))))

(defun surface-node-effects (node)
  (case (surface-node-operation node)
    (:send (list :actor))
    (:start-actor (list :actor-start))
    (:stop-actor (list :actor-stop))
    (:load-documents (list :source-read))
    (:attach-dataset (list :dataset-attach))
    (:loop
     (remove-duplicates
      (mapcan
       (lambda (child)
         (copy-list (surface-node-effects child)))
       (append
        (getf (surface-node-arguments node) :actions)
        (remove nil
                (list
                 (getf (surface-node-arguments node) :collect)
                 (getf (surface-node-arguments node) :append)))))
      :test #'eq))
    (otherwise nil)))
