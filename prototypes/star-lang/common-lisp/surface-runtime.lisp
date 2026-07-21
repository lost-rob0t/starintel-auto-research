(in-package #:star-lang.core)

(export '(make-memory-actor-adapter
          make-memory-source-adapter
          make-script-runtime
          memory-source-set
          register-runtime-handler
          run-script
          script-runtime
          script-runtime-dataset
          script-runtime-events
          script-runtime-output
          script-runtime-send-count
          star-lang-actor-adapter
          star-lang-source-adapter))

(defclass star-lang-actor-adapter () ())

(defgeneric actor-adapter-start (adapter spec runtime))
(defgeneric actor-adapter-stop (adapter actor-name runtime))
(defgeneric actor-adapter-ref (adapter actor-name runtime))
(defgeneric actor-adapter-send (adapter actor-reference message runtime))
(defgeneric actor-adapter-shutdown (adapter runtime))

(defclass memory-actor-adapter (star-lang-actor-adapter)
  ((actors :initform (make-hash-table :test #'equal)
           :reader memory-actors)
   (messages :initform '()
             :accessor memory-actor-messages)))

(defun make-memory-actor-adapter ()
  (make-instance 'memory-actor-adapter))

(defmethod actor-adapter-start ((adapter memory-actor-adapter) spec runtime)
  (declare (ignore runtime))
  (let ((name (actor-spec-name spec)))
    (when (gethash name (memory-actors adapter))
      (fail 'execution-error :actor-already-started nil
            "Actor ~A is already started." name))
    (setf (gethash name (memory-actors adapter)) spec)
    spec))

(defmethod actor-adapter-ref ((adapter memory-actor-adapter)
                              actor-name runtime)
  (declare (ignore runtime))
  (or (gethash actor-name (memory-actors adapter))
      (fail 'execution-error :actor-not-started nil
            "Actor ~A is not started." actor-name)))

(defmethod actor-adapter-send ((adapter memory-actor-adapter)
                               actor-reference message runtime)
  (let ((handler
          (runtime-handler runtime (actor-spec-handler actor-reference))))
    (push (list (actor-spec-name actor-reference) message)
          (memory-actor-messages adapter))
    (funcall handler message runtime)))

(defmethod actor-adapter-stop ((adapter memory-actor-adapter)
                               actor-name runtime)
  (declare (ignore runtime))
  (remhash actor-name (memory-actors adapter)))

(defmethod actor-adapter-shutdown ((adapter memory-actor-adapter) runtime)
  (declare (ignore runtime))
  (clrhash (memory-actors adapter)))

(defclass star-lang-source-adapter () ())
(defgeneric source-adapter-read (adapter spec runtime &key limit))

(defclass memory-source-adapter (star-lang-source-adapter)
  ((documents :initform (make-hash-table :test #'equal)
              :reader memory-source-documents)))

(defun make-memory-source-adapter ()
  (make-instance 'memory-source-adapter))

(defun memory-source-set (adapter source-name documents)
  (setf (gethash (normalize-name source-name)
                 (memory-source-documents adapter))
        documents)
  adapter)

(defmethod source-adapter-read ((adapter memory-source-adapter)
                                spec runtime &key limit)
  (declare (ignore runtime))
  (let ((documents
          (copy-list
           (or (gethash (source-spec-name spec)
                        (memory-source-documents adapter))
               '()))))
    (if limit
        (subseq documents 0 (min limit (length documents)))
        documents)))

(defstruct script-event
  sequence
  type
  node-id
  payload)

(defclass script-runtime ()
  ((environment :initform (make-hash-table :test #'equal)
                :reader script-runtime-environment)
   (datasets :initform (make-hash-table :test #'equal)
             :reader script-runtime-datasets)
   (actor-definitions :initform (make-hash-table :test #'equal)
                      :reader script-runtime-actor-definitions)
   (source-definitions :initform (make-hash-table :test #'equal)
                       :reader script-runtime-source-definitions)
   (handlers :initform (make-hash-table :test #'equal)
             :reader script-runtime-handlers)
   (actor-adapter :initarg :actor-adapter
                  :reader script-runtime-actor-adapter)
   (source-adapters :initform (make-hash-table :test #'eq)
                    :reader script-runtime-source-adapters)
   (events :initform '() :accessor script-runtime-events)
   (output :initform '() :accessor script-runtime-output)
   (send-count :initform 0 :accessor script-runtime-send-count)))

(defun make-script-runtime (&key environment handlers
                                 (actor-adapter
                                  (make-memory-actor-adapter))
                                 couchdb-adapter
                                 rabbitmq-adapter)
  (let ((runtime
          (make-instance 'script-runtime
                         :actor-adapter actor-adapter)))
    (dolist (entry environment)
      (setf (gethash (normalize-name (car entry))
                     (script-runtime-environment runtime))
            (cdr entry)))
    (dolist (entry handlers)
      (register-runtime-handler runtime (car entry) (cdr entry)))
    (when couchdb-adapter
      (setf (gethash :couchdb
                     (script-runtime-source-adapters runtime))
            couchdb-adapter))
    (when rabbitmq-adapter
      (setf (gethash :rabbitmq
                     (script-runtime-source-adapters runtime))
            rabbitmq-adapter))
    runtime))

(defun register-runtime-handler (runtime name function)
  (setf (gethash (normalize-name name)
                 (script-runtime-handlers runtime))
        function)
  runtime)

(defun runtime-handler (runtime name)
  (or (gethash (normalize-name name)
               (script-runtime-handlers runtime))
      (fail 'execution-error :unknown-runtime-handler nil
            "Runtime handler ~A is not registered." name)))

(defun runtime-variable (runtime name)
  (multiple-value-bind (value present-p)
      (gethash (normalize-name name)
               (script-runtime-environment runtime))
    (unless present-p
      (fail 'execution-error :unbound-program-variable nil
            "Program variable ~A is unbound." name))
    value))

(defun set-runtime-variable (runtime name value)
  (setf (gethash (normalize-name name)
                 (script-runtime-environment runtime))
        value)
  value)

(defun record-script-event (runtime type node &rest payload)
  (let ((event
          (make-script-event
           :sequence (1+ (length (script-runtime-events runtime)))
           :type type
           :node-id (and node (surface-node-id node))
           :payload payload)))
    (push event (script-runtime-events runtime))
    event))

(defun script-runtime-dataset (runtime name)
  (gethash name (script-runtime-datasets runtime)))

(defun literal-runtime-value (value)
  (if (symbol-literal-p value)
      (intern (string-upcase (symbol-literal-name value)) :keyword)
      value))

(defun normalize-reference-key (key)
  (cond
    ((symbol-literal-p key) (symbol-literal-name key))
    ((symbolp key) (string-downcase (symbol-name key)))
    ((stringp key) (string-downcase key))
    (t key)))

(defun map-reference (value key)
  (let ((normalized (normalize-reference-key key)))
    (cond
      ((core-document-p value)
       (document-field value normalized))
      ((hash-table-p value)
       (multiple-value-bind (result present-p)
           (gethash normalized value)
         (unless present-p
           (multiple-value-setq (result present-p)
             (gethash (intern (string-upcase normalized) :keyword)
                      value)))
         (unless present-p
           (fail 'execution-error :missing-document-path nil
                 "Map has no key ~A." normalized))
         result))
      ((listp value)
       (let ((entry
               (or (assoc normalized value :test #'equal)
                   (assoc (intern (string-upcase normalized) :keyword)
                          value :test #'eq))))
         (unless entry
           (fail 'execution-error :missing-document-path nil
                 "Association list has no key ~A." normalized))
         (if (and (listp entry) (= (length entry) 2))
             (second entry)
             (cdr entry))))
      (t
       (fail 'execution-error :invalid-document-path nil
             "Cannot read key ~A from ~S." normalized value)))))

(defun document-type-matches-p (document expected)
  (and (core-document-p document)
       (string= (core-document-schema-name document)
                (normalize-reference-key expected))))

(defun evaluate-surface-node (node runtime)
  (let ((arguments (surface-node-arguments node)))
    (case (surface-node-operation node)
      (:literal
       (literal-runtime-value (getf arguments :value)))
      (:variable
       (runtime-variable runtime (getf arguments :name)))
      (:list
       (mapcar (lambda (child)
                 (evaluate-surface-node child runtime))
               arguments))
      (:and
       (loop for child in arguments
             always (evaluate-surface-node child runtime)))
      (:or
       (loop for child in arguments
             thereis (evaluate-surface-node child runtime)))
      (:not
       (not (evaluate-surface-node (first arguments) runtime)))
      (:equal
       (equal (evaluate-surface-node (first arguments) runtime)
              (evaluate-surface-node (second arguments) runtime)))
      (:length
       (length (evaluate-surface-node (first arguments) runtime)))
      (:document-type-p
       (document-type-matches-p
        (evaluate-surface-node (first arguments) runtime)
        (evaluate-surface-node (second arguments) runtime)))
      (:document-ref
       (reduce #'map-reference
               (mapcar
                (lambda (child)
                  (evaluate-surface-node child runtime))
                (rest arguments))
               :initial-value
               (evaluate-surface-node (first arguments) runtime)))
      (:actor-ref
       (actor-adapter-ref
        (script-runtime-actor-adapter runtime)
        (normalize-reference-key
         (evaluate-surface-node (first arguments) runtime))
        runtime))
      (:dataset
       (script-runtime-dataset
        runtime
        (evaluate-surface-node (first arguments) runtime)))
      (:send
       (let ((actor
               (evaluate-surface-node (first arguments) runtime))
             (message
               (evaluate-surface-node (second arguments) runtime)))
         (incf (script-runtime-send-count runtime))
         (record-script-event runtime :message-sent node
                              :message message)
         (actor-adapter-send
          (script-runtime-actor-adapter runtime)
          actor message runtime)))
      (:emit
       (let ((value
               (evaluate-surface-node (first arguments) runtime)))
         (push value (script-runtime-output runtime))
         (record-script-event runtime :value-emitted node :value value)
         value))
      (otherwise
       (execute-program-node node runtime)))))

(defun loop-filter-passes-p (filter runtime)
  (let ((value (evaluate-surface-node (cdr filter) runtime)))
    (if (eq (car filter) :when)
        value
        (not value))))

(defun execute-loop-node (node runtime)
  (let* ((arguments (surface-node-arguments node))
         (variable (getf arguments :variable))
         (collection
           (evaluate-surface-node (getf arguments :collection) runtime))
         (filters (getf arguments :filters))
         (actions (getf arguments :actions))
         (collect-node (getf arguments :collect))
         (append-node (getf arguments :append))
         (results '()))
    (dolist (item collection)
      (set-runtime-variable runtime variable item)
      (when (every
             (lambda (filter)
               (loop-filter-passes-p filter runtime))
             filters)
        (dolist (action actions)
          (evaluate-surface-node action runtime))
        (when collect-node
          (push (evaluate-surface-node collect-node runtime) results))
        (when append-node
          (dolist (value
                   (evaluate-surface-node append-node runtime))
            (push value results)))))
    (let ((ordered (nreverse results)))
      (when (or collect-node append-node)
        (push ordered (script-runtime-output runtime)))
      ordered)))

(defun evaluate-option-node (options name runtime &optional default)
  (let ((entry (assoc name options :test #'string=)))
    (if entry
        (evaluate-surface-node (cdr entry) runtime)
        default)))

(defun execute-program-node (node runtime)
  (let ((arguments (surface-node-arguments node)))
    (case (surface-node-operation node)
      (:set-variable
       (set-runtime-variable
        runtime
        (getf arguments :name)
        (evaluate-surface-node (getf arguments :value) runtime)))
      (:attach-dataset
       (let ((name
               (evaluate-surface-node (getf arguments :name) runtime))
             (documents
               (evaluate-surface-node
                (getf arguments :documents) runtime)))
         (setf (gethash name (script-runtime-datasets runtime))
               documents)
         (record-script-event runtime :dataset-attached node
                              :name name
                              :count (length documents))
         documents))
      (:define-actor
       (let ((spec (getf arguments :spec)))
         (setf (gethash (actor-spec-name spec)
                        (script-runtime-actor-definitions runtime))
               spec)
         (record-script-event runtime :actor-defined node
                              :name (actor-spec-name spec))
         spec))
      (:start-actor
       (let* ((name (getf arguments :name))
              (spec
                (or (gethash name
                             (script-runtime-actor-definitions runtime))
                    (fail 'execution-error :unknown-actor-definition
                          (surface-node-span node)
                          "Actor definition ~A does not exist." name)))
              (resolved (copy-actor-spec spec)))
         (setf (actor-spec-state resolved)
               (evaluate-surface-node (actor-spec-state spec) runtime)
               (actor-spec-dispatcher resolved)
               (normalize-reference-key
                (evaluate-surface-node
                 (actor-spec-dispatcher spec) runtime))
               (actor-spec-queue-size resolved)
               (and (actor-spec-queue-size spec)
                    (evaluate-surface-node
                     (actor-spec-queue-size spec) runtime)))
         (actor-adapter-start
          (script-runtime-actor-adapter runtime)
          resolved runtime)
         (record-script-event runtime :actor-started node :name name)
         resolved))
      (:stop-actor
       (let ((name (getf arguments :name)))
         (actor-adapter-stop
          (script-runtime-actor-adapter runtime)
          name runtime)
         (record-script-event runtime :actor-stopped node :name name)
         t))
      (:define-source
       (let ((spec (getf arguments :spec)))
         (setf (gethash (source-spec-name spec)
                        (script-runtime-source-definitions runtime))
               spec)
         (record-script-event runtime :source-defined node
                              :name (source-spec-name spec)
                              :kind (source-spec-kind spec))
         spec))
      (:load-documents
       (let* ((name (getf arguments :source))
              (spec
                (or (gethash name
                             (script-runtime-source-definitions runtime))
                    (fail 'execution-error :unknown-source-definition
                          (surface-node-span node)
                          "Source definition ~A does not exist." name)))
              (adapter
                (or (gethash (source-spec-kind spec)
                             (script-runtime-source-adapters runtime))
                    (fail 'execution-error :missing-source-adapter
                          (surface-node-span node)
                          "No adapter is installed for source kind ~A."
                          (source-spec-kind spec))))
              (options (getf arguments :options))
              (limit
                (evaluate-option-node options "limit" runtime nil))
              (dataset-name
                (evaluate-option-node options "dataset" runtime nil))
              (documents
                (source-adapter-read adapter spec runtime :limit limit)))
         (set-runtime-variable runtime
                               (getf arguments :target)
                               documents)
         (when dataset-name
           (setf (gethash dataset-name
                          (script-runtime-datasets runtime))
                 documents))
         (record-script-event runtime :documents-loaded node
                              :source name
                              :count (length documents))
         documents))
      (:loop
       (execute-loop-node node runtime))
      ((:literal :variable :list :and :or :not :equal :length
        :document-type-p :document-ref :actor-ref :dataset :send :emit)
       (evaluate-surface-node node runtime))
      (otherwise
       (fail 'execution-error :unknown-program-operation
             (surface-node-span node)
             "Unknown program operation ~S."
             (surface-node-operation node))))))

(defun run-script (plan runtime)
  (dolist (node (script-plan-nodes plan))
    (execute-program-node node runtime))
  (setf (script-runtime-events runtime)
        (nreverse (script-runtime-events runtime))
        (script-runtime-output runtime)
        (nreverse (script-runtime-output runtime)))
  (values (script-runtime-output runtime) runtime))
