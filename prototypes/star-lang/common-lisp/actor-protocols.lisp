(in-package #:star-lang.core)

(export '(actor-message-contract-violation
          actor-protocol
          actor-protocol-accepts
          actor-protocol-actor-name
          actor-protocol-restart-policy
          actor-protocol-supervisor
          message-contract
          message-contract-name
          message-contract-schema
          supervisor-spec
          supervisor-spec-max-restarts
          supervisor-spec-name
          supervisor-spec-on-exhausted
          supervisor-spec-strategy))

(define-condition actor-message-contract-violation (execution-error) ())

(defstruct message-contract
  name
  schema)

(defstruct supervisor-spec
  name
  strategy
  max-restarts
  on-exhausted)

(defstruct actor-protocol
  actor-name
  accepts
  supervisor
  restart-policy)

(defstruct runtime-protocol-state
  messages
  supervisors
  actors
  restart-counts)

(defparameter *runtime-protocol-states*
  (make-hash-table :test #'eq))

(defun make-runtime-protocol-state* ()
  (make-runtime-protocol-state
   :messages (make-hash-table :test #'equal)
   :supervisors (make-hash-table :test #'equal)
   :actors (make-hash-table :test #'equal)
   :restart-counts (make-hash-table :test #'equal)))

(defun runtime-protocol-state-for (runtime)
  (or (gethash runtime *runtime-protocol-states*)
      (setf (gethash runtime *runtime-protocol-states*)
            (make-runtime-protocol-state*))))

(defun option-designator-name (options name &optional default)
  (or (node-designator-name (option-node name options)) default))

(defun option-positive-integer (options name &optional default)
  (or (positive-literal-integer (option-node name options)) default))

(defparameter *compile-actor-definition-before-protocols*
  (symbol-function 'compile-actor-definition))

(defun compile-actor-definition (syntax)
  (let* ((node
           (funcall *compile-actor-definition-before-protocols* syntax))
         (items (syntax-list syntax))
         (options (compile-option-alist (subseq items 2)))
         (arguments (surface-node-arguments node)))
    (setf (surface-node-arguments node)
          (append
           arguments
           (list
            :accepts (option-node "accepts" options)
            :supervisor (option-designator-name options "supervisor")
            :restart-policy
            (option-designator-name options "restart" "permanent"))))
    node))

(defun compile-message-definition (syntax)
  (let* ((items (syntax-list syntax))
         (span (syntax-object-span syntax)))
    (unless (>= (length items) 3)
      (fail 'compile-error :invalid-message-definition span
            "DEFINE-MESSAGE expects a name and options."))
    (let* ((name (syntax-name (second items)))
           (options (compile-option-alist (subseq items 2)))
           (schema (option-designator-name options "schema")))
      (unless schema
        (fail 'compile-error :missing-message-schema span
              "Message ~A requires (:SCHEMA schema)." name))
      (make-surface-node*
       :define-message
       (list :contract
             (make-message-contract :name name :schema schema))
       span))))

(defun compile-supervisor-definition (syntax)
  (let* ((items (syntax-list syntax))
         (span (syntax-object-span syntax)))
    (unless (>= (length items) 2)
      (fail 'compile-error :invalid-supervisor-definition span
            "DEFINE-SUPERVISOR expects a name."))
    (let* ((name (syntax-name (second items)))
           (options (compile-option-alist (subseq items 2)))
           (strategy
             (option-designator-name options "strategy" "one-for-one"))
           (max-restarts
             (option-positive-integer options "max-restarts" 3))
           (on-exhausted
             (option-designator-name options "on-exhausted" "escalate")))
      (unless (member strategy '("one-for-one" "one-for-all")
                      :test #'string=)
        (fail 'compile-error :invalid-supervisor-strategy span
              "Supervisor ~A has unsupported strategy ~A."
              name strategy))
      (unless (member on-exhausted '("escalate" "stop") :test #'string=)
        (fail 'compile-error :invalid-supervisor-exhaustion-policy span
              "Supervisor ~A has unsupported exhaustion policy ~A."
              name on-exhausted))
      (make-surface-node*
       :define-supervisor
       (list :spec
             (make-supervisor-spec
              :name name
              :strategy strategy
              :max-restarts max-restarts
              :on-exhausted on-exhausted))
       span))))

(defparameter *compile-program-form-before-protocols*
  (symbol-function 'compile-program-form))

(defun compile-program-form (syntax)
  (let* ((items (syntax-list syntax))
         (name (and items (syntax-name (first items)))))
    (cond
      ((string= name "define-message")
       (compile-message-definition syntax))
      ((string= name "define-supervisor")
       (compile-supervisor-definition syntax))
      (t
       (funcall *compile-program-form-before-protocols* syntax)))))

(defun protocol-accepted-names (node runtime)
  (if node
      (mapcar #'normalize-reference-key
              (evaluate-surface-node node runtime))
      '()))

(defparameter *execute-program-node-before-protocols*
  (symbol-function 'execute-program-node))

(defun execute-program-node (node runtime)
  (let ((arguments (surface-node-arguments node))
        (state (runtime-protocol-state-for runtime)))
    (case (surface-node-operation node)
      (:define-message
       (let* ((contract (getf arguments :contract))
              (name (message-contract-name contract)))
         (setf (gethash name (runtime-protocol-state-messages state))
               contract)
         (record-script-event runtime :message-defined node
                              :name name
                              :schema (message-contract-schema contract))
         contract))
      (:define-supervisor
       (let* ((spec (getf arguments :spec))
              (name (supervisor-spec-name spec)))
         (setf (gethash name (runtime-protocol-state-supervisors state))
               spec)
         (record-script-event runtime :supervisor-defined node
                              :name name
                              :strategy (supervisor-spec-strategy spec))
         spec))
      (:define-actor
       (let* ((result
                (funcall *execute-program-node-before-protocols*
                         node runtime))
              (spec (getf arguments :spec))
              (protocol
                (make-actor-protocol
                 :actor-name (actor-spec-name spec)
                 :accepts
                 (protocol-accepted-names (getf arguments :accepts) runtime)
                 :supervisor (getf arguments :supervisor)
                 :restart-policy (getf arguments :restart-policy))))
         (setf (gethash (actor-spec-name spec)
                        (runtime-protocol-state-actors state))
               protocol)
         result))
      (otherwise
       (funcall *execute-program-node-before-protocols* node runtime)))))

(defun actor-name-from-reference-node (node)
  (when (and node (eq (surface-node-operation node) :actor-ref))
    (node-reference-name (first (surface-node-arguments node)))))

(defun accepted-message-schemas (runtime actor-name)
  (let* ((state (runtime-protocol-state-for runtime))
         (protocol
           (gethash actor-name (runtime-protocol-state-actors state))))
    (when protocol
      (mapcar
       (lambda (message-name)
         (let ((contract
                 (gethash message-name
                          (runtime-protocol-state-messages state))))
           (and contract (message-contract-schema contract))))
       (actor-protocol-accepts protocol)))))

(defun validate-actor-message (runtime actor-name message node)
  (let ((schemas (remove nil (accepted-message-schemas runtime actor-name))))
    (when schemas
      (unless (and (core-document-p message)
                   (member (core-document-schema-name message)
                           schemas :test #'string=))
        (fail 'actor-message-contract-violation
              :actor-message-contract-violation
              (surface-node-span node)
              "Actor ~A accepts schemas ~{~A~^, ~}; received ~A."
              actor-name
              schemas
              (if (core-document-p message)
                  (core-document-schema-name message)
                  (type-of message)))))))

(defparameter *evaluate-surface-node-before-protocols*
  (symbol-function 'evaluate-surface-node))

(defun evaluate-surface-node (node runtime)
  (if (eq (surface-node-operation node) :send)
      (let* ((arguments (surface-node-arguments node))
             (actor-node (first arguments))
             (message-node (second arguments))
             (actor-name (actor-name-from-reference-node actor-node))
             (actor (evaluate-surface-node actor-node runtime))
             (message (evaluate-surface-node message-node runtime)))
        (when actor-name
          (validate-actor-message runtime actor-name message node))
        (incf (script-runtime-send-count runtime))
        (record-script-event runtime :message-sent node
                             :actor actor-name
                             :message message)
        (actor-adapter-send
         (script-runtime-actor-adapter runtime)
         actor message runtime))
      (funcall *evaluate-surface-node-before-protocols* node runtime)))

(defun actor-protocol-for-spec (runtime spec)
  (gethash (actor-spec-name spec)
           (runtime-protocol-state-actors
            (runtime-protocol-state-for runtime))))

(defun actor-supervisor-spec (runtime protocol)
  (and protocol
       (actor-protocol-supervisor protocol)
       (gethash
        (actor-protocol-supervisor protocol)
        (runtime-protocol-state-supervisors
         (runtime-protocol-state-for runtime)))))

(defun actor-restart-key (protocol)
  (list (actor-protocol-supervisor protocol)
        (actor-protocol-actor-name protocol)))

(defun invoke-supervised-actor-handler (runtime spec message)
  (let ((handler (runtime-handler runtime (actor-spec-handler spec))))
    (handler-case
        (funcall handler message runtime)
      (error (cause)
        (let* ((state (runtime-protocol-state-for runtime))
               (protocol (actor-protocol-for-spec runtime spec))
               (supervisor (actor-supervisor-spec runtime protocol))
               (restart-policy
                 (and protocol (actor-protocol-restart-policy protocol))))
          (record-script-event runtime :actor-failed nil
                               :actor (actor-spec-name spec)
                               :message (princ-to-string cause))
          (when (or (null protocol)
                    (string= restart-policy "temporary")
                    (null supervisor))
            (error cause))
          (let* ((key (actor-restart-key protocol))
                 (count
                   (gethash key
                            (runtime-protocol-state-restart-counts state)
                            0)))
            (if (< count (supervisor-spec-max-restarts supervisor))
                (progn
                  (setf (gethash key
                                 (runtime-protocol-state-restart-counts state))
                        (1+ count))
                  (record-script-event runtime :actor-restarted nil
                                       :actor (actor-spec-name spec)
                                       :supervisor
                                       (supervisor-spec-name supervisor)
                                       :restart-count (1+ count))
                  :restarted)
                (progn
                  (record-script-event runtime :supervisor-exhausted nil
                                       :actor (actor-spec-name spec)
                                       :supervisor
                                       (supervisor-spec-name supervisor))
                  (error cause)))))))))

(defmethod actor-adapter-send ((adapter memory-actor-adapter)
                               actor-reference message runtime)
  (push (list (actor-spec-name actor-reference) message)
        (memory-actor-messages adapter))
  (invoke-supervised-actor-handler runtime actor-reference message))

(defparameter *lint-script-plan-before-protocols*
  (symbol-function 'lint-script-plan))

(defun lint-script-plan (plan)
  (let ((diagnostics
          (funcall *lint-script-plan-before-protocols* plan))
        (messages (make-hash-table :test #'equal))
        (supervisors (make-hash-table :test #'equal)))
    (labels ((emit (code node control &rest arguments)
               (push (apply #'analysis-diagnostic
                            :error code node control arguments)
                     diagnostics)))
      (dolist (node (script-plan-nodes plan))
        (let ((arguments (surface-node-arguments node)))
          (case (surface-node-operation node)
            (:define-message
             (let* ((contract (getf arguments :contract))
                    (name (message-contract-name contract)))
               (if (gethash name messages)
                   (emit :duplicate-message-definition node
                         "Message ~A is defined more than once." name)
                   (setf (gethash name messages) contract))))
            (:define-supervisor
             (let* ((spec (getf arguments :spec))
                    (name (supervisor-spec-name spec)))
               (if (gethash name supervisors)
                   (emit :duplicate-supervisor-definition node
                         "Supervisor ~A is defined more than once." name)
                   (setf (gethash name supervisors) spec))))
            (:define-actor
             (let* ((spec (getf arguments :spec))
                    (actor-name (actor-spec-name spec))
                    (accepts-node (getf arguments :accepts))
                    (supervisor (getf arguments :supervisor))
                    (restart-policy (getf arguments :restart-policy)))
               (when accepts-node
                 (dolist (message-name
                          (mapcar #'normalize-reference-key
                                  (mapcar #'literal-runtime-value
                                          (mapcar
                                           (lambda (child)
                                             (getf
                                              (surface-node-arguments child)
                                              :value))
                                           (surface-node-arguments
                                            accepts-node)))))
                   (unless (gethash message-name messages)
                     (emit :undefined-message-contract node
                           "Actor ~A accepts undefined message ~A."
                           actor-name message-name))))
               (when (and supervisor (not (gethash supervisor supervisors)))
                 (emit :undefined-supervisor node
                       "Actor ~A references undefined supervisor ~A."
                       actor-name supervisor))
               (unless (member restart-policy
                               '("permanent" "transient" "temporary")
                               :test #'string=)
                 (emit :invalid-actor-restart-policy node
                       "Actor ~A has invalid restart policy ~A."
                       actor-name restart-policy))))
            (otherwise nil)))))
    (nreverse diagnostics)))
