(in-package #:star-lang.core)

(export '(actor-spec
          actor-spec-handler
          actor-spec-name
          compile-program
          parse-program-source
          script-plan
          script-plan-hash
          script-plan-nodes
          source-spec
          source-spec-kind
          source-spec-name
          symbol-literal
          symbol-literal-name))

(defstruct symbol-literal name)

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

(defun surface-symbol-character-p (character)
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
                  (unless (surface-symbol-character-p next)
                    (fail 'source-error :invalid-symbol-literal nil
                          "Quote shorthand must precede one symbol in ~A."
                          source-name))
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
     (format nil "(~{~A~^ ~})" (mapcar #'canonical-surface-value value)))
    (t
     (canonical-value value))))

(defun make-surface-node* (operation arguments span)
  (make-surface-node
   :id (subseq
        (sha256-string
         (format nil "(~A ~D ~D ~A ~A)"
                 (source-span-source-name span)
                 (source-span-start-offset span)
                 (source-span-end-offset span)
                 operation
                 (canonical-surface-value arguments)))
        0 24)
   :operation operation
   :arguments arguments
   :span span))

(defun compile-surface-expression (syntax)
  (let ((datum (syntax-object-datum syntax)))
    (cond
      ((source-symbol-p datum)
       (if (source-symbol-keyword-p datum)
           (make-surface-node*
            :literal
            (list :value (make-symbol-literal
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
                 "DOCUMENT-REF expects a document and a path."))
         (make-surface-node* :document-ref (compiled-arguments) span))
        (t
         (fail 'compile-error :unknown-surface-expression span
               "Unknown surface expression ~A." name))))))

(defun compile-option-alist (options)
  (mapcar
   (lambda (option)
     (let ((items (syntax-list option)))
       (unless (= (length items) 2)
         (fail 'compile-error :invalid-option (syntax-object-span option)
               "Options must contain exactly one value."))
       (cons (syntax-name (first items))
             (compile-surface-expression (second items)))))
   options))

(defun option-node (name options &optional default)
  (let ((entry (assoc name options :test #'string=)))
    (if entry (cdr entry) default)))

(defun node-designator-name (node)
  (when node
    (case (surface-node-operation node)
      (:variable (getf (surface-node-arguments node) :name))
      (:literal
       (let ((value (getf (surface-node-arguments node) :value)))
         (cond
           ((symbol-literal-p value) (symbol-literal-name value))
           ((stringp value) value)))))))

(defun compile-actor-definition (syntax)
  (let* ((items (syntax-list syntax))
         (span (syntax-object-span syntax)))
    (unless (>= (length items) 3)
      (fail 'compile-error :invalid-actor-definition span
            "DEFINE-ACTOR expects a name and options."))
    (let* ((name (syntax-name (second items)))
           (options (compile-option-alist (subseq items 2)))
           (handler (node-designator-name (option-node "receive" options))))
      (unless handler
        (fail 'compile-error :missing-actor-handler span
              "Actor ~A requires (:RECEIVE handler)." name))
      (make-surface-node*
       :define-actor
       (list
        :spec
        (make-actor-spec
         :name name
         :external-name (or (node-designator-name (option-node "name" options))
                            name)
         :handler handler
         :state (option-node
                 "state" options
                 (make-surface-node* :literal (list :value nil) span))
         :dispatcher (option-node
                      "dispatcher" options
                      (make-surface-node*
                       :literal
                       (list :value (make-symbol-literal :name "shared"))
                       span))
         :queue-size (option-node "queue-size" options)
         :parent (node-designator-name (option-node "parent" options))))
       span))))

(defun compile-source-definition (syntax kind)
  (let* ((items (syntax-list syntax))
         (span (syntax-object-span syntax)))
    (unless (>= (length items) 3)
      (fail 'compile-error :invalid-source-definition span
            "Source definition expects a name and options."))
    (make-surface-node*
     :define-source
     (list
      :spec
      (make-source-spec
       :name (syntax-name (second items))
       :kind kind
       :options (compile-option-alist (subseq items 2))))
     span)))

(defun expect-loop-clause (syntax expected)
  (unless (and (source-symbol-p (syntax-object-datum syntax))
               (string= (source-symbol-name (syntax-object-datum syntax))
                        expected))
    (fail 'compile-error :invalid-loop-clause (syntax-object-span syntax)
          "Expected loop clause ~A." expected)))

(defun compile-loop-form (syntax)
  (let* ((items (syntax-list syntax))
         (span (syntax-object-span syntax)))
    (unless (>= (length items) 7)
      (fail 'compile-error :invalid-loop span
            "LOOP expects FOR variable IN collection and a body."))
    (expect-loop-clause (second items) "for")
    (expect-loop-clause (fourth items) "in")
    (let ((variable (syntax-name (third items)))
          (collection (compile-surface-expression (fifth items)))
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
                    (push
                     (cons (if (string= clause "when") :when :unless)
                           (compile-surface-expression
                            (nth (1+ index) items)))
                     filters)
                    (incf index 2))
                   ((string= clause "do")
                    (when (>= (1+ index) (length items))
                      (fail 'compile-error :invalid-loop-clause span
                            "DO has no expression."))
                    (push (compile-surface-expression
                           (nth (1+ index) items))
                          actions)
                    (incf index 2))
                   ((string= clause "collect")
                    (when collect-node
                      (fail 'compile-error :duplicate-loop-result span
                            "LOOP has more than one COLLECT clause."))
                    (setf collect-node
                          (compile-surface-expression
                           (nth (1+ index) items)))
                    (incf index 2))
                   ((string= clause "append")
                    (when append-node
                      (fail 'compile-error :duplicate-loop-result span
                            "LOOP has more than one APPEND clause."))
                    (setf append-node
                          (compile-surface-expression
                           (nth (1+ index) items)))
                    (incf index 2))
                   (t
                    (fail 'compile-error :unknown-loop-clause
                          (syntax-object-span (nth index items))
                          "Unknown loop clause ~A." clause)))))
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
       span))))

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
               "ATTACH-DATASET expects a name and documents."))
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
               "START-ACTOR expects one actor name."))
       (make-surface-node*
        :start-actor
        (list :name (syntax-name (second items)))
        span))
      ((string= name "stop-actor")
       (unless (= (length items) 2)
         (fail 'compile-error :invalid-stop-actor span
               "STOP-ACTOR expects one actor name."))
       (make-surface-node*
        :stop-actor
        (list :name (syntax-name (second items)))
        span))
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
         (fail 'compile-error :invalid-set span
               "SET expects a variable and value."))
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

