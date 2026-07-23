(require :asdf)

(in-package #:star-lang.core-surface.prototype)

(export '(compile-domain-server
          compile-domain-tool
          domain-server-engine-instance-count
          domain-server-engine-instance-state
          domain-server-manifest-entry
          emit-domain-program-manifest
          invoke-domain-operation
          make-domain-server-engine
          make-process-tool-runner
          make-tool-runner-port
          run-domain-tool
          tool-command-argv))

(define-condition domain-server-core-error (star-lang-core-error) ())
(define-condition domain-tool-error (domain-server-core-error) ())

(defun domain-declarations-of-kind (library kind)
  (remove-if-not (lambda (declaration)
                   (eq (getf declaration :kind) kind))
                 (getf library :declarations)))

(defun declaration-qualified-names (library kind)
  (mapcar (lambda (declaration)
            (getf declaration :qualified-name))
          (domain-declarations-of-kind library kind)))

(defun local-qualified-declaration (library kind value context)
  (let* ((library-name (getf library :name))
         (qualified (qualify-name library-name value)))
    (unless (member qualified
                    (declaration-qualified-names library kind)
                    :test #'string=)
      (fail 'domain-server-core-error
            "~A references unknown ~A ~A."
            context kind qualified))
    qualified))

(defun normalize-domain-capabilities (values)
  (unless (listp values)
    (fail 'domain-server-core-error
          "Domain server capabilities must be a list."))
  (mapcar #'identifier-string values))

(defun normalize-tool-argv-template (value tool-name)
  (unless (and (listp value) value)
    (fail 'domain-tool-error
          "Tool ~A requires a nonempty argv template."
          tool-name))
  (dolist (item value)
    (unless (or (stringp item)
                (member item '(:target :program-id :run-id) :test #'eq))
      (fail 'domain-tool-error
            "Tool ~A argv item ~S is not a fixed string or supported placeholder."
            tool-name item)))
  (copy-list value))

(defun compile-domain-tool (form library)
  (unless (and (listp form)
               (= (length form) 3)
               (string= (declaration-kind form) "tool"))
    (fail 'domain-tool-error
          "Expected (tool name (...options...))."))
  (destructuring-bind (operator name options) form
    (declare (ignore operator))
    (ensure-plist options "tool" 'domain-tool-error)
    (let* ((normalized-name (identifier-string name))
           (executable
             (required-option options :executable "tool" 'domain-tool-error))
           (input
             (local-qualified-declaration
              library :scalar
              (required-option options :input "tool" 'domain-tool-error)
              (format nil "Tool ~A" normalized-name)))
           (produces
             (local-qualified-declaration
              library :message
              (required-option options :produces "tool" 'domain-tool-error)
              (format nil "Tool ~A" normalized-name)))
           (timeout-ms
             (required-option options :timeout-ms "tool" 'domain-tool-error)))
      (unless (and (stringp executable) (> (length executable) 0))
        (fail 'domain-tool-error
              "Tool ~A executable must be a nonempty string."
              normalized-name))
      (unless (and (integerp timeout-ms) (> timeout-ms 0))
        (fail 'domain-tool-error
              "Tool ~A timeout must be a positive integer."
              normalized-name))
      (list :kind :tool
            :name normalized-name
            :executable executable
            :argv-template
            (normalize-tool-argv-template
             (required-option options :argv "tool" 'domain-tool-error)
             normalized-name)
            :input input
            :produces produces
            :timeout-ms timeout-ms
            :capabilities
            (mapcar #'identifier-string
                    (or (getf options :capabilities) '()))))))

(defun tool-name-set (tools)
  (mapcar (lambda (tool) (getf tool :name)) tools))

(defun compile-domain-server (form library tools)
  (unless (and (listp form)
               (= (length form) 3)
               (string= (declaration-kind form) "domain-server"))
    (fail 'domain-server-core-error
          "Expected (domain-server name (...options...))."))
  (destructuring-bind (operator name options) form
    (declare (ignore operator))
    (ensure-plist options "domain-server" 'domain-server-core-error)
    (let* ((normalized-name (identifier-string name))
           (key-type
             (local-qualified-declaration
              library :scalar
              (required-option options :key-type
                               "domain-server"
                               'domain-server-core-error)
              (format nil "Domain server ~A" normalized-name)))
           (owns
             (mapcar
              (lambda (value)
                (local-qualified-declaration
                 library :document value
                 (format nil "Domain server ~A" normalized-name)))
              (required-option options :owns
                               "domain-server"
                               'domain-server-core-error)))
           (accepts
             (mapcar
              (lambda (value)
                (local-qualified-declaration
                 library :message value
                 (format nil "Domain server ~A" normalized-name)))
              (required-option options :accepts
                               "domain-server"
                               'domain-server-core-error)))
           (declared-tools
             (mapcar #'identifier-string
                     (required-option options :tools
                                      "domain-server"
                                      'domain-server-core-error)))
           (available-tools (tool-name-set tools)))
      (dolist (tool declared-tools)
        (unless (member tool available-tools :test #'string=)
          (fail 'domain-server-core-error
                "Domain server ~A references undeclared tool ~A."
                normalized-name tool)))
      (list :kind :domain-server
            :name normalized-name
            :key-type key-type
            :owns owns
            :accepts accepts
            :tools declared-tools
            :restart
            (normalize-restart
             (required-option options :restart
                              "domain-server"
                              'domain-server-core-error))
            :mailbox
            (normalize-mailbox
             (required-option options :mailbox
                              "domain-server"
                              'domain-server-core-error))
            :dispatcher
            (identifier-string (or (getf options :dispatcher) 'default))
            :capabilities
            (normalize-domain-capabilities
             (or (getf options :capabilities) '()))))))

(defun portable-domain-tool (tool)
  (list :name (getf tool :name)
        :executable (getf tool :executable)
        :argv-template (copy-list (getf tool :argv-template))
        :input (getf tool :input)
        :produces-message (getf tool :produces)
        :timeout-ms (getf tool :timeout-ms)
        :capabilities (copy-list (getf tool :capabilities))))

(defun domain-server-manifest-entry (definition)
  (list :name (getf definition :name)
        :authority :keyed-aggregate
        :key-type (getf definition :key-type)
        :owns (copy-list (getf definition :owns))
        :accepts (copy-list (getf definition :accepts))
        :tools (copy-list (getf definition :tools))
        :restart (getf definition :restart)
        :mailbox (copy-tree (getf definition :mailbox))
        :dispatcher (getf definition :dispatcher)
        :capabilities (copy-list (getf definition :capabilities))))

(defun emit-domain-program-manifest (library actors tools domain-servers)
  (append
   (emit-core-manifest library actors)
   (list :tools (mapcar #'portable-domain-tool tools)
         :domain-servers
         (mapcar #'domain-server-manifest-entry domain-servers))))

(defstruct (tool-runner-port (:constructor %make-tool-runner-port))
  run-fn)

(defun make-tool-runner-port (&key run)
  (unless (functionp run)
    (fail 'domain-tool-error
          "Tool runner operation must be a function."))
  (%make-tool-runner-port :run-fn run))

(defun request-option (request key)
  (cond
    ((and (listp request) (every #'consp request))
     (cdr (assoc (identifier-string key) request :test #'string=)))
    ((listp request)
     (getf request key))
    (t nil)))

(defun required-request-option (request key context)
  (or (request-option request key)
      (fail 'domain-tool-error
            "~A requires request value ~A."
            context key)))

(defun tool-command-argv (tool request)
  (let ((values
          (list (cons :target
                      (required-request-option request :target "Tool command"))
                (cons :program-id
                      (required-request-option request :program-id "Tool command"))
                (cons :run-id
                      (required-request-option request :run-id "Tool command")))))
    (cons
     (getf tool :executable)
     (mapcar
      (lambda (item)
        (if (keywordp item)
            (let ((entry (assoc item values :test #'eq)))
              (unless entry
                (fail 'domain-tool-error
                      "Tool ~A has unresolved argv placeholder ~S."
                      (getf tool :name) item))
              (let ((value (cdr entry)))
                (unless (stringp value)
                  (fail 'domain-tool-error
                        "Tool ~A placeholder ~S requires a string value."
                        (getf tool :name) item))
                value))
            item))
      (getf tool :argv-template)))))

(defun validate-tool-run-result (tool result)
  (ensure-plist result "tool run result" 'domain-tool-error)
  (unless (integerp (getf result :exit-code))
    (fail 'domain-tool-error
          "Tool ~A result requires integer exit-code."
          (getf tool :name)))
  (dolist (key '(:stdout :stderr))
    (unless (stringp (getf result key))
      (fail 'domain-tool-error
            "Tool ~A result requires string ~A."
            (getf tool :name) key)))
  result)

(defun run-domain-tool (runner tool request)
  (unless (tool-runner-port-p runner)
    (fail 'domain-tool-error
          "Domain tool execution requires a tool runner port."))
  (let ((argv (tool-command-argv tool request)))
    (handler-case
        (let ((result
                (funcall (tool-runner-port-run-fn runner)
                         tool argv request)))
          (validate-tool-run-result tool result)
          (append result (list :argv argv)))
      (domain-tool-error (condition)
        (error condition))
      (error (condition)
        (fail 'domain-tool-error
              "Tool ~A execution failed: ~A"
              (getf tool :name) condition)))))

(defun tool-timeout-duration (tool)
  (format nil "~,3Fs" (/ (getf tool :timeout-ms) 1000.0)))

(defun make-process-tool-runner ()
  (make-tool-runner-port
   :run
   (lambda (tool argv request)
     (declare (ignore request))
     (let ((command
             (append (list "timeout"
                           "--signal=TERM"
                           "--kill-after=5s"
                           (tool-timeout-duration tool))
                     argv)))
       (multiple-value-bind (stdout stderr exit-code)
           (uiop:run-program command
                             :output :string
                             :error-output :string
                             :ignore-error-status t
                             :force-shell nil)
         (list :exit-code exit-code
               :stdout (or stdout "")
               :stderr (or stderr "")))))))

(defstruct (domain-server-instance
            (:constructor make-domain-server-instance (&key key state)))
  key
  state)

(defstruct (domain-server-engine
            (:constructor %make-domain-server-engine))
  definition
  (tools (make-hash-table :test #'equal))
  tool-runner
  (handlers (make-hash-table :test #'equal))
  initializer
  (instances (make-hash-table :test #'equal)))

(defun make-domain-handler-table (handlers)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (entry handlers)
      (unless (and (consp entry)
                   (stringp (car entry))
                   (functionp (cdr entry)))
        (fail 'domain-server-core-error
              "Domain handlers must be (qualified-message . function) pairs."))
      (when (gethash (car entry) table)
        (fail 'domain-server-core-error
              "Duplicate domain handler for ~A."
              (car entry)))
      (setf (gethash (car entry) table) (cdr entry)))
    table))

(defun make-domain-tool-table (tools)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (tool tools)
      (let ((name (getf tool :name)))
        (when (gethash name table)
          (fail 'domain-tool-error "Duplicate tool ~A." name))
        (setf (gethash name table) tool)))
    table))

(defun make-domain-server-engine
    (&key definition tools tool-runner handlers initializer)
  (unless (and (listp definition)
               (eq (getf definition :kind) :domain-server))
    (fail 'domain-server-core-error
          "Domain engine requires compiled domain-server IR."))
  (unless (functionp initializer)
    (fail 'domain-server-core-error
          "Domain engine initializer must be a function."))
  (let ((handler-table (make-domain-handler-table handlers)))
    (dolist (message-type (getf definition :accepts))
      (unless (gethash message-type handler-table)
        (fail 'domain-server-core-error
              "Domain server ~A has no handler for ~A."
              (getf definition :name) message-type)))
    (%make-domain-server-engine
     :definition definition
     :tools (make-domain-tool-table tools)
     :tool-runner tool-runner
     :handlers handler-table
     :initializer initializer)))

(defun domain-server-engine-instance-count (engine)
  (hash-table-count (domain-server-engine-instances engine)))

(defun ensure-domain-server-instance (engine key)
  (or (gethash key (domain-server-engine-instances engine))
      (setf (gethash key (domain-server-engine-instances engine))
            (make-domain-server-instance
             :key key
             :state (funcall (domain-server-engine-initializer engine)
                             key engine)))))

(defun domain-server-engine-instance-state (engine key)
  (let ((instance (gethash key (domain-server-engine-instances engine))))
    (and instance (domain-server-instance-state instance))))

(defun invoke-domain-operation (engine key message-type payload)
  (unless (domain-server-engine-p engine)
    (fail 'domain-server-core-error
          "Domain operation requires a domain-server engine."))
  (required-nonempty-string key "domain key")
  (required-nonempty-string message-type "domain message type")
  (unless (member message-type
                  (getf (domain-server-engine-definition engine) :accepts)
                  :test #'string=)
    (fail 'domain-server-core-error
          "Domain server ~A does not accept ~A."
          (getf (domain-server-engine-definition engine) :name)
          message-type))
  (let ((handler (gethash message-type
                          (domain-server-engine-handlers engine))))
    (unless handler
      (fail 'domain-server-core-error
            "Domain server ~A has no runtime handler for ~A."
            (getf (domain-server-engine-definition engine) :name)
            message-type))
    (funcall handler
             (ensure-domain-server-instance engine key)
             payload
             engine)))
