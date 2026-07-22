(defpackage #:star-lang.spec-domain.prototype
  (:use #:cl)
  (:export
   #:attach-dataset
   #:build-example-runtime
   #:dataset
   #:define-actor
   #:define-domain-server
   #:define-spec-library
   #:domain-server
   #:field
   #:invoke-actor
   #:make-entity-ref
   #:make-relation
   #:relations
   #:run-example
   #:run-tests))

(in-package #:star-lang.spec-domain.prototype)

(define-condition star-lang-error (error)
  ((message :initarg :message :reader star-lang-error-message))
  (:report (lambda (condition stream)
             (write-string (star-lang-error-message condition) stream))))

(define-condition spec-error (star-lang-error) ())
(define-condition import-error (spec-error) ())
(define-condition schema-error (star-lang-error) ())
(define-condition dataset-error (star-lang-error) ())
(define-condition actor-error (star-lang-error) ())
(define-condition domain-server-error (star-lang-error) ())
(define-condition test-error (star-lang-error) ())

(defstruct field-spec
  name
  type
  required-p)

(defstruct schema-definition
  id
  library
  name
  version
  persistence
  extends
  fields)

(defstruct predicate-definition
  id
  name
  source-schema
  destination-schema)

(defstruct spec-import
  library
  version
  digest)

(defstruct spec-library
  name
  version
  source
  digest
  imports)

(defstruct entity-ref
  schema-id
  id)

(defstruct (document (:constructor %make-document))
  schema-id
  id
  persistence
  fields)

(defstruct dataset-view
  name
  documents)

(defstruct actor-definition
  name
  accepts
  produces
  capabilities
  behavior)

(defstruct domain-server-definition
  name
  key-type
  owns
  indexes
  accepts
  restart
  capabilities)

(defstruct (runtime (:constructor %make-runtime))
  libraries
  schemas
  predicates
  datasets
  actors
  domain-servers
  events)

(defun make-runtime ()
  (%make-runtime
   :libraries (make-hash-table :test #'equal)
   :schemas (make-hash-table :test #'equal)
   :predicates (make-hash-table :test #'equal)
   :datasets (make-hash-table :test #'equal)
   :actors (make-hash-table :test #'eq)
   :domain-servers (make-hash-table :test #'eq)
   :events '()))

(defun fail (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun table-value (table key kind &optional condition-type)
  (multiple-value-bind (value present-p) (gethash key table)
    (unless present-p
      (fail (or condition-type 'spec-error) "Unknown ~A ~S." kind key))
    value))

(defun record-event (runtime type &rest payload)
  (push (list* :type type payload) (runtime-events runtime)))

(defun normalized-name (value)
  (string-downcase
   (etypecase value
     (string value)
     (symbol (symbol-name value)))))

(defun string-prefix-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun string-suffix-p (suffix string)
  (let ((offset (- (length string) (length suffix))))
    (and (>= offset 0)
         (string= suffix string :start2 offset))))

(defun remote-source-p (source)
  (and (stringp source) (string-prefix-p "https://" source)))

(defun digest-p (digest)
  (and (stringp digest)
       (> (length digest) 7)
       (string-prefix-p "sha256:" digest)))

(defun schema-id (library-name local-name)
  (format nil "~A/~A" library-name (normalized-name local-name)))

(defun schema-local-name (schema)
  (schema-definition-name schema))

(defun find-schema-by-local-name (runtime name)
  (let ((wanted (normalized-name name))
        (matches '()))
    (maphash
     (lambda (id schema)
       (declare (ignore id))
       (when (string= wanted (schema-local-name schema))
         (push schema matches)))
     (runtime-schemas runtime))
    (cond
      ((null matches)
       (fail 'schema-error "No schema named ~S is installed." name))
      ((cdr matches)
       (fail 'schema-error "Schema name ~S is ambiguous; use a qualified identifier." name))
      (t (first matches)))))

(defun parse-import (runtime declaration)
  (destructuring-bind (operator library-name &rest options) declaration
    (declare (ignore operator))
    (let ((version (getf options :version))
          (digest (getf options :digest)))
      (unless (and (stringp library-name) (stringp version) (digest-p digest))
        (fail 'import-error "Import ~S requires a library name, exact version, and sha256 digest."
              declaration))
      (let ((installed
              (table-value (runtime-libraries runtime)
                           library-name
                           "specification library"
                           'import-error)))
        (unless (and (string= version (spec-library-version installed))
                     (string= digest (spec-library-digest installed)))
          (fail 'import-error
                "Import ~A expected version ~A at ~A, installed version ~A at ~A."
                library-name
                version
                digest
                (spec-library-version installed)
                (spec-library-digest installed))))
      (make-spec-import :library library-name :version version :digest digest))))

(defun parse-field (field)
  (destructuring-bind (name type &rest options) field
    (make-field-spec
     :name (normalized-name name)
     :type type
     :required-p (not (null (getf options :required))))))

(defun copy-fields (fields)
  (mapcar #'copy-field-spec fields))

(defun register-schema-declaration (runtime library declaration)
  (destructuring-bind (operator local-name options &rest field-declarations) declaration
    (declare (ignore operator))
    (let* ((id (schema-id (spec-library-name library) local-name))
           (extends (getf options :extends))
           (declared-persistence (getf options :persistence))
           (base (and extends
                      (table-value (runtime-schemas runtime)
                                   extends
                                   "base schema"
                                   'schema-error)))
           (persistence (or declared-persistence
                            (and base (schema-definition-persistence base))))
           (fields (if base
                       (copy-fields (schema-definition-fields base))
                       '())))
      (when (gethash id (runtime-schemas runtime))
        (fail 'schema-error "Schema ~A is already installed." id))
      (unless (member persistence '(:persistent :transient) :test #'eq)
        (fail 'schema-error "Schema ~A requires :persistent or :transient persistence." id))
      (when (and base declared-persistence
                 (not (eq declared-persistence (schema-definition-persistence base))))
        (fail 'schema-error "Derived schema ~A cannot change persistence from ~S to ~S."
              id
              (schema-definition-persistence base)
              declared-persistence))
      (dolist (field-declaration field-declarations)
        (let* ((field (parse-field field-declaration))
               (name (field-spec-name field)))
          (when (find name fields :key #'field-spec-name :test #'string=)
            (fail 'schema-error
                  "Derived schema ~A cannot redefine inherited field ~A; extensions are additive."
                  id name))
          (push field fields)))
      (let ((schema
              (make-schema-definition
               :id id
               :library (spec-library-name library)
               :name (normalized-name local-name)
               :version (spec-library-version library)
               :persistence persistence
               :extends extends
               :fields (nreverse fields))))
        (setf (gethash id (runtime-schemas runtime)) schema)
        schema))))

(defun register-predicate-declaration (runtime library declaration)
  (destructuring-bind (operator local-name options) declaration
    (declare (ignore operator))
    (let* ((name (normalized-name local-name))
           (id (schema-id (spec-library-name library) local-name))
           (source (getf options :source))
           (destination (getf options :destination)))
      (table-value (runtime-schemas runtime) source "predicate source schema" 'schema-error)
      (table-value (runtime-schemas runtime) destination "predicate destination schema" 'schema-error)
      (when (gethash name (runtime-predicates runtime))
        (fail 'schema-error "Predicate name ~A is already installed." name))
      (let ((predicate
              (make-predicate-definition
               :id id
               :name name
               :source-schema source
               :destination-schema destination)))
        (setf (gethash name (runtime-predicates runtime)) predicate)
        predicate))))

(defun install-spec-library (runtime name options declarations)
  (let ((version (getf options :version))
        (source (getf options :source))
        (digest (getf options :digest)))
    (unless (and (stringp name) (stringp version) (stringp source))
      (fail 'spec-error "Specification libraries require string name, version, and source values."))
    (when (and (remote-source-p source) (not (digest-p digest)))
      (fail 'import-error "Remote specification library ~A requires a sha256 digest." name))
    (when (gethash name (runtime-libraries runtime))
      (fail 'spec-error "Specification library ~A is already installed." name))
    (let* ((import-declarations
             (remove-if-not
              (lambda (declaration)
                (string= "import" (normalized-name (first declaration))))
              declarations))
           (imports
             (mapcar (lambda (declaration) (parse-import runtime declaration))
                     import-declarations))
           (library
             (make-spec-library
              :name name
              :version version
              :source source
              :digest digest
              :imports imports)))
      (setf (gethash name (runtime-libraries runtime)) library)
      (dolist (declaration declarations)
        (let ((operator (normalized-name (first declaration))))
          (cond
            ((string= operator "import"))
            ((string= operator "document")
             (register-schema-declaration runtime library declaration))
            ((string= operator "predicate")
             (register-predicate-declaration runtime library declaration))
            (t
             (fail 'spec-error "Unknown specification declaration ~S." (first declaration))))))
      (record-event runtime :spec-installed :library name :version version :digest digest)
      library)))

(defmacro define-spec-library (runtime name options &body declarations)
  `(install-spec-library ,runtime ,name ',options ',declarations))

(defun field-entry (document field-name)
  (assoc (normalized-name field-name) (document-fields document) :test #'string=))

(defun field (document field-name)
  (let ((entry (field-entry document field-name)))
    (unless entry
      (fail 'schema-error "Document ~A has no field ~A."
            (document-id document)
            (normalized-name field-name)))
    (second entry)))

(defun email-address-p (value)
  (and (stringp value)
       (let ((at (position #\@ value)))
         (and at
              (> at 0)
              (< at (1- (length value)))
              (position #\. value :start (1+ at))))))

(defun map-value-p (value)
  (and (listp value)
       (every (lambda (entry)
                (and (listp entry) (= (length entry) 2)))
              value)))

(defun type-valid-p (runtime type value)
  (cond
    ((eq type :any) t)
    ((eq type :string) (stringp value))
    ((eq type :symbol) (symbolp value))
    ((eq type :boolean) (or (eq value t) (null value)))
    ((eq type :integer) (integerp value))
    ((eq type :email) (email-address-p value))
    ((eq type :reference) (entity-ref-p value))
    ((eq type :map) (map-value-p value))
    ((and (consp type) (eq (first type) :list))
     (and (listp value)
          (every (lambda (item) (type-valid-p runtime (second type) item)) value)))
    ((stringp type)
     (or (and (document-p value) (string= type (document-schema-id value)))
         (and (entity-ref-p value) (string= type (entity-ref-schema-id value)))))
    (t nil)))

(defun validate-document (runtime document)
  (unless (document-p document)
    (fail 'schema-error "Expected a document, received ~S." document))
  (let* ((schema
           (table-value (runtime-schemas runtime)
                        (document-schema-id document)
                        "schema"
                        'schema-error))
         (schema-fields (schema-definition-fields schema)))
    (unless (eq (schema-definition-persistence schema) (document-persistence document))
      (fail 'schema-error "Document ~A has persistence ~S but schema ~A requires ~S."
            (document-id document)
            (document-persistence document)
            (schema-definition-id schema)
            (schema-definition-persistence schema)))
    (dolist (entry (document-fields document))
      (unless (find (first entry) schema-fields :key #'field-spec-name :test #'string=)
        (fail 'schema-error "Schema ~A has no field ~A."
              (schema-definition-id schema)
              (first entry))))
    (dolist (field-spec schema-fields)
      (let ((entry (assoc (field-spec-name field-spec)
                          (document-fields document)
                          :test #'string=)))
        (when (and (field-spec-required-p field-spec) (null entry))
          (fail 'schema-error "Document ~A is missing required field ~A."
                (document-id document)
                (field-spec-name field-spec)))
        (when (and entry
                   (not (type-valid-p runtime
                                      (field-spec-type field-spec)
                                      (second entry))))
          (fail 'schema-error "Field ~A on document ~A does not satisfy ~S."
                (field-spec-name field-spec)
                (document-id document)
                (field-spec-type field-spec)))))
    document))

(defun make-document (runtime schema-id id &rest fields)
  (let ((schema
          (table-value (runtime-schemas runtime) schema-id "schema" 'schema-error)))
    (validate-document
     runtime
     (%make-document
      :schema-id schema-id
      :id id
      :persistence (schema-definition-persistence schema)
      :fields
      (mapcar (lambda (entry)
                (unless (and (listp entry) (= (length entry) 2))
                  (fail 'schema-error "Invalid field entry ~S." entry))
                (list (normalized-name (first entry)) (second entry)))
              fields)))))

(defun reference-for (document)
  (make-entity-ref :schema-id (document-schema-id document) :id (document-id document)))

(defun predicate-definition (runtime predicate)
  (table-value (runtime-predicates runtime)
               (normalized-name predicate)
               "predicate"
               'schema-error))

(defun validate-relation (runtime relation)
  (let* ((predicate (predicate-definition runtime (field relation 'predicate)))
         (source (field relation 'source))
         (destination (field relation 'destination)))
    (unless (and (entity-ref-p source)
                 (string= (entity-ref-schema-id source)
                          (predicate-definition-source-schema predicate)))
      (fail 'schema-error "Relation source must reference schema ~A."
            (predicate-definition-source-schema predicate)))
    (unless (and (entity-ref-p destination)
                 (string= (entity-ref-schema-id destination)
                          (predicate-definition-destination-schema predicate)))
      (fail 'schema-error "Relation destination must reference schema ~A."
            (predicate-definition-destination-schema predicate)))
    relation))

(defun make-relation (runtime id predicate source destination)
  (let ((relation-schema (find-schema-by-local-name runtime "relation")))
    (validate-relation
     runtime
     (make-document
      runtime
      (schema-definition-id relation-schema)
      id
      (list 'predicate predicate)
      (list 'source source)
      (list 'destination destination)))))

(defun entity-ref-equal-p (left right)
  (and (entity-ref-p left)
       (entity-ref-p right)
       (string= (entity-ref-schema-id left) (entity-ref-schema-id right))
       (equal (entity-ref-id left) (entity-ref-id right))))

(defun attach-dataset (runtime name documents)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (document documents)
      (validate-document runtime document)
      (let ((key (list (document-schema-id document) (document-id document))))
        (when (gethash key seen)
          (fail 'dataset-error "Dataset ~A contains duplicate document identity ~S." name key))
        (setf (gethash key seen) t)))
    (let ((view (make-dataset-view :name name :documents (copy-list documents))))
      (setf (gethash name (runtime-datasets runtime)) view)
      (record-event runtime :dataset-attached :dataset name :document-count (length documents))
      view)))

(defun dataset (runtime name)
  (table-value (runtime-datasets runtime) name "dataset" 'dataset-error))

(defun resolve-entity (dataset reference)
  (or
   (find-if
    (lambda (document)
      (and (string= (document-schema-id document) (entity-ref-schema-id reference))
           (equal (document-id document) (entity-ref-id reference))))
    (dataset-view-documents dataset))
   (fail 'dataset-error "Dataset ~A cannot resolve entity ~A/~A."
         (dataset-view-name dataset)
         (entity-ref-schema-id reference)
         (entity-ref-id reference))))

(defun relations (runtime dataset &key predicate source destination)
  (let ((predicate-definition
          (and predicate (predicate-definition runtime predicate))))
    (remove-if-not
     (lambda (document)
       (and (string= "relation"
                     (schema-definition-name
                      (table-value (runtime-schemas runtime)
                                   (document-schema-id document)
                                   "schema"
                                   'schema-error)))
            (or (null predicate-definition)
                (string= (predicate-definition-name predicate-definition)
                         (normalized-name (field document 'predicate))))
            (or (null source)
                (entity-ref-equal-p source (field document 'source)))
            (or (null destination)
                (entity-ref-equal-p destination (field document 'destination)))))
     (dataset-view-documents dataset))))

(defun register-actor (runtime name options behavior)
  (when (gethash name (runtime-actors runtime))
    (fail 'actor-error "Actor ~S is already registered." name))
  (let ((actor
          (make-actor-definition
           :name name
           :accepts (getf options :accepts)
           :produces (getf options :produces)
           :capabilities (copy-list (getf options :capabilities))
           :behavior behavior)))
    (setf (gethash name (runtime-actors runtime)) actor)
    actor))

(defmacro define-actor (runtime name options lambda-list &body body)
  `(register-actor ,runtime ',name ',options (lambda ,lambda-list ,@body)))

(defun invoke-actor (runtime name input)
  (let ((actor
          (table-value (runtime-actors runtime) name "actor" 'actor-error)))
    (unless (type-valid-p runtime (actor-definition-accepts actor) input)
      (fail 'actor-error "Actor ~S rejected its input." name))
    (record-event runtime :actor-invoked :actor name)
    (let ((result (funcall (actor-definition-behavior actor) input runtime)))
      (unless (type-valid-p runtime (actor-definition-produces actor) result)
        (fail 'actor-error "Actor ~S returned an invalid result." name))
      (record-event runtime :actor-result :actor name)
      result)))

(defun register-domain-server (runtime name options)
  (when (gethash name (runtime-domain-servers runtime))
    (fail 'domain-server-error "Domain server ~S is already registered." name))
  (let ((key-type (getf options :key-type))
        (owns (getf options :owns))
        (indexes (getf options :indexes))
        (restart (getf options :restart)))
    (table-value (runtime-schemas runtime) key-type "domain-server key schema" 'domain-server-error)
    (dolist (schema-id owns)
      (table-value (runtime-schemas runtime) schema-id "owned schema" 'domain-server-error))
    (dolist (index indexes)
      (destructuring-bind (index-name schema-id field-name) index
        (declare (ignore index-name))
        (let ((schema
                (table-value (runtime-schemas runtime)
                             schema-id
                             "indexed schema"
                             'domain-server-error)))
          (unless (find (normalized-name field-name)
                        (schema-definition-fields schema)
                        :key #'field-spec-name
                        :test #'string=)
            (fail 'domain-server-error "Domain server ~S indexes unknown field ~A on ~A."
                  name field-name schema-id)))))
    (unless (member restart '(:permanent :transient :temporary) :test #'eq)
      (fail 'domain-server-error "Domain server ~S has invalid restart policy ~S." name restart))
    (let ((definition
            (make-domain-server-definition
             :name name
             :key-type key-type
             :owns (copy-list owns)
             :indexes (copy-tree indexes)
             :accepts (copy-tree (getf options :accepts))
             :restart restart
             :capabilities (copy-list (getf options :capabilities)))))
      (setf (gethash name (runtime-domain-servers runtime)) definition)
      (record-event runtime :domain-server-registered :domain-server name)
      definition)))

(defmacro define-domain-server (runtime name options)
  `(register-domain-server ,runtime ',name ',options))

(defun domain-server (runtime name)
  (table-value (runtime-domain-servers runtime)
               name
               "domain server"
               'domain-server-error))

(defun install-core-library (runtime)
  (define-spec-library runtime "org.starintel/core@1"
    (:version "1.0.0"
     :source "file:///specs/org.starintel/core/v1/library.star"
     :digest "sha256:core-v1-example")
    (document person
      (:persistence :persistent)
      (given-name :string :required t)
      (family-name :string :required t))
    (document organization
      (:persistence :persistent)
      (name :string :required t)
      (domain :string :required t))
    (document relation
      (:persistence :persistent)
      (predicate :symbol :required t)
      (source :reference :required t)
      (destination :reference :required t))))

(defun install-employment-library (runtime &key
                                           (source "https://specs.starintel.actor/employment/v1/library.star")
                                           (digest "sha256:employment-v1-example")
                                           (import-digest "sha256:core-v1-example"))
  (define-spec-library runtime "org.starintel/employment@1"
    (:version "1.0.0" :source source :digest digest)
    (import "org.starintel/core@1"
      :version "1.0.0"
      :digest import-digest)
    (document employee
      (:extends "org.starintel/core@1/person" :persistence :persistent)
      (employee-number :string :required nil))
    (predicate employed
      (:source "org.starintel/core@1/person"
       :destination "org.starintel/core@1/organization"))))

(defun build-example-runtime ()
  (let ((runtime (make-runtime)))
    (install-core-library runtime)
    (install-employment-library runtime)
    (define-domain-server runtime employment-domain
      (:key-type "org.starintel/core@1/organization"
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
    (define-actor runtime combine-names-into-emails
      (:accepts (:list "org.starintel/core@1/relation")
       :produces (:list :email)
       :capabilities (:read-dataset))
      (employment-relations actor-runtime)
      (let ((view (dataset actor-runtime "flock")))
        (mapcar
         (lambda (relation)
           (let* ((person (resolve-entity view (field relation 'source)))
                  (organization (resolve-entity view (field relation 'destination))))
             (string-downcase
              (format nil "~A.~A@~A"
                      (field person 'given-name)
                      (field person 'family-name)
                      (field organization 'domain)))))
         employment-relations)))
    runtime))

(defun example-documents (runtime)
  (let* ((ada
           (make-document
            runtime
            "org.starintel/core@1/person"
            "person:ada"
            (list 'given-name "Ada")
            (list 'family-name "Lovelace")))
         (grace
           (make-document
            runtime
            "org.starintel/core@1/person"
            "person:grace"
            (list 'given-name "Grace")
            (list 'family-name "Hopper")))
         (organization
           (make-document
            runtime
            "org.starintel/core@1/organization"
            "organization:example-labs"
            (list 'name "Example Labs")
            (list 'domain "example.org")))
         (organization-ref (reference-for organization))
         (ada-relation
           (make-relation runtime
                          "relation:ada-example-labs"
                          'employed
                          (reference-for ada)
                          organization-ref))
         (grace-relation
           (make-relation runtime
                          "relation:grace-example-labs"
                          'employed
                          (reference-for grace)
                          organization-ref)))
    (values
     (list ada grace organization ada-relation grace-relation)
     organization-ref)))

(defun run-example ()
  (let ((runtime (build-example-runtime)))
    (multiple-value-bind (documents employer) (example-documents runtime)
      (let* ((view (attach-dataset runtime "flock" documents))
             (employment-relations
               (relations runtime view :predicate 'employed :destination employer))
             (emails
               (invoke-actor runtime 'combine-names-into-emails employment-relations)))
        (values runtime emails employment-relations employer)))))

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

(defun test-remote-library-requires-digest ()
  (let ((runtime (make-runtime)))
    (assert-true
     (condition-signaled-p
      'import-error
      (lambda ()
        (define-spec-library runtime "org.starintel/bad@1"
          (:version "1.0.0" :source "https://example.invalid/library.star")
          (document bad (:persistence :persistent) (name :string :required t)))))
     "remote libraries require digests")))

(defun test-import-lock-mismatch-rejected ()
  (let ((runtime (make-runtime)))
    (install-core-library runtime)
    (assert-true
     (condition-signaled-p
      'import-error
      (lambda ()
        (install-employment-library runtime :import-digest "sha256:not-the-installed-core")))
     "mismatched locked imports are rejected")))

(defun test-exact-import-lock-accepted ()
  (let ((runtime (make-runtime)))
    (install-core-library runtime)
    (install-employment-library runtime)
    (assert-true
     (gethash "org.starintel/employment@1" (runtime-libraries runtime))
     "exact locked imports are accepted")))

(defun test-extension-is-additive ()
  (let ((runtime (make-runtime)))
    (install-core-library runtime)
    (assert-true
     (condition-signaled-p
      'schema-error
      (lambda ()
        (define-spec-library runtime "org.starintel/bad-extension@1"
          (:version "1.0.0"
           :source "file:///specs/bad-extension.star"
           :digest "sha256:bad-extension-example")
          (import "org.starintel/core@1"
            :version "1.0.0"
            :digest "sha256:core-v1-example")
          (document bad-person
            (:extends "org.starintel/core@1/person" :persistence :persistent)
            (given-name :string :required nil)))))
     "derived schemas cannot redefine inherited fields")))

(defun test-relation-type-constraints ()
  (let* ((runtime (build-example-runtime))
         (person
           (make-document runtime
                          "org.starintel/core@1/person"
                          "person:test"
                          (list 'given-name "Test")
                          (list 'family-name "Person"))))
    (assert-true
     (condition-signaled-p
      'schema-error
      (lambda ()
        (make-relation runtime
                       "relation:invalid"
                       'employed
                       (reference-for person)
                       (reference-for person))))
     "relation destination schemas are enforced")))

(defun test-dataset-destination-filter ()
  (multiple-value-bind (runtime emails employment-relations employer) (run-example)
    (declare (ignore emails employer))
    (assert-equal 2 (length employment-relations) "destination-filtered relation count")
    (assert-true
     (every (lambda (relation) (eq 'employed (field relation 'predicate)))
            employment-relations)
     "relations retain the employed predicate")
    (assert-equal 5
                  (length (dataset-view-documents (dataset runtime "flock")))
                  "attached dataset document count")))

(defun test-email-actor-output ()
  (multiple-value-bind (runtime emails employment-relations employer) (run-example)
    (declare (ignore runtime employment-relations employer))
    (assert-equal
     '("ada.lovelace@example.org" "grace.hopper@example.org")
     emails
     "combined email addresses")))

(defun test-domain-server-metadata ()
  (let* ((runtime (build-example-runtime))
         (definition (domain-server runtime 'employment-domain)))
    (assert-equal "org.starintel/core@1/organization"
                  (domain-server-definition-key-type definition)
                  "domain-server key type")
    (assert-equal :transient
                  (domain-server-definition-restart definition)
                  "domain-server restart policy")
    (assert-equal 3
                  (length (domain-server-definition-indexes definition))
                  "domain-server index count")))

(defun run-tests ()
  (mapc #'funcall
        (list #'test-remote-library-requires-digest
              #'test-import-lock-mismatch-rejected
              #'test-exact-import-lock-accepted
              #'test-extension-is-additive
              #'test-relation-type-constraints
              #'test-dataset-destination-filter
              #'test-email-actor-output
              #'test-domain-server-metadata))
  t)
