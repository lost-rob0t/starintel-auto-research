(in-package #:star-lang.core)

(export '(actor-spec
          actor-spec-name
          actor-spec-handler
          compile-program
          make-memory-actor-adapter
          make-memory-source-adapter
          make-script-runtime
          memory-source-set
          parse-program-source
          register-runtime-handler
          run-script
          script-plan
          script-plan-hash
          script-plan-nodes
          script-runtime
          script-runtime-dataset
          script-runtime-events
          script-runtime-output
          script-runtime-send-count
          source-spec
          source-spec-kind
          source-spec-name
          star-lang-actor-adapter
          star-lang-source-adapter
          symbol-literal
          symbol-literal-name))

(defstruct symbol-literal
  name)

(defun symbol-character-p (character)
  (and character
       (not (whitespace-character-p character))
       (not (member character '(#\( #\) #\; #\" #\' #\` #\, #\#)
                    :test #'char=))))

(defun normalize-symbol-quotes (source source-name)
  (let ((output (copy-seq source))
        (in-string nil)
        (escaped nil)
        (in-comment nil))
    (loop for index from 0 below (length source)
          for character = (char source index)
          do
             (cond
               (in-comment
                (when (char= character #\Newline)
                  (setf in-comment nil)))
               (in-string
                (cond
                  (escaped (setf escaped nil))
                  ((char= character #\\) (setf escaped t))
                  ((char= character #\") (setf in-string nil))))
               ((char= character #\;) (setf in-comment t))
               ((char= character #\") (setf in-string t))
               ((char= character #\')
                (let ((next (when (< (1+ index) (length source))
                              (char source (1+ index)))))
                  (unless (symbol-character-p next)
                    (fail 'source-error :invalid-symbol-literal
                          (make-source-span
                           :source-name source-name
                           :start-offset index
                           :end-offset (1+ index)
                           :start-line 1
                           :start-column (1+ index)
                           :end-line 1
                           :end-column (+ index 2))
                          "Quote shorthand must precede one symbol."))
                  (setf (char output index) #\:)))))
    output))

(defun parse-program-source (source &key (source-name "<program>")
                                         (max-source-bytes 65536)
                                         (max-tokens 20000)
                                         (max-depth 128)
                                         (max-token-length 4096)
                                         (max-list-length 10000)
                                         (max-integer-magnitude 1000000000000000000))
  (let ((normalized (normalize-symbol-quotes source source-name)))
    (multiple-value-bind (tokens state)
        (tokenize-source normalized source-name
                         :max-source-bytes max-source-bytes
                         :max-tokens max-tokens
                         :max-depth max-depth
                         :max-token-length max-token-length
                         :max-list-length max-list-length
                         :max-integer-magnitude max-integer-magnitude)
      (declare (ignore state))
      (when (null tokens)
        (fail 'source-error :empty-source nil "Program source is empty."))
      (let ((stream (%make-token-stream
                     :tokens tokens
                     :source-name source-name
                     :max-depth max-depth
                     :max-list-length max-list-length))
            (forms '()))
        (loop while (token-stream-peek stream)
              do (push (parse-expression stream 0) forms))
        (nreverse forms)))))

(defstruct surface-node
  id
  operation
  arguments
  span)

(defstruct script-plan
  source-name
  source-hash
  hash
  nodes
  effects
  source-map)

(defstruct actor-spec
  name
  external-name
  handler
  state
  dispatcher
  queue-size
  parent)

(defstruct source-spec
  name
  kind
  options)

(defun canonical-surface-value (value)
  (cond
    ((surface-node-p value)
     (format nil "(~A ~A ~A)"
             (surface-node-id value)
             (surface-node-operation value)
             (canonical-surface-value (surface-node-arguments value))))
    ((actor-spec-p value)
     (format nil "(actor ~A ~A ~A ~A ~A ~A)"
             (actor-spec-name value)
             (actor-spec-external-name value)
             (actor-spec-handler value)
             (canonical-surface-value (actor-spec-state value))
             (canonical-surface-value (actor-spec-dispatcher value))
             (canonical-surface-value (actor-spec-queue-size value))))
    ((source-spec-p value)
     (format nil "(source ~A ~A ~A)"
             (source-spec-name value)
             (source-spec-kind value)
             (canonical-surface-value (source-spec-options value))))
    ((symbol-literal-p value)
     (format nil "'~A" (symbol-literal-name value)))
    ((consp value)
     (format nil "(~{~A~^ ~})" (mapcar #'canonical-surface-value value)))
    (t
     (canonical-value value))))

(defun make-surface-node* (operation arguments span)
  (let ((identifier
          (subseq
           (sha256-string
            (format nil "(~A ~D ~D ~A ~A)"
                    (source-span-source-name span)
                    (source-span-start-offset span)
                    (source-span-end-offset span)
                    operation
                    (canonical-surface-value arguments)))
           0 24)))
    (make-surface-node
     :id identifier
     :operation operation
     :arguments arguments
     :span span)))

(defun surface-form-name (syntax)
  (let ((items (syntax-list syntax)))
    (when items (syntax-name (first items)))))

(defun source-symbol-literal-value (datum)
  (make-symbol-literal :name (source-symbol-name datum)))

(defun compile-surface-expression (syntax)
  (let ((datum (syntax-object-datum syntax)))
    (cond
      ((source-symbol-p datum)
       (if (source-symbol-keyword-p datum)
           (make-surface-node*
            :literal
            (list :value (source-symbol-literal-value datum))
            (syntax-object-span syntax))
           (make-surface-node*
            :variable
            (list :name (source-symbol-name datum))
            (syntax-object-span syntax))))
      ((not (listp datum))
       (make-surface-node* :literal (list :value datum) (syntax-object-span syntax)))
      (t
       (compile-surface-call syntax)))))

(defun compile-surface-call (syntax)
  (let* ((items (syntax-list syntax))
         (name (and items (syntax-name (first items))))
         (span (syntax-object-span syntax))
         (arguments (rest items)))
    (labels ((compiled-arguments ()
               (mapcar #'compile-surface-expression arguments))
             (fixed (operation count)
               (unless (= (length arguments) count)
                 (fail 'compile-error :invalid-surface-arity span
                       "~A expects ~D argument~:P." name count))
               (make-surface-node* operation (compiled-arguments) span)))
      (cond
        ((member name '("and" "or" "list") :test #'string=)
         (make-surface-node*
          (intern (string-upcase name) :keyword)
          (compiled-arguments)
          span))
        ((string= name "not") (fixed :not 1))
        ((string= name "equal") (fixed :equal 2))
        ((string= name "document-type-p") (fixed :document-type-p 2))
        ((string= name "actor-ref") (fixed :actor-ref 1))
        ((string= name "dataset") (fixed :dataset 1))
        ((string= name "length") (fixed :length 1))
        ((string= name "send") (fixed :send 2))
        ((string= name "emit") (fixed :emit 1))
        ((string= name "document-ref")
         (unless (>= (length arguments) 2)
           (fail 'compile-error :invalid-document-ref span
                 "DOCUMENT-REF expects a document and at least one path segment."))
         (make-surface-node* :document-ref (compiled-arguments) span))
        (t
         (fail 'compile-error :unknown-surface-expression span
               "Unknown surface expression ~A." name))))))

(defun option-name (syntax)
  (let ((items (syntax-list syntax)))
    (unless (= (length items) 2)
      (fail 'compile-error :invalid-option (syntax-object-span syntax)
            "Options must have exactly one value."))
    (values (syntax-name (first items)) (second items))))

(defun compile-option-alist (options)
  (mapcar
   (lambda (option)
     (multiple-value-bind (name value) (option-name option)
       (cons name (compile-surface-expression value))))
   options))

(defun option-node (name options &optional default)
  (let ((entry (assoc name options :test #'string=)))
    (if entry (cdr entry) default)))

(defun literal-node-value (node &optional default)
  (if (and node (eq (surface-node-operation node) :literal))
      (getf (surface-node-arguments node) :value)
      default))

(defun literal-name (node &optional default)
  (let ((value (literal-node-value node default)))
    (cond
      ((symbol-literal-p value) (symbol-literal-name value))
      ((stringp value) value)
      (t default))))

(defun compile-actor-definition (syntax)
  (let* ((items (syntax-list syntax))
         (span (syntax-object-span syntax)))
    (unless (>= (length items) 3)
      (fail 'compile-error :invalid-actor-definition span
            "DEFINE-ACTOR expects a name and options."))
    (let* ((name (syntax-name (second items)))
           (options (compile-option-alist (subseq items 2)))
           (handler-node (option-node "receive" options))
           (external-node (option-node "name" options))
           (state-node (option-node "state" options
                                    (make-surface-node* :literal (list :value nil) span)))
           (dispatcher-node (option-node "dispatcher" options
                                         (make-surface-node*
                                          :literal
                                          (list :value (make-symbol-literal :name "shared"))
                                          span)))
           (queue-node (option-node "queue-size" options))
           (parent-node (option-node "parent" options)))
      (unless handler-node
        (fail 'compile-error :missing-actor-handler span
              "Actor ~A requires (:RECEIVE handler)." name))
      (make-surface-node*
       :define-actor
       (list :spec
             (make-actor-spec
              :name name
              :external-name (or (literal-name external-node) name)
              :handler (or (literal-name handler-node)
                           (and (eq (surface-node-operation handler-node) :variable)
                                (getf (surface-node-arguments handler-node) :name)))
              :state state-node
              :dispatcher dispatcher-node
              :queue-size queue-node
              :parent (or (literal-name parent-node)
                          (and parent-node
                               (eq (surface-node-operation parent-node) :variable)
                               (getf (surface-node-arguments parent-node) :name)))))
       span))))

(defun compile-source-definition (syntax kind)
  (let* ((items (syntax-list syntax))
         (span (syntax-object-span syntax)))
    (unless (>= (length items) 3)
      (fail 'compile-error :invalid-source-definition span
            "Source definition expects a name and options."))
    (make-surface-node*
     :define-source
     (list :spec
           (make-source-spec
            :name (syntax-name (second items))
            :kind kind
            :options (compile-option-alist (subseq items 2))))
     span)))

(defun expect-loop-clause (syntax expected)
  (unless (and (source-symbol-p (syntax-object-datum syntax))
               (string= (source-symbol-name (syntax-object-datum syntax)) expected))
    (fail 'compile-error :invalid-loop-clause (syntax-object-span syntax)
          "Expected loop clause ~A." expected)))

(defun compile-loop-form (syntax)
  (let* ((items (syntax-list syntax))
         (span (syntax-object-span syntax)))
    (unless (>= (length items) 7)
      (fail 'compile-error :invalid-loop span
            "LOOP expects FOR variable IN collection and an action clause."))
    (expect-loop-clause (second items) "for")
    (let ((variable (syntax-name (third items))))
      (expect-loop-clause (fourth items) "in")
      (let ((collection (compile-surface-expression (fifth items)))
            (filters '())
            (actions '())
            (collect-node nil)
            (append-node nil)
            (index 5))
        (loop while (< index (length items))
              do
                 (let ((clause (syntax-name (nth index items))))
                   (cond
                     ((member clause '("when" "unless") :test #'string=)
                      (when (>= (1+ index) (length items))
                        (fail 'compile-error :invalid-loop-clause span
                              "Loop clause ~A has no expression." clause))
                      (push (cons (if (string= clause "when") :when :unless)
                                  (compile-surface-expression (nth (1+ index) items)))
                            filters)
                      (incf index 2))
                     ((string= clause "do")
                      (when (>= (1+ index) (length items))
                        (fail 'compile-error :invalid-loop-clause span
                              "DO has no expression."))
                      (push (compile-surface-expression (nth (1+ index) items)) actions)
                      (incf index 2))
                     ((string= clause "collect")
                      (when collect-node
                        (fail 'compile-error :duplicate-loop-result span
                              "LOOP may have only one COLLECT clause."))
                      (setf collect-node
                            (compile-surface-expression (nth (1+ index) items)))
                      (incf index 2))
                     ((string= clause "append")
                      (when append-node
                        (fail 'compile-error :duplicate-loop-result span
                              "LOOP may have only one APPEND clause."))
                      (setf append-node
                            (compile-surface-expression (nth (1+ index) items)))
                      (incf index 2))
                     (t
                      (fail 'compile-error :unknown-loop-clause
                            (syntax-object-span (nth index items))
                            "Unknown loop clause ~A." clause))))
        (unless (or actions collect-node append-node)
          (fail 'compile-error :loop-without-body span
                "LOOP requires DO, COLLECT, or APPEND."))
        (make-surface-node*
         :loop
         (list :variable variable
               :collection collection
               :filters (nreverse filters)
               :actions (nreverse actions)
               :collect collect-node
               :append append-node)
         span)))))

(defun compile-load-documents (syntax)
  (let* ((items (syntax-list syntax))
         (span (syntax-object-span syntax)))
    (unless (>= (length items) 3)
      (fail 'compile-error :invalid-load-documents span
            "LOAD-DOCUMENTS expects a source and target variable."))
    (make-surface-node*
     :load-documents
     (list :source (syntax-name (second items))
           :target (syntax-name (third items))
           :options (compile-option-alist (subseq items 3)))
     span)))

(defun compile-program-form (syntax)
  (let* ((items (syntax-list syntax))
         (name (and items (syntax-name (first items))))
         (span (syntax-object-span syntax)))
    (cond
      ((string= name "attach-dataset")
       (unless (= (length items) 3)
         (fail 'compile-error :invalid-attach-dataset span
               "ATTACH-DATASET expects a name and document collection."))
       (make-surface-node*
        :attach-dataset
        (list :name (compile-surface-expression (second items))
              :documents (compile-surface-expression (third items)))
        span))
      ((string= name "define-actor")
       (compile-actor-definition syntax))
      ((string= name "start-actor")
       (unless (= (length items) 2)
         (fail 'compile-error :invalid-start-actor span
               "START-ACTOR expects one actor definition name."))
       (make-surface-node* :start-actor (list :name (syntax-name (second items))) span))
      ((string= name "stop-actor")
       (unless (= (length items) 2)
         (fail 'compile-error :invalid-stop-actor span
               "STOP-ACTOR expects one actor definition name."))
       (make-surface-node* :stop-actor (list :name (syntax-name (second items))) span))
      ((string= name "define-couchdb-source")
       (compile-source-definition syntax :couchdb))
      ((string= name "define-rabbitmq-source")
       (compile-source-definition syntax :rabbitmq))
      ((string= name "load-documents")
       (compile-load-documents syntax))
      ((string= name "loop")
       (compile-loop-form syntax))
      ((string= name "set")
       (unless (= (length items) 3)
         (fail 'compile-error :invalid-set span "SET expects a variable and value."))
       (make-surface-node*
        :set-variable
        (list :name (syntax-name (second items))
              :value (compile-surface-expression (third items)))
        span))
      ((member name '("send" "emit") :test #'string=)
       (compile-surface-expression syntax))
      (t
       (fail 'compile-error :unknown-program-form span
             "Unknown program form ~A." name))))

(defun node-effects (node)
  (case (surface-node-operation node)
    (:send '(:actor))
    (:start-actor '(:actor-start))
    (:stop-actor '(:actor-stop))
    (:load-documents '(:source-read))
    (:attach-dataset '(:dataset-attach))
    (:loop
     (remove-duplicates
      (mapcan #'node-effects
              (append (getf (surface-node-arguments node) :actions)
                      (remove nil
                              (list (getf (surface-node-arguments node) :collect)
                                    (getf (surface-node-arguments node) :append)))))
      :test #'eq))
    (otherwise '())))

(defun compile-program (source &key (source-name "<program>"))
  (let* ((syntax-forms (parse-program-source source :source-name source-name))
         (nodes (mapcar #'compile-program-form syntax-forms))
         (source-hash (sha256-string source))
         (effects (remove-duplicates (mapcan #'node-effects nodes) :test #'eq))
         (plan-hash
           (sha256-string
            (canonical-surface-value
             (list source-name source-hash effects nodes)))))
    (make-script-plan
     :source-name source-name
     :source-hash source-hash
     :hash plan-hash
     :nodes nodes
     :effects effects
     :source-map
     (mapcar (lambda (node)
               (list (surface-node-id node) (surface-node-span node)))
             nodes))))

(defclass star-lang-actor-adapter () ())

(defgeneric actor-adapter-start (adapter spec runtime))
(defgeneric actor-adapter-stop (adapter actor-name runtime))
(defgeneric actor-adapter-ref (adapter actor-name runtime))
(defgeneric actor-adapter-send (adapter actor-reference message runtime))
(defgeneric actor-adapter-shutdown (adapter runtime))

(defclass memory-actor-adapter (star-lang-actor-adapter)
  ((actors :initform (make-hash-table :test #'equal) :reader memory-actors)
   (messages :initform '() :accessor memory-actor-messages)))

(defun make-memory-actor-adapter ()
  (make-instance 'memory-actor-adapter))

(defmethod actor-adapter-start ((adapter memory-actor-adapter) spec runtime)
  (let ((name (actor-spec-name spec)))
    (when (gethash name (memory-actors adapter))
      (fail 'execution-error :actor-already-started nil
            "Actor ~A is already started." name))
    (setf (gethash name (memory-actors adapter)) spec)
    spec))

(defmethod actor-adapter-ref ((adapter memory-actor-adapter) actor-name runtime)
  (declare (ignore runtime))
  (or (gethash actor-name (memory-actors adapter))
      (fail 'execution-error :actor-not-started nil
            "Actor ~A is not started." actor-name)))

(defmethod actor-adapter-send ((adapter memory-actor-adapter) actor-reference message runtime)
  (let* ((spec actor-reference)
         (handler (runtime-handler runtime (actor-spec-handler spec))))
    (push (list (actor-spec-name spec) message) (memory-actor-messages adapter))
    (funcall handler message runtime)))

(defmethod actor-adapter-stop ((adapter memory-actor-adapter) actor-name runtime)
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
  (setf (gethash (normalize-name source-name) (memory-source-documents adapter))
        documents)
  adapter)

(defmethod source-adapter-read ((adapter memory-source-adapter) spec runtime &key limit)
  (declare (ignore runtime))
  (let ((documents
          (copy-list
           (or (gethash (source-spec-name spec) (memory-source-documents adapter))
               '()))))
    (if limit (subseq documents 0 (min limit (length documents))) documents)))

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
                                 (actor-adapter (make-memory-actor-adapter))
                                 couchdb-adapter rabbitmq-adapter)
  (let ((runtime (make-instance 'script-runtime :actor-adapter actor-adapter)))
    (dolist (entry environment)
      (setf (gethash (normalize-name (car entry))
                     (script-runtime-environment runtime))
            (cdr entry)))
    (dolist (entry handlers)
      (register-runtime-handler runtime (car entry) (cdr entry)))
    (when couchdb-adapter
      (setf (gethash :couchdb (script-runtime-source-adapters runtime))
            couchdb-adapter))
    (when rabbitmq-adapter
      (setf (gethash :rabbitmq (script-runtime-source-adapters runtime))
            rabbitmq-adapter))
    runtime))

(defun register-runtime-handler (runtime name function)
  (setf (gethash (normalize-name name) (script-runtime-handlers runtime)) function)
  runtime)

(defun runtime-handler (runtime name)
  (or (gethash (normalize-name name) (script-runtime-handlers runtime))
      (fail 'execution-error :unknown-runtime-handler nil
            "Runtime handler ~A is not registered." name)))

(defun runtime-variable (runtime name)
  (multiple-value-bind (value present-p)
      (gethash (normalize-name name) (script-runtime-environment runtime))
    (unless present-p
      (fail 'execution-error :unbound-program-variable nil
            "Program variable ~A is unbound." name))
    value))

(defun set-runtime-variable (runtime name value)
  (setf (gethash (normalize-name name) (script-runtime-environment runtime)) value)
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
       (multiple-value-bind (result present-p) (gethash normalized value)
         (unless present-p
           (multiple-value-setq (result present-p)
             (gethash (intern (string-upcase normalized) :keyword) value)))
         (unless present-p
           (fail 'execution-error :missing-document-path nil
                 "Map has no key ~A." normalized))
         result))
      ((listp value)
       (let ((entry
               (or (assoc normalized value :test #'equal)
                   (assoc (intern (string-upcase normalized) :keyword)
                          value :test #'eq)
                   (assoc (intern (string-upcase normalized) *package*)
                          value :test #'eq))))
         (unless entry
           (fail 'execution-error :missing-document-path nil
                 "Association list has no key ~A." normalized))
         (cdr entry)))
      (t
       (fail 'execution-error :invalid-document-path nil
             "Cannot read key ~A from ~S." normalized value)))))

(defun document-type-matches-p (document expected)
  (let ((expected-name (normalize-reference-key expected)))
    (and (core-document-p document)
         (string= (core-document-schema-name document) expected-name))))

(defun evaluate-surface-node (node runtime)
  (let ((arguments (surface-node-arguments node)))
    (case (surface-node-operation node)
      (:literal
       (literal-runtime-value (getf arguments :value)))
      (:variable
       (runtime-variable runtime (getf arguments :name)))
      (:list
       (mapcar (lambda (child) (evaluate-surface-node child runtime)) arguments))
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
               (mapcar (lambda (child) (evaluate-surface-node child runtime))
                       (rest arguments))
               :initial-value (evaluate-surface-node (first arguments) runtime)))
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
       (let ((actor (evaluate-surface-node (first arguments) runtime))
             (message (evaluate-surface-node (second arguments) runtime)))
         (incf (script-runtime-send-count runtime))
         (record-script-event runtime :message-sent node :message message)
         (actor-adapter-send
          (script-runtime-actor-adapter runtime) actor message runtime)))
      (:emit
       (let ((value (evaluate-surface-node (first arguments) runtime)))
         (push value (script-runtime-output runtime))
         (record-script-event runtime :value-emitted node :value value)
         value))
      (otherwise
       (execute-program-node node runtime)))))

(defun loop-filter-passes-p (filter runtime)
  (let ((value (evaluate-surface-node (cdr filter) runtime)))
    (if (eq (car filter) :when) value (not value))))

(defun execute-loop-node (node runtime)
  (let* ((arguments (surface-node-arguments node))
         (variable (getf arguments :variable))
         (collection (evaluate-surface-node (getf arguments :collection) runtime))
         (filters (getf arguments :filters))
         (actions (getf arguments :actions))
         (collect-node (getf arguments :collect))
         (append-node (getf arguments :append))
         (results '()))
    (dolist (item collection)
      (set-runtime-variable runtime variable item)
      (when (every (lambda (filter) (loop-filter-passes-p filter runtime)) filters)
        (dolist (action actions)
          (evaluate-surface-node action runtime))
        (when collect-node
          (push (evaluate-surface-node collect-node runtime) results))
        (when append-node
          (dolist (value (evaluate-surface-node append-node runtime))
            (push value results)))))
    (let ((ordered (nreverse results)))
      (when (or collect-node append-node)
        (push ordered (script-runtime-output runtime)))
      ordered)))

(defun evaluate-option-node (options name runtime &optional default)
  (let ((entry (assoc name options :test #'string=)))
    (if entry (evaluate-surface-node (cdr entry) runtime) default)))

(defun execute-program-node (node runtime)
  (let ((arguments (surface-node-arguments node)))
    (case (surface-node-operation node)
      (:set-variable
       (set-runtime-variable
        runtime
        (getf arguments :name)
        (evaluate-surface-node (getf arguments :value) runtime)))
      (:attach-dataset
       (let ((name (evaluate-surface-node (getf arguments :name) runtime))
             (documents (evaluate-surface-node (getf arguments :documents) runtime)))
         (setf (gethash name (script-runtime-datasets runtime)) documents)
         (record-script-event runtime :dataset-attached node
                              :name name :count (length documents))
         documents))
      (:define-actor
       (let ((spec (getf arguments :spec)))
         (setf (gethash (actor-spec-name spec)
                        (script-runtime-actor-definitions runtime))
               spec)
         (record-script-event runtime :actor-defined node :name (actor-spec-name spec))
         spec))
      (:start-actor
       (let* ((name (getf arguments :name))
              (spec (or (gethash name (script-runtime-actor-definitions runtime))
                        (fail 'execution-error :unknown-actor-definition
                              (surface-node-span node)
                              "Actor definition ~A does not exist." name)))
              (resolved
                (copy-actor-spec spec)))
         (setf (actor-spec-state resolved)
               (evaluate-surface-node (actor-spec-state spec) runtime)
               (actor-spec-dispatcher resolved)
               (normalize-reference-key
                (evaluate-surface-node (actor-spec-dispatcher spec) runtime))
               (actor-spec-queue-size resolved)
               (and (actor-spec-queue-size spec)
                    (evaluate-surface-node (actor-spec-queue-size spec) runtime)))
         (actor-adapter-start
          (script-runtime-actor-adapter runtime) resolved runtime)
         (record-script-event runtime :actor-started node :name name)
         resolved))
      (:stop-actor
       (let ((name (getf arguments :name)))
         (actor-adapter-stop (script-runtime-actor-adapter runtime) name runtime)
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
              (spec (or (gethash name (script-runtime-source-definitions runtime))
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
              (limit (evaluate-option-node options "limit" runtime nil))
              (dataset-name (evaluate-option-node options "dataset" runtime nil))
              (documents (source-adapter-read adapter spec runtime :limit limit)))
         (set-runtime-variable runtime (getf arguments :target) documents)
         (when dataset-name
           (setf (gethash dataset-name (script-runtime-datasets runtime)) documents))
         (record-script-event runtime :documents-loaded node
                              :source name :count (length documents))
         documents))
      (:loop
       (execute-loop-node node runtime))
      ((:literal :variable :list :and :or :not :equal :length
        :document-type-p :document-ref :actor-ref :dataset :send :emit)
       (evaluate-surface-node node runtime))
      (otherwise
       (fail 'execution-error :unknown-program-operation
             (surface-node-span node)
             "Unknown program operation ~S." (surface-node-operation node))))))

(defun run-script (plan runtime)
  (dolist (node (script-plan-nodes plan))
    (execute-program-node node runtime))
  (setf (script-runtime-events runtime)
        (nreverse (script-runtime-events runtime))
        (script-runtime-output runtime)
        (nreverse (script-runtime-output runtime)))
  (values (script-runtime-output runtime) runtime))
