(defpackage #:star-lang.prototype
  (:use #:cl)
  (:export
   #:benchmark-example
   #:build-example-runtime
   #:dataflow-plan
   #:document
   #:document-fields
   #:document-persistence
   #:document-ref
   #:document-type
   #:example-expansions
   #:load-fixture
   #:make-runtime
   #:run-dataflow
   #:run-example
   #:run-tests
   #:transient-document))

(in-package #:star-lang.prototype)

(define-condition star-lang-error (error)
  ((message :initarg :message :reader star-lang-error-message))
  (:report (lambda (condition stream)
             (write-string (star-lang-error-message condition) stream))))

(define-condition fixture-read-error (star-lang-error) ())
(define-condition schema-error (star-lang-error) ())
(define-condition persistence-error (star-lang-error) ())
(define-condition definition-error (star-lang-error) ())
(define-condition execution-error (star-lang-error) ())

(defstruct field-spec
  name
  type
  required-p)

(defstruct document-schema
  name
  persistence
  fields)

(defstruct (document (:constructor %make-document))
  type
  persistence
  fields)

(defstruct actor-definition
  name
  accepts
  produces
  behavior)

(defstruct tool-definition
  name
  input-type
  output-type
  function)

(defstruct agent-definition
  name
  accepts
  produces
  tools
  behavior)

(defstruct dataflow-definition
  name
  source-stages
  plan)

(defstruct (runtime (:constructor %make-runtime))
  schemas
  actors
  tools
  agents
  dataflows
  pure-functions
  persisted
  events)

(defun make-runtime ()
  (%make-runtime
   :schemas (make-hash-table :test #'eq)
   :actors (make-hash-table :test #'eq)
   :tools (make-hash-table :test #'eq)
   :agents (make-hash-table :test #'eq)
   :dataflows (make-hash-table :test #'eq)
   :pure-functions (make-hash-table :test #'eq)
   :persisted '()
   :events '()))

(defun fail (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun table-value (table key kind)
  (multiple-value-bind (value present-p) (gethash key table)
    (unless present-p
      (fail 'definition-error "Unknown ~A ~S." kind key))
    value))

(defun register-document-schema (runtime schema)
  (setf (gethash (document-schema-name schema) (runtime-schemas runtime)) schema)
  schema)

(defun register-actor (runtime actor)
  (setf (gethash (actor-definition-name actor) (runtime-actors runtime)) actor)
  actor)

(defun register-tool (runtime tool)
  (setf (gethash (tool-definition-name tool) (runtime-tools runtime)) tool)
  tool)

(defun register-agent (runtime agent)
  (dolist (tool-name (agent-definition-tools agent))
    (table-value (runtime-tools runtime) tool-name "tool"))
  (setf (gethash (agent-definition-name agent) (runtime-agents runtime)) agent)
  agent)

(defun register-pure-function (runtime name function)
  (setf (gethash name (runtime-pure-functions runtime)) function)
  function)

(defmacro define-document (runtime name options &body fields)
  (let ((persistence (getf options :persistence)))
    `(register-document-schema
      ,runtime
      (make-document-schema
       :name ',name
       :persistence ',persistence
       :fields
       (list
        ,@(mapcar
           (lambda (field)
             (destructuring-bind (field-name field-type &rest field-options) field
               `(make-field-spec
                 :name ',field-name
                 :type ',field-type
                 :required-p ,(not (null (getf field-options :required))))))
           fields))))))

(defmacro define-pure (runtime name lambda-list &body body)
  `(register-pure-function ,runtime ',name (lambda ,lambda-list ,@body)))

(defmacro define-actor (runtime name options lambda-list &body body)
  `(register-actor
    ,runtime
    (make-actor-definition
     :name ',name
     :accepts ',(getf options :accepts)
     :produces ',(getf options :produces)
     :behavior (lambda ,lambda-list ,@body))))

(defmacro define-tool (runtime name options lambda-list &body body)
  `(register-tool
    ,runtime
    (make-tool-definition
     :name ',name
     :input-type ',(getf options :input)
     :output-type ',(getf options :output)
     :function (lambda ,lambda-list ,@body))))

(defmacro define-agent (runtime name options lambda-list &body body)
  `(register-agent
    ,runtime
    (make-agent-definition
     :name ',name
     :accepts ',(getf options :accepts)
     :produces ',(getf options :produces)
     :tools ',(getf options :tools)
     :behavior (lambda ,lambda-list ,@body))))

(defmacro define-dataflow (runtime name &body stages)
  `(register-dataflow ,runtime ',name ',stages))

(defun record-event (runtime type &rest payload)
  (push (list* :type type payload) (runtime-events runtime)))

(defun ordered-events (runtime)
  (reverse (copy-list (runtime-events runtime))))

(defun association-value (key associations)
  (let ((entry (assoc key associations :test #'eq)))
    (values (second entry) (not (null entry)))))

(defun field-entry (document field-name)
  (assoc field-name (document-fields document) :test #'eq))

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
                (and (consp entry)
                     (symbolp (first entry))
                     (= (length entry) 2)))
              value)))

(defun type-valid-p (runtime type value)
  (cond
    ((eq type :string) (stringp value))
    ((eq type :boolean) (or (eq value t) (null value)))
    ((eq type :integer) (integerp value))
    ((eq type :number) (numberp value))
    ((eq type :symbol) (symbolp value))
    ((eq type :email) (email-address-p value))
    ((eq type :map) (map-value-p value))
    ((eq type :any) t)
    ((and (consp type) (eq (first type) :list))
     (and (listp value)
          (every (lambda (item)
                   (type-valid-p runtime (second type) item))
                 value)))
    ((keywordp type)
     (and (document-p value)
          (eq (document-type value) type)
          (progn (validate-document runtime value) t)))
    (t nil)))

(defun validate-document (runtime document)
  (unless (document-p document)
    (fail 'schema-error "Expected a document, received ~S." document))
  (let* ((schema (table-value (runtime-schemas runtime)
                              (document-type document)
                              "document schema"))
         (schema-fields (document-schema-fields schema)))
    (unless (eq (document-schema-persistence schema)
                (document-persistence document))
      (fail 'persistence-error
            "Document type ~S requires ~S persistence, received ~S."
            (document-type document)
            (document-schema-persistence schema)
            (document-persistence document)))
    (dolist (entry (document-fields document))
      (unless (find (first entry) schema-fields :key #'field-spec-name :test #'eq)
        (fail 'schema-error
              "Document type ~S has unknown field ~S."
              (document-type document)
              (first entry))))
    (dolist (field schema-fields)
      (let ((entry (field-entry document (field-spec-name field))))
        (when (and (field-spec-required-p field) (null entry))
          (fail 'schema-error
                "Document type ~S is missing required field ~S."
                (document-type document)
                (field-spec-name field)))
        (when (and entry
                   (not (type-valid-p runtime
                                      (field-spec-type field)
                                      (second entry))))
          (fail 'schema-error
                "Field ~S on document type ~S does not satisfy type ~S."
                (field-spec-name field)
                (document-type document)
                (field-spec-type field)))))
    document))

(defun make-checked-document (runtime type persistence fields)
  (validate-document
   runtime
   (%make-document :type type :persistence persistence :fields fields)))

(defun document (runtime type &rest fields)
  (let ((schema (table-value (runtime-schemas runtime) type "document schema")))
    (make-checked-document runtime type (document-schema-persistence schema) fields)))

(defun transient-document (runtime type &rest fields)
  (let ((schema (table-value (runtime-schemas runtime) type "document schema")))
    (unless (eq (document-schema-persistence schema) :transient)
      (fail 'persistence-error "Document type ~S is not transient." type))
    (make-checked-document runtime type :transient fields)))

(defun document-ref (value &rest path)
  (reduce
   (lambda (current key)
     (cond
       ((document-p current)
        (let ((entry (field-entry current key)))
          (unless entry
            (fail 'schema-error "Document type ~S has no field ~S."
                  (document-type current) key))
          (second entry)))
       ((map-value-p current)
        (multiple-value-bind (result present-p) (association-value key current)
          (unless present-p
            (fail 'schema-error "Map has no key ~S." key))
          result))
       (t
        (fail 'schema-error "Cannot read key ~S from ~S." key current))))
   path
   :initial-value value))

(defun persist-document (runtime document)
  (validate-document runtime document)
  (unless (eq (document-persistence document) :persistent)
    (fail 'persistence-error
          "Transient document type ~S cannot be persisted."
          (document-type document)))
  (push document (runtime-persisted runtime))
  (record-event runtime :persisted :document-type (document-type document))
  document)

(defun invoke-pure (runtime name value)
  (funcall (table-value (runtime-pure-functions runtime) name "pure function") value))

(defun invoke-actor (runtime name document)
  (let ((actor (table-value (runtime-actors runtime) name "actor")))
    (unless (type-valid-p runtime (actor-definition-accepts actor) document)
      (fail 'execution-error "Actor ~S rejected input type ~S."
            name (and (document-p document) (document-type document))))
    (record-event runtime :actor-invoked :actor name :input-type (document-type document))
    (let ((result (funcall (actor-definition-behavior actor) document runtime)))
      (unless (type-valid-p runtime (actor-definition-produces actor) result)
        (fail 'execution-error "Actor ~S returned an invalid result." name))
      (record-event runtime :actor-result :actor name :output-type (document-type result))
      result)))

(defun call-tool (runtime agent-name tool-name input)
  (let* ((agent (table-value (runtime-agents runtime) agent-name "agent"))
         (tool (table-value (runtime-tools runtime) tool-name "tool")))
    (unless (member tool-name (agent-definition-tools agent) :test #'eq)
      (fail 'execution-error "Agent ~S did not declare tool ~S." agent-name tool-name))
    (unless (type-valid-p runtime (tool-definition-input-type tool) input)
      (fail 'execution-error "Tool ~S rejected its input." tool-name))
    (record-event runtime :tool-invoked :agent agent-name :tool tool-name)
    (let ((result (funcall (tool-definition-function tool) input runtime)))
      (unless (type-valid-p runtime (tool-definition-output-type tool) result)
        (fail 'execution-error "Tool ~S returned an invalid result." tool-name))
      (record-event runtime :tool-result :agent agent-name :tool tool-name)
      result)))

(defun invoke-agent (runtime name documents)
  (let ((agent (table-value (runtime-agents runtime) name "agent")))
    (unless (type-valid-p runtime (agent-definition-accepts agent) documents)
      (fail 'execution-error "Agent ~S rejected its input." name))
    (record-event runtime :agent-invoked :agent name :input-count (length documents))
    (let ((result (funcall (agent-definition-behavior agent) documents runtime)))
      (unless (type-valid-p runtime (agent-definition-produces agent) result)
        (fail 'execution-error "Agent ~S returned an invalid result." name))
      (record-event runtime :agent-result :agent name :output-type (document-type result))
      result)))

(defun known-target-kind (runtime name)
  (cond
    ((gethash name (runtime-actors runtime)) :actor)
    ((gethash name (runtime-agents runtime)) :agent)
    (t (fail 'definition-error "Unknown dataflow target ~S." name))))

(defun compile-stage (runtime stage)
  (unless (and (consp stage) (symbolp (first stage)))
    (fail 'definition-error "Invalid dataflow stage ~S." stage))
  (case (first stage)
    (from
     (let ((type (second stage)))
       (table-value (runtime-schemas runtime) type "document schema")
       (list :op :from :type type)))
    (filter
     (let ((name (second stage)))
       (table-value (runtime-pure-functions runtime) name "pure function")
       (list :op :filter :function name)))
    (flat-map
     (let ((name (second stage)))
       (table-value (runtime-pure-functions runtime) name "pure function")
       (list :op :flat-map :function name)))
    (through
     (let ((name (second stage)))
       (list :op :through :target name :kind (known-target-kind runtime name))))
    (parallel
     (let ((limit (second stage))
           (nested (third stage)))
       (unless (and (integerp limit) (> limit 0))
         (fail 'definition-error "Parallel limit must be a positive integer."))
       (let ((compiled (compile-stage runtime nested)))
         (unless (and (eq (getf compiled :op) :through)
                      (eq (getf compiled :kind) :actor))
           (fail 'definition-error
                 "Parallel currently accepts only one actor through stage."))
         (list :op :parallel :limit limit :stage compiled))))
    (into
     (unless (eq (second stage) 'persist)
       (fail 'definition-error "Unknown sink ~S." (second stage)))
     (list :op :into :sink :persist))
    (otherwise
     (fail 'definition-error "Unknown dataflow operation ~S." (first stage)))))

(defun register-dataflow (runtime name stages)
  (let ((definition
          (make-dataflow-definition
           :name name
           :source-stages stages
           :plan (mapcar (lambda (stage) (compile-stage runtime stage)) stages))))
    (setf (gethash name (runtime-dataflows runtime)) definition)
    definition))

(defun dataflow-plan (runtime name)
  (dataflow-definition-plan
   (table-value (runtime-dataflows runtime) name "dataflow")))

(defun execute-through-stage (runtime plan documents)
  (let ((target (getf plan :target)))
    (ecase (getf plan :kind)
      (:actor (mapcar (lambda (document) (invoke-actor runtime target document)) documents))
      (:agent (list (invoke-agent runtime target documents))))))

(defun execute-stage (runtime plan documents)
  (ecase (getf plan :op)
    (:from
     (dolist (document documents)
       (unless (type-valid-p runtime (getf plan :type) document)
         (fail 'execution-error "Dataflow input does not match ~S." (getf plan :type))))
     documents)
    (:filter
     (remove-if-not (lambda (document)
                      (invoke-pure runtime (getf plan :function) document))
                    documents))
    (:flat-map
     (let ((results
             (mapcan (lambda (document)
                       (copy-list
                        (invoke-pure runtime (getf plan :function) document)))
                     documents)))
       (dolist (document results)
         (validate-document runtime document)
         (record-event runtime :transient-emitted :document-type (document-type document)))
       results))
    (:through
     (execute-through-stage runtime plan documents))
    (:parallel
     (record-event runtime :parallel-stage :limit (getf plan :limit))
     (execute-through-stage runtime (getf plan :stage) documents))
    (:into
     (ecase (getf plan :sink)
       (:persist
        (mapcar (lambda (document) (persist-document runtime document)) documents))))))

(defun run-dataflow (runtime name input)
  (let* ((definition (table-value (runtime-dataflows runtime) name "dataflow"))
         (documents (list (validate-document runtime input))))
    (record-event runtime :dataflow-started :dataflow name)
    (dolist (stage (dataflow-definition-plan definition))
      (setf documents (execute-stage runtime stage documents)))
    (record-event runtime :dataflow-completed :dataflow name :output-count (length documents))
    documents))

(defun rejecting-reader-macro (stream character)
  (declare (ignore stream character))
  (fail 'fixture-read-error "Reader dispatch and quoting are forbidden in fixtures."))

(defun fixture-readtable ()
  (let ((readtable (copy-readtable nil)))
    (dolist (character '(#\# #\' #\` #\,))
      (set-macro-character character #'rejecting-reader-macro nil readtable))
    readtable))

(defun fixture-node-p (value)
  (cond
    ((or (null value) (stringp value) (integerp value) (keywordp value)) t)
    ((consp value)
     (and (listp value) (every #'fixture-node-p value)))
    (t nil)))

(defun load-fixture (pathname)
  (with-open-file (stream pathname :direction :input :external-format :utf-8)
    (when (> (file-length stream) 65536)
      (fail 'fixture-read-error "Fixture exceeds 65,536 bytes."))
    (let ((*read-eval* nil)
          (*readtable* (fixture-readtable))
          (*package* (find-package :keyword)))
      (let ((fixture (read stream nil :eof)))
        (when (eq fixture :eof)
          (fail 'fixture-read-error "Fixture is empty."))
        (unless (eq (read stream nil :eof) :eof)
          (fail 'fixture-read-error "Fixture contains more than one top-level form."))
        (unless (fixture-node-p fixture)
          (fail 'fixture-read-error "Fixture contains a forbidden value."))
        fixture))))

(defun fixture-value (fixture key)
  (multiple-value-bind (value present-p) (association-value key fixture)
    (unless present-p
      (fail 'fixture-read-error "Fixture is missing key ~S." key))
    value))

(defun fixture-map-p (value)
  (and (listp value)
       (every (lambda (entry)
                (and (listp entry)
                     (= (length entry) 2)
                     (keywordp (first entry))))
              value)))

(defun decode-fixture-value (runtime value)
  (cond
    ((eq value :true) t)
    ((eq value :false) nil)
    ((and (fixture-map-p value) (assoc :type value :test #'eq))
     (decode-fixture-document runtime value))
    ((fixture-map-p value)
     (mapcar (lambda (entry)
               (list (first entry)
                     (decode-fixture-value runtime (second entry))))
             value))
    ((listp value)
     (mapcar (lambda (item) (decode-fixture-value runtime item)) value))
    (t value)))

(defun decode-fixture-document (runtime specification)
  (let ((type (fixture-value specification :type))
        (persistence (fixture-value specification :persistence))
        (fields (fixture-value specification :fields)))
    (make-checked-document
     runtime
     type
     persistence
     (mapcar (lambda (entry)
               (list (first entry)
                     (decode-fixture-value runtime (second entry))))
             fields))))

(defun fixture-actor-status (fixture email)
  (let ((entry (assoc email (fixture-value fixture :actor-results) :test #'string=)))
    (unless entry
      (fail 'fixture-read-error "No actor result exists for ~A." email))
    (second entry)))

(defun build-example-runtime (fixture)
  (let ((runtime (make-runtime))
        (domains (fixture-value fixture :domains)))
    (define-document runtime :user (:persistence :persistent)
      (:username :string :required t))
    (define-document runtime :target (:persistence :persistent)
      (:options :map :required t)
      (:data :user :required t))
    (define-document runtime :email-candidate (:persistence :transient)
      (:username :string :required t)
      (:email :email :required t))
    (define-document runtime :tested-email-candidate (:persistence :transient)
      (:username :string :required t)
      (:email :email :required t)
      (:status :symbol :required t))
    (define-document runtime :final-review (:persistence :persistent)
      (:username :string :required t)
      (:found-emails (:list :email) :required t)
      (:decision :symbol :required t))

    (define-pure runtime enumeration-target-p (target)
      (and (eq (document-type target) :target)
           (eq (document-ref target :options :enumeration) t)
           (let ((user (document-ref target :data)))
             (and (document-p user) (eq (document-type user) :user)))))

    (define-pure runtime generate-email-candidates (target)
      (let* ((user (document-ref target :data))
             (username (document-ref user :username)))
        (mapcar
         (lambda (domain)
           (transient-document
            runtime
            :email-candidate
            (list :username username)
            (list :email (format nil "~A@~A" username domain))))
         domains)))

    (define-pure runtime found-candidate-p (candidate)
      (eq (document-ref candidate :status) :found))

    (define-actor runtime email-testing-actor
      (:accepts :email-candidate :produces :tested-email-candidate)
      (candidate actor-runtime)
      (transient-document
       actor-runtime
       :tested-email-candidate
       (list :username (document-ref candidate :username))
       (list :email (document-ref candidate :email))
       (list :status
             (fixture-actor-status fixture (document-ref candidate :email)))))

    (define-tool runtime candidate-summary
      (:input (:list :tested-email-candidate) :output (:list :email))
      (candidates tool-runtime)
      (declare (ignore tool-runtime))
      (mapcar (lambda (candidate) (document-ref candidate :email)) candidates))

    (define-agent runtime review-agent
      (:accepts (:list :tested-email-candidate)
       :produces :final-review
       :tools (candidate-summary))
      (candidates agent-runtime)
      (let ((emails (call-tool agent-runtime 'review-agent 'candidate-summary candidates))
            (username (if candidates
                          (document-ref (first candidates) :username)
                          "unknown")))
        (document
         agent-runtime
         :final-review
         (list :username username)
         (list :found-emails emails)
         (list :decision :review-required))))

    (define-dataflow runtime email-enumeration
      (from :target)
      (filter enumeration-target-p)
      (flat-map generate-email-candidates)
      (parallel 4 (through email-testing-actor))
      (filter found-candidate-p)
      (through review-agent)
      (into persist))

    runtime))

(defun example-expansions ()
  (list
   (macroexpand-1
    '(define-document runtime :email-candidate (:persistence :transient)
       (:username :string :required t)
       (:email :email :required t)))
   (macroexpand-1
    '(define-dataflow runtime email-enumeration
       (from :target)
       (filter enumeration-target-p)
       (flat-map generate-email-candidates)
       (parallel 4 (through email-testing-actor))
       (filter found-candidate-p)
       (through review-agent)
       (into persist)))))

(defun run-example (fixture-pathname)
  (let* ((fixture (load-fixture fixture-pathname))
         (runtime (build-example-runtime fixture))
         (target (decode-fixture-document runtime (fixture-value fixture :target)))
         (outputs (run-dataflow runtime 'email-enumeration target)))
    (values runtime outputs fixture)))

(defun event-count (runtime type)
  (count type (ordered-events runtime) :key (lambda (event) (getf event :type)) :test #'eq))

(defun assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'execution-error "~A expected ~S, received ~S." label expected actual)))

(defun condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun test-reader-rejects-dispatch ()
  (let ((pathname #P"/tmp/star-lang-rejected.fixture"))
    (unwind-protect
         (progn
           (with-open-file (stream pathname
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string "#.(error \"forbidden\")" stream))
           (unless (condition-signaled-p
                    'fixture-read-error
                    (lambda () (load-fixture pathname)))
             (fail 'execution-error "Fixture reader accepted dispatch syntax.")))
      (when (probe-file pathname) (delete-file pathname)))))

(defun test-transient-persistence-rejected (runtime)
  (let ((candidate
          (transient-document
           runtime
           :email-candidate
           (list :username "ada")
           (list :email "ada@example.com"))))
    (unless (condition-signaled-p
             'persistence-error
             (lambda () (persist-document runtime candidate)))
      (fail 'execution-error "Runtime persisted a transient document."))))

(defun run-tests (fixture-pathname)
  (multiple-value-bind (runtime outputs fixture) (run-example fixture-pathname)
    (let* ((expected (fixture-value fixture :expected))
           (expected-count (fixture-value expected :candidate-count))
           (expected-emails (fixture-value expected :found-emails))
           (expected-types (fixture-value expected :persisted-document-types))
           (expected-persisted-count (fixture-value expected :persisted-document-count))
           (persisted (reverse (copy-list (runtime-persisted runtime))))
           (review (first outputs)))
      (assert-equal expected-count
                    (event-count runtime :transient-emitted)
                    "candidate count")
      (assert-equal expected-emails
                    (document-ref review :found-emails)
                    "found emails")
      (assert-equal expected-persisted-count
                    (length persisted)
                    "persisted document count")
      (assert-equal expected-types
                    (mapcar #'document-type persisted)
                    "persisted document types")
      (assert-equal 1 (event-count runtime :tool-invoked) "declared tool call count")
      (assert-equal 2 (length (example-expansions)) "macro expansion count")
      t)))

(defun benchmark-example (fixture-pathname iterations)
  (unless (and (integerp iterations) (> iterations 0))
    (fail 'execution-error "Iterations must be a positive integer."))
  (let ((started (get-internal-real-time)))
    (dotimes (index iterations)
      (declare (ignore index))
      (multiple-value-bind (runtime outputs fixture) (run-example fixture-pathname)
        (declare (ignore runtime outputs fixture))))
    (/ (- (get-internal-real-time) started)
       internal-time-units-per-second)))
