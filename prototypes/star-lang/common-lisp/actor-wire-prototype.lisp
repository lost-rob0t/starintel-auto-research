(in-package #:star-lang.core-surface.prototype)

(defun compile-actor (form &optional library)
  (unless (and (listp form)
               (= (length form) 3)
               (string= (declaration-kind form) "actor"))
    (fail 'invalid-actor-error "Expected (actor name (...options...))."))
  (destructuring-bind (operator name options) form
    (declare (ignore operator))
    (ensure-plist options "actor" 'invalid-actor-error)
    (let* ((runtime (normalize-runtime (required-option options :runtime "actor" 'invalid-actor-error)))
           (library-name (and library (getf library :name)))
           (local-types (and library
                             (loop for item in (getf library :declarations)
                                   when (member (getf item :kind)
                                                '(:scalar :enum :document :message))
                                     collect (getf item :name))))
           (normalize-contract
             (lambda (types)
               (unless (listp types)
                 (fail 'invalid-actor-error "Actor accepts/produces must be lists."))
               (mapcar (lambda (type)
                         (if library-name
                             (normalize-type-expression type library-name local-types)
                             (identifier-string type)))
                       types))))
      (let ((actor
              (list :kind :actor
                    :name (identifier-string name)
                    :runtime runtime
                    :accepts (funcall normalize-contract
                                      (required-option options :accepts "actor" 'invalid-actor-error))
                    :produces (funcall normalize-contract
                                       (required-option options :produces "actor" 'invalid-actor-error))
                    :restart (normalize-restart
                              (required-option options :restart "actor" 'invalid-actor-error))
                    :mailbox (normalize-mailbox
                              (required-option options :mailbox "actor" 'invalid-actor-error))
                    :capabilities (mapcar #'identifier-string
                                          (or (getf options :capabilities) '())))))
        (ecase runtime
          (:native
           (let ((handler (required-option options :handler "native actor" 'invalid-actor-error)))
             (setf actor (append actor (list :handler (identifier-string handler))))))
          (:external
           (let ((protocol (required-option options :protocol "external actor" 'invalid-actor-error))
                 (endpoint (required-option options :endpoint "external actor" 'invalid-actor-error)))
             (unless (stringp endpoint)
               (fail 'invalid-actor-error "External actor endpoint must be a string."))
             (setf actor
                   (append actor
                           (list :protocol (identifier-string protocol)
                                 :endpoint endpoint))))))
        actor))))

(defun bind-actor-runtime (actor)
  (ecase (getf actor :runtime)
    (:native
     (list :kind :actor-binding
           :name (getf actor :name)
           :runtime :cl-gserver
           :constructor :actor-of
           :send-operation :tell
           :handler (getf actor :handler)
           :accepts (copy-list (getf actor :accepts))
           :produces (copy-list (getf actor :produces))
           :restart (getf actor :restart)
           :mailbox (copy-tree (getf actor :mailbox))))
    (:external
     (list :kind :actor-binding
           :name (getf actor :name)
           :runtime :external
           :protocol (getf actor :protocol)
           :endpoint (getf actor :endpoint)
           :send-operation :dispatch
           :accepts (copy-list (getf actor :accepts))
           :produces (copy-list (getf actor :produces))
           :restart (getf actor :restart)
           :mailbox (copy-tree (getf actor :mailbox))))))

(defun declarations-of-kind (library kind)
  (remove-if-not (lambda (item) (eq (getf item :kind) kind))
                 (getf library :declarations)))

(defun portable-field (field)
  (let ((portable
          (list :name (getf field :name)
                :type (copy-tree (getf field :type))
                :required (getf field :required))))
    (if (getf field :default-p)
        (append portable (list :default (getf field :default)))
        portable)))

(defun portable-declaration (declaration)
  (case (getf declaration :kind)
    (:scalar
     (list :kind :scalar
           :name (getf declaration :qualified-name)
           :base (getf declaration :base)
           :pattern (getf declaration :pattern)
           :format (getf declaration :format)
           :minimum (getf declaration :minimum)
           :maximum (getf declaration :maximum)
           :scale (getf declaration :scale)))
    (:enum
     (list :kind :enum
           :name (getf declaration :qualified-name)
           :values (copy-list (getf declaration :values))))
    (:document
     (list :kind :document
           :name (getf declaration :qualified-name)
           :extends (getf declaration :extends)
           :persistence (getf declaration :persistence)
           :fields (mapcar #'portable-field (getf declaration :fields))))
    (:predicate
     (list :kind :predicate
           :name (getf declaration :qualified-name)
           :source (getf declaration :source)
           :destination (getf declaration :destination)))
    (:message
     (list :kind :message
           :name (getf declaration :qualified-name)
           :fields (mapcar #'portable-field (getf declaration :fields))))
    (otherwise
     (fail 'invalid-declaration-error
           "Cannot emit portable declaration for ~S."
           (getf declaration :kind)))))

(defun emit-portable-manifest (library actors)
  (unless (and (listp library) (eq (getf library :kind) :spec-library))
    (fail 'invalid-library-error "Portable manifest requires compiled spec library IR."))
  (list :wire-version 1
        :library (list :name (getf library :name)
                       :version (getf library :version)
                       :digest (getf library :digest))
        :imports (copy-tree (getf library :imports))
        :types (mapcar #'portable-declaration
                       (append (declarations-of-kind library :scalar)
                               (declarations-of-kind library :enum)
                               (declarations-of-kind library :document)))
        :predicates (mapcar #'portable-declaration
                            (declarations-of-kind library :predicate))
        :messages (mapcar #'portable-declaration
                          (declarations-of-kind library :message))
        :actors (mapcar (lambda (actor)
                          (list :name (getf actor :name)
                                :runtime (getf actor :runtime)
                                :protocol (getf actor :protocol)
                                :endpoint (getf actor :endpoint)
                                :accepts (copy-list (getf actor :accepts))
                                :produces (copy-list (getf actor :produces))))
                        actors)))

(defun make-wire-envelope (&key message-type message-id actor dataset reply-to payload)
  (unless (and (stringp message-type)
               (stringp message-id)
               (stringp actor))
    (fail 'invalid-envelope-error
          "Wire envelope requires string message-type, message-id, and actor."))
  (list :star-version 1
        :message-type message-type
        :message-id message-id
        :actor actor
        :dataset dataset
        :reply-to reply-to
        :payload payload))

(defun map-entry (map key)
  (cond
    ((and (listp map)
          (every #'consp map))
     (assoc key map :test #'string=))
    ((listp map)
     (let ((keyword (intern (string-upcase key) :keyword)))
       (when (plist-has-key-p map keyword)
         (cons key (getf map keyword)))))
    (t nil)))

(defun message-contract (manifest message-type)
  (find message-type (getf manifest :messages)
        :key (lambda (message) (getf message :name))
        :test #'string=))

(defun validate-wire-envelope (manifest envelope)
  (unless (= (getf envelope :star-version) 1)
    (fail 'invalid-envelope-error "Unsupported Star wire version."))
  (let* ((message-type (getf envelope :message-type))
         (contract (message-contract manifest message-type))
         (payload (getf envelope :payload)))
    (unless contract
      (fail 'invalid-envelope-error "Unknown message type ~A." message-type))
    (dolist (field (getf contract :fields))
      (when (and (getf field :required)
                 (null (map-entry payload (getf field :name))))
        (fail 'invalid-envelope-error
              "Message ~A is missing required field ~A."
              message-type (getf field :name))))
    t))