(defun surface-node-effects (node)
  (case (surface-node-operation node)
    (:send '(:actor))
    (:start-actor '(:actor-start))
    (:stop-actor '(:actor-stop))
    (:load-documents '(:source-read))
    (:attach-dataset '(:dataset-attach))
    (:loop
     (remove-duplicates
      (mapcan #'surface-node-effects
              (append
               (getf (surface-node-arguments node) :actions)
               (remove nil
                       (list
                        (getf (surface-node-arguments node) :collect)
                        (getf (surface-node-arguments node) :append)))))
      :test #'eq))
    (otherwise '())))

(defun compile-program (source &key (source-name "<program>"))
  (let* ((forms (parse-program-source source :source-name source-name))
         (nodes (mapcar #'compile-program-form forms))
         (source-hash (sha256-string source))
         (effects
           (remove-duplicates
            (mapcan #'surface-node-effects nodes)
            :test #'eq))
         (hash
           (sha256-string
            (canonical-surface-value
             (list source-name source-hash effects nodes)))))
    (make-script-plan
     :source-name source-name
     :source-hash source-hash
     :hash hash
     :nodes nodes
     :effects effects
     :source-map
     (mapcar
      (lambda (node)
        (list (surface-node-id node) (surface-node-span node)))
      nodes))))
