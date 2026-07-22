(defpackage #:star-lang.compiler-ir.prototype
  (:use #:cl)
  (:export
   #:bind-cl-gserver
   #:compile-program
   #:define-star-program
   #:example-program
   #:run-example
   #:run-tests))

(in-package #:star-lang.compiler-ir.prototype)

(define-condition star-lang-compiler-error (error)
  ((message :initarg :message :reader compiler-error-message))
  (:report (lambda (condition stream)
             (write-string (compiler-error-message condition) stream))))

(define-condition invalid-declaration-error (star-lang-compiler-error) ())
(define-condition invalid-stage-error (star-lang-compiler-error) ())
(define-condition unresolved-spec-error (star-lang-compiler-error) ())
(define-condition adapter-binding-error (star-lang-compiler-error) ())
(define-condition test-error (star-lang-compiler-error) ())

(defun fail (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun identifier-string (value)
  (string-downcase
   (etypecase value
     (string value)
     (symbol (symbol-name value)))))

(defun string-prefix-p (prefix string)
  (and (stringp string)
       (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun digest-p (value)
  (and (stringp value)
       (> (length value) 7)
       (string-prefix-p "sha256:" value)))

(defun local-spec-path-p (value)
  (and (stringp value)
       (not (string-prefix-p "http://" value))
       (not (string-prefix-p "https://" value))))

(defun plist-has-key-p (plist key)
  (loop for tail on plist by #'cddr
        thereis (eq (first tail) key)))

(defun required-option (options key context &optional condition-type)
  (unless (plist-has-key-p options key)
    (fail (or condition-type 'invalid-declaration-error)
          "~A requires option ~S."
          context key))
  (getf options key))

(defun ensure-proper-plist (options context)
  (unless (and (listp options) (evenp (length options)))
    (fail 'invalid-declaration-error "~A requires a property list." context))
  options)

(defun normalize-type (value)
  (cond
    ((keywordp value) value)
    ((stringp value) value)
    ((symbolp value) (identifier-string value))
    ((consp value) (mapcar #'normalize-type value))
    (t value)))

(defun normalize-capabilities (value)
  (unless (listp value)
    (fail 'invalid-declaration-error "Capabilities must be a list."))
  (mapcar #'normalize-type value))

(defun compile-spec-import (import)
  (unless (and (listp import) (evenp (length import)))
    (fail 'unresolved-spec-error "Specification imports must be property lists."))
  (let ((name (required-option import :name "Specification import" 'unresolved-spec-error))
        (version (required-option import :version "Specification import" 'unresolved-spec-error))
        (digest (required-option import :digest "Specification import" 'unresolved-spec-error)))
    (unless (and (stringp name) (stringp version) (digest-p digest))
      (fail 'unresolved-spec-error
            "Specification import requires string name, exact version, and sha256 digest."))
    (list :name name :version version :digest digest)))

(defun compile-spec-library (library)
  (unless (and (listp library) (evenp (length library)))
    (fail 'unresolved-spec-error "Specification library entries must be property lists."))
  (let ((name (required-option library :name "Specification library" 'unresolved-spec-error))
        (version (required-option library :version "Specification library" 'unresolved-spec-error))
        (digest (required-option library :digest "Specification library" 'unresolved-spec-error))
        (path (required-option library :path "Specification library" 'unresolved-spec-error)))
    (unless (and (stringp name) (stringp version) (digest-p digest))
      (fail 'unresolved-spec-error
            "Specification library requires string name, exact version, and sha256 digest."))
    (unless (local-spec-path-p path)
      (fail 'unresolved-spec-error
            "Compiler received unresolved remote specification path ~S; resolve and lock it first."
            path))
    (list :name name
          :version version
          :digest digest
          :path path
          :origin (getf library :origin)
          :imports (mapcar #'compile-spec-import
                           (or (getf library :imports) '())))))

(defun compile-spec-graph (declaration)
  (destructuring-bind (operator options) declaration
    (declare (ignore operator))
    (ensure-proper-plist options "spec-graph")
    (let ((lock-digest (required-option options :lock-digest "spec-graph" 'unresolved-spec-error))
          (libraries (required-option options :libraries "spec-graph" 'unresolved-spec-error)))
      (unless (digest-p lock-digest)
        (fail 'unresolved-spec-error "spec-graph requires a sha256 lock digest."))
      (unless (and (listp libraries) libraries)
        (fail 'unresolved-spec-error "spec-graph requires at least one resolved library."))
      (list :kind :spec-graph
            :lock-digest lock-digest
            :libraries (mapcar #'compile-spec-library libraries)))))

(defun compile-document (declaration)
  (destructuring-bind (operator name options) declaration
    (declare (ignore operator))
    (ensure-proper-plist options "document")
    (let ((schema (required-option options :schema "document"))
          (persistence (required-option options :persistence "document")))
      (unless (stringp schema)
        (fail 'invalid-declaration-error "Document schema must be a locked schema identifier."))
      (unless (member persistence '(:persistent :transient) :test #'eq)
        (fail 'invalid-declaration-error "Document persistence must be :persistent or :transient."))
      (list :kind :document
            :name (identifier-string name)
            :schema schema
            :persistence persistence))))

(defun normalize-mailbox (mailbox)
  (unless (and (listp mailbox) (= (length mailbox) 2))
    (fail 'invalid-declaration-error "Actor mailbox must be (:bounded capacity)."))
  (destructuring-bind (kind capacity) mailbox
    (unless (and (eq kind :bounded) (integerp capacity) (> capacity 0))
      (fail 'invalid-declaration-error "Actor mailbox must be (:bounded positive-integer)."))
    (list :kind :bounded :capacity capacity)))

(defun compile-actor (declaration)
  (destructuring-bind (operator name options) declaration
    (declare (ignore operator))
    (ensure-proper-plist options "actor")
    (let ((accepts (required-option options :accepts "actor"))
          (produces (required-option options :produces "actor"))
          (handler (required-option options :handler "actor"))
          (mailbox (required-option options :mailbox "actor"))
          (restart (required-option options :restart "actor")))
      (unless (member restart '(:permanent :transient :temporary) :test #'eq)
        (fail 'invalid-declaration-error "Actor restart policy ~S is invalid." restart))
      (list :kind :actor
            :name (identifier-string name)
            :accepts (normalize-type accepts)
            :produces (normalize-type produces)
            :handler (identifier-string handler)
            :mailbox (normalize-mailbox mailbox)
            :restart restart
            :capabilities (normalize-capabilities (or (getf options :capabilities) '()))))))

(defun normalize-index (index)
  (unless (and (listp index) (= (length index) 3))
    (fail 'invalid-declaration-error
          "Domain-server indexes must be (name schema field)."))
  (destructuring-bind (name schema field) index
    (unless (stringp schema)
      (fail 'invalid-declaration-error "Domain-server index schema must be qualified."))
    (list :name (identifier-string name)
          :schema schema
          :field (identifier-string field))))

(defun compile-domain-server (declaration)
  (destructuring-bind (operator name options) declaration
    (declare (ignore operator))
    (ensure-proper-plist options "domain-server")
    (let ((key-schema (required-option options :key-schema "domain-server"))
          (owns (required-option options :owns "domain-server"))
          (indexes (required-option options :indexes "domain-server"))
          (accepts (required-option options :accepts "domain-server"))
          (restart (required-option options :restart "domain-server")))
      (unless (and (stringp key-schema)
                   (listp owns)
                   (every #'stringp owns)
                   (listp indexes)
                   (listp accepts))
        (fail 'invalid-declaration-error "Domain-server schema and protocol declarations are invalid."))
      (unless (member restart '(:permanent :transient :temporary) :test #'eq)
        (fail 'invalid-declaration-error "Domain-server restart policy ~S is invalid." restart))
      (list :kind :domain-server
            :name (identifier-string name)
            :authority :keyed-aggregate
            :actor-cardinality :per-key
            :key-schema key-schema
            :owns (copy-list owns)
            :indexes (mapcar #'normalize-index indexes)
            :accepts (copy-tree accepts)
            :restart restart
            :capabilities (normalize-capabilities (or (getf options :capabilities) '()))))))

(defun compile-relation-stage (dataflow-name index stage)
  (let ((options (rest stage)))
    (ensure-proper-plist options "relations stage")
    (let ((source (required-option options :source "relations stage" 'invalid-stage-error))
          (predicate (required-option options :predicate "relations stage" 'invalid-stage-error))
          (destination (required-option options :destination "relations stage" 'invalid-stage-error)))
      (list :node-id (format nil "~A/~3,'0D" dataflow-name index)
            :op :relations
            :source (normalize-type source)
            :predicate (normalize-type predicate)
            :destination (normalize-type destination)))))

(defun compile-stage (dataflow-name index stage target-names)
  (unless (and (listp stage) (symbolp (first stage)))
    (fail 'invalid-stage-error "Invalid dataflow stage ~S." stage))
  (let ((node-id (format nil "~A/~3,'0D" dataflow-name index))
        (operator (identifier-string (first stage))))
    (cond
      ((string= operator "from-dataset")
       (unless (and (= (length stage) 2) (stringp (second stage)))
         (fail 'invalid-stage-error "from-dataset requires one dataset name string."))
       (list :node-id node-id :op :from-dataset :dataset (second stage)))
      ((string= operator "relations")
       (compile-relation-stage dataflow-name index stage))
      ((string= operator "send")
       (unless (= (length stage) 3)
         (fail 'invalid-stage-error "send requires target and message operands."))
       (let ((target (identifier-string (second stage))))
         (unless (member target target-names :test #'string=)
           (fail 'invalid-stage-error "send targets undefined actor or domain server ~A." target))
         (list :node-id node-id
               :op :send
               :target target
               :message (normalize-type (third stage)))))
      ((string= operator "collect")
       (unless (= (length stage) 2)
         (fail 'invalid-stage-error "collect requires one binding name."))
       (list :node-id node-id :op :collect :binding (normalize-type (second stage))))
      (t
       (fail 'invalid-stage-error "Unknown dataflow stage ~S." (first stage))))))

(defun compile-dataflow (declaration target-names)
  (destructuring-bind (operator name &rest stages) declaration
    (declare (ignore operator))
    (let ((normalized-name (identifier-string name)))
      (unless stages
        (fail 'invalid-stage-error "Dataflow ~A has no stages." normalized-name))
      (list :kind :dataflow
            :name normalized-name
            :nodes (loop for stage in stages
                         for index from 0
                         collect (compile-stage normalized-name index stage target-names))))))

(defun declaration-kind (declaration)
  (unless (and (listp declaration) (symbolp (first declaration)))
    (fail 'invalid-declaration-error "Invalid declaration ~S." declaration))
  (identifier-string (first declaration)))

(defun declared-target-names (declarations)
  (loop for declaration in declarations
        for kind = (declaration-kind declaration)
        when (member kind '("actor" "domain-server") :test #'string=)
          collect (identifier-string (second declaration))))

(defun ensure-one-spec-graph (declarations)
  (let ((graphs (remove-if-not (lambda (declaration)
                                 (string= (declaration-kind declaration) "spec-graph"))
                               declarations)))
    (unless (= (length graphs) 1)
      (fail 'unresolved-spec-error "Program requires exactly one resolved spec-graph."))
    (first graphs)))

(defun compile-declaration (declaration target-names)
  (let ((kind (declaration-kind declaration)))
    (cond
      ((string= kind "spec-graph") (compile-spec-graph declaration))
      ((string= kind "document") (compile-document declaration))
      ((string= kind "actor") (compile-actor declaration))
      ((string= kind "domain-server") (compile-domain-server declaration))
      ((string= kind "dataflow") (compile-dataflow declaration target-names))
      (t
       (fail 'invalid-declaration-error "Unknown declaration ~S." (first declaration))))))

(defun compile-program (declarations)
  (unless (listp declarations)
    (fail 'invalid-declaration-error "Program declarations must be a list."))
  (ensure-one-spec-graph declarations)
  (let* ((target-names (declared-target-names declarations))
         (compiled (mapcar (lambda (declaration)
                             (compile-declaration declaration target-names))
                           declarations))
         (spec-graph (find :spec-graph compiled :key (lambda (item) (getf item :kind)))))
    (list :ir-version 1
          :spec-lock-digest (getf spec-graph :lock-digest)
          :declarations compiled)))

(defmacro define-star-program (&body declarations)
  `(compile-program ',declarations))

(defun declaration-by-kind (program kind)
  (remove-if-not (lambda (declaration) (eq (getf declaration :kind) kind))
                 (getf program :declarations)))

(defun bind-actor-manifest (actor)
  (list :kind :actor-manifest
        :name (getf actor :name)
        :runtime :cl-gserver
        :constructor :actor-of
        :send-operation :tell
        :handler (getf actor :handler)
        :accepts (copy-tree (getf actor :accepts))
        :produces (copy-tree (getf actor :produces))
        :mailbox (copy-tree (getf actor :mailbox))
        :restart (getf actor :restart)
        :capabilities (copy-list (getf actor :capabilities))))

(defun bind-domain-server-manifest (domain-server)
  (list :kind :domain-server-manifest
        :name (getf domain-server :name)
        :runtime :cl-gserver
        :constructor :actor-of
        :send-operation :tell
        :authority :keyed-aggregate
        :actor-cardinality :per-key
        :key-schema (getf domain-server :key-schema)
        :owns (copy-list (getf domain-server :owns))
        :indexes (copy-tree (getf domain-server :indexes))
        :accepts (copy-tree (getf domain-server :accepts))
        :restart (getf domain-server :restart)
        :capabilities (copy-list (getf domain-server :capabilities))))

(defun bind-node (node)
  (if (eq (getf node :op) :send)
      (list :node-id (getf node :node-id)
            :op :tell
            :actor (getf node :target)
            :message (copy-tree (getf node :message)))
      (copy-tree node)))

(defun bind-dataflow (dataflow)
  (list :kind :bound-dataflow
        :name (getf dataflow :name)
        :nodes (mapcar #'bind-node (getf dataflow :nodes))))

(defun bind-cl-gserver (program)
  (unless (and (listp program) (= (getf program :ir-version) 1))
    (fail 'adapter-binding-error "cl-gserver binder requires Star-Lang IR version 1."))
  (list :runtime :cl-gserver
        :ir-version 1
        :spec-lock-digest (getf program :spec-lock-digest)
        :actors (mapcar #'bind-actor-manifest (declaration-by-kind program :actor))
        :domain-servers
        (mapcar #'bind-domain-server-manifest
                (declaration-by-kind program :domain-server))
        :dataflows (mapcar #'bind-dataflow (declaration-by-kind program :dataflow))))

(defun example-program ()
  (define-star-program
    (spec-graph
     (:lock-digest "sha256:employment-lock-v1"
      :libraries
      ((:name "org.starintel/core@1"
        :version "1.0.0"
        :digest "sha256:core-v1-example"
        :path "spec-lock/org.starintel-core-1/library.star"
        :origin "https://specs.starintel.actor/core/v1/library.star")
       (:name "org.starintel/employment@1"
        :version "1.0.0"
        :digest "sha256:employment-v1-example"
        :path "spec-lock/org.starintel-employment-1/library.star"
        :origin "https://specs.starintel.actor/employment/v1/library.star"
        :imports ((:name "org.starintel/core@1"
                   :version "1.0.0"
                   :digest "sha256:core-v1-example"))))))
    (document relation
      (:schema "org.starintel/core@1/relation" :persistence :persistent))
    (actor combine-names-into-emails
      (:accepts (:list "org.starintel/core@1/relation")
       :produces (:list :email)
       :handler combine-names-handler
       :mailbox (:bounded 128)
       :restart :transient
       :capabilities (:read-dataset)))
    (domain-server employment-domain
      (:key-schema "org.starintel/core@1/organization"
       :owns ("org.starintel/core@1/person"
              "org.starintel/core@1/organization"
              "org.starintel/core@1/relation")
       :indexes ((by-predicate "org.starintel/core@1/relation" predicate)
                 (by-source "org.starintel/core@1/relation" source)
                 (by-destination "org.starintel/core@1/relation" destination))
       :accepts ((employees-for-organization :reference)
                 (relations-for-predicate :symbol))
       :restart :transient
       :capabilities (:read-dataset :write-transient)))
    (dataflow employment-emails
      (from-dataset "flock")
      (relations :source :any :predicate employed :destination employer)
      (send combine-names-into-emails :current)
      (collect emails))))

(defun run-example ()
  (let ((program (example-program)))
    (values program (bind-cl-gserver program))))

(defun condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S." label expected actual)))

(defun find-node (dataflow operation)
  (find operation (getf dataflow :nodes) :key (lambda (node) (getf node :op))))

(defun test-macro-expands-to-compiler-call ()
  (multiple-value-bind (expansion expanded-p)
      (macroexpand-1 '(define-star-program
                        (spec-graph
                         (:lock-digest "sha256:test-lock"
                          :libraries
                          ((:name "test/core"
                            :version "1.0.0"
                            :digest "sha256:test-core"
                            :path "spec-lock/test-core/library.star"))))))
    (assert-true expanded-p "define-star-program expands")
    (assert-equal 'compile-program (first expansion) "macro compiler entry point")))

(defun test-core-ir-preserves-runtime-neutral-send ()
  (let* ((program (example-program))
         (dataflow (first (declaration-by-kind program :dataflow)))
         (send (find-node dataflow :send)))
    (assert-true send "core IR contains send")
    (assert-equal "combine-names-into-emails" (getf send :target) "core send target")))

(defun test-cl-gserver-binding-lowers-send-to-tell ()
  (let* ((bound (bind-cl-gserver (example-program)))
         (dataflow (first (getf bound :dataflows)))
         (tell (find-node dataflow :tell))
         (actor (first (getf bound :actors))))
    (assert-true tell "bound dataflow contains tell")
    (assert-equal "combine-names-into-emails" (getf tell :actor) "tell actor")
    (assert-equal :actor-of (getf actor :constructor) "actor constructor")
    (assert-equal :tell (getf actor :send-operation) "actor send operation")))

(defun test-domain-server-is-keyed-authority ()
  (let* ((bound (bind-cl-gserver (example-program)))
         (domain-server (first (getf bound :domain-servers))))
    (assert-equal :keyed-aggregate (getf domain-server :authority) "domain authority")
    (assert-equal :per-key (getf domain-server :actor-cardinality) "domain actor cardinality")
    (assert-true (not (eq (getf domain-server :actor-cardinality) :per-document))
                 "domain server is not one actor per document")))

(defun test-remote-spec-path-is-rejected ()
  (assert-true
   (condition-signaled-p
    'unresolved-spec-error
    (lambda ()
      (compile-program
       '((spec-graph
          (:lock-digest "sha256:test-lock"
           :libraries
           ((:name "test/core"
             :version "1.0.0"
             :digest "sha256:test-core"
             :path "https://example.invalid/library.star"))))))))
   "compiler rejects unresolved remote specification path"))

(defun test-relations-require-explicit-positions ()
  (assert-true
   (condition-signaled-p
    'invalid-stage-error
    (lambda ()
      (compile-program
       '((spec-graph
          (:lock-digest "sha256:test-lock"
           :libraries
           ((:name "test/core"
             :version "1.0.0"
             :digest "sha256:test-core"
             :path "spec-lock/test-core/library.star"))))
         (dataflow broken
           (relations :predicate employed :destination employer))))))
   "relation traversal requires source, predicate, and destination"))

(defun test-unknown-send-target-is-rejected ()
  (assert-true
   (condition-signaled-p
    'invalid-stage-error
    (lambda ()
      (compile-program
       '((spec-graph
          (:lock-digest "sha256:test-lock"
           :libraries
           ((:name "test/core"
             :version "1.0.0"
             :digest "sha256:test-core"
             :path "spec-lock/test-core/library.star"))))
         (dataflow broken
           (send missing-actor :current))))))
   "send target must be declared"))

(defun test-compilation-is-deterministic ()
  (assert-equal (example-program) (example-program) "deterministic compilation"))

(defun run-tests ()
  (mapc #'funcall
        (list #'test-macro-expands-to-compiler-call
              #'test-core-ir-preserves-runtime-neutral-send
              #'test-cl-gserver-binding-lowers-send-to-tell
              #'test-domain-server-is-keyed-authority
              #'test-remote-spec-path-is-rejected
              #'test-relations-require-explicit-positions
              #'test-unknown-send-target-is-rejected
              #'test-compilation-is-deterministic))
  (format t "Star-Lang normalized IR and cl-gserver adapter tests passed.~%")
  t)
