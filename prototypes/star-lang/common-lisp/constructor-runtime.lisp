(require :asdf)

(unless (find-package "STAR-LANG.DOCUMENT-RUNTIME")
  (load (merge-pathnames "document-runtime.lisp" *load-truename*)))

(defpackage #:star-lang.constructor-runtime
  (:use #:cl)
  (:export
   #:constructor-runtime-error
   #:constructor-runtime-error-message
   #:constructor-spec
   #:constructor-spec-name
   #:constructor-spec-document
   #:constructor-spec-lambda-list
   #:constructor-spec-dataset-argument
   #:constructor-spec-bindings
   #:constructor-spec-rest-keywords
   #:constructor-spec-validate
   #:constructor-spec-validator
   #:constructors-in-graph
   #:generate-constructor-form
   #:generate-constructor-source
   #:install-constructors
   #:package-constructor-graph
   #:installed-constructor-spec
   #:invoke-constructor
   #:merge-constructor-values
   #:email-user-part
   #:email-domain-part))

(in-package #:star-lang.constructor-runtime)

(define-condition constructor-runtime-error (error)
  ((message :initarg :message :reader constructor-runtime-error-message))
  (:report (lambda (condition stream)
             (write-string (constructor-runtime-error-message condition) stream))))

(defun fail-constructor (control &rest arguments)
  (error 'constructor-runtime-error
         :message (apply #'format nil control arguments)))

(defun identifier-string (value)
  (string-downcase
   (etypecase value
     (string value)
     (symbol (symbol-name value)))))

(defun plist-key-present-p (plist key)
  (loop for tail on plist by #'cddr
        thereis (eq (first tail) key)))

(defun ensure-plist (value context)
  (unless (and (listp value) (evenp (length value)))
    (fail-constructor "~A requires a property list, received ~S."
                      context value))
  value)

(defun required-option (options key context)
  (unless (plist-key-present-p options key)
    (fail-constructor "~A requires option ~S." context key))
  (getf options key))

(defstruct constructor-spec
  name
  document
  lambda-list
  dataset-argument
  bindings
  rest-keywords
  validate
  validator
  export)

(defparameter *package-graphs* (make-hash-table :test #'equal))
(defparameter *package-specs* (make-hash-table :test #'equal))

(defun normalized-package-name (package-designator)
  (string-upcase
   (etypecase package-designator
     (package (package-name package-designator))
     (string package-designator)
     (symbol (symbol-name package-designator)))))

(defun package-constructor-graph (package-designator)
  (or (gethash (normalized-package-name package-designator) *package-graphs*)
      (fail-constructor "No constructor graph is installed for package ~A."
                        package-designator)))

(defun installed-constructor-spec (package-designator constructor-name)
  (let* ((package-name (normalized-package-name package-designator))
         (table (gethash package-name *package-specs*)))
    (or (and table
             (gethash (identifier-string constructor-name) table))
        (fail-constructor "Constructor ~A is not installed for package ~A."
                          constructor-name package-name))))

(defun library-options (node)
  (third (star-lang.loader:library-node-form node)))

(defun raw-constructor-entries (node)
  (let ((options (library-options node)))
    (or (getf options :constructors) '())))

(defun library-generates-default-constructors-p (node)
  (not (null (getf (library-options node) :generate-default-constructors))))

(defparameter +lambda-list-keywords+
  '(&optional &rest &key &allow-other-keys &aux &body &whole &environment))

(defun lambda-list-keyword-p (symbol)
  (and (symbolp symbol)
       (member symbol +lambda-list-keywords+ :test #'eq)))

(defun parameter-variable (parameter)
  (cond
    ((symbolp parameter)
     (unless (lambda-list-keyword-p parameter)
       parameter))
    ((and (consp parameter) (symbolp (first parameter)))
     (first parameter))
    (t nil)))

(defun lambda-list-variables (lambda-list)
  (unless (listp lambda-list)
    (fail-constructor "Constructor lambda list must be a list."))
  (let ((variables '()))
    (dolist (parameter lambda-list (nreverse variables))
      (let ((variable (parameter-variable parameter)))
        (when variable
          (push (identifier-string variable) variables))))))

(defun source-expression-variables (source)
  (cond
    ((symbolp source)
     (if (or (null source) (eq source t))
         '()
         (list (identifier-string source))))
    ((atom source) '())
    ((member (first source) '(:or :email-user :email-domain) :test #'eq)
     (mapcan #'source-expression-variables (rest source)))
    (t
     (fail-constructor "Unsupported constructor source expression ~S." source))))

(defun validate-source-expression (source variables context)
  (dolist (variable (source-expression-variables source))
    (unless (member variable variables :test #'string=)
      (fail-constructor "~A references unknown constructor argument ~A."
                        context variable)))
  source)

(defun field-names (contract)
  (mapcar (lambda (field) (getf field :name))
          (star-lang.document-runtime:document-contract-fields contract)))

(defun parse-binding (binding variables known-fields context)
  (unless (and (listp binding) (= (length binding) 2))
    (fail-constructor "~A has invalid binding ~S." context binding))
  (let ((field (identifier-string (first binding)))
        (source (second binding)))
    (unless (member field known-fields :test #'string=)
      (fail-constructor "~A binds unknown field ~A." context field))
    (validate-source-expression source variables context)
    (list field source)))

(defun parse-constructor-entry (graph entry)
  (unless (and (listp entry) (= (length entry) 2))
    (fail-constructor "Invalid constructor declaration ~S." entry))
  (let* ((name (identifier-string (first entry)))
         (options (ensure-plist (second entry)
                                (format nil "constructor ~A" name)))
         (document (required-option options :document
                                    (format nil "constructor ~A" name)))
         (lambda-list (required-option options :lambda-list
                                       (format nil "constructor ~A" name)))
         (variables (lambda-list-variables lambda-list))
         (dataset-argument
           (identifier-string
            (required-option options :dataset
                             (format nil "constructor ~A" name))))
         (rest-keywords-value (getf options :rest-keywords))
         (rest-keywords (and rest-keywords-value
                             (identifier-string rest-keywords-value)))
         (validate (if (plist-key-present-p options :validate)
                       (getf options :validate)
                       t))
         (validator-value (getf options :validator))
         (validator (and validator-value
                         (intern (string-upcase (identifier-string validator-value))
                                 :keyword)))
         (export (if (plist-key-present-p options :export)
                     (getf options :export)
                     t))
         (contract (star-lang.document-runtime:compile-document-contract
                    graph document))
         (known-fields (field-names contract))
         (bindings
           (mapcar (lambda (binding)
                     (parse-binding binding variables known-fields
                                    (format nil "constructor ~A" name)))
                   (or (getf options :bindings) '()))))
    (unless (member dataset-argument variables :test #'string=)
      (fail-constructor "Constructor ~A dataset argument ~A is not in its lambda list."
                        name dataset-argument))
    (when (and rest-keywords
               (not (member rest-keywords variables :test #'string=)))
      (fail-constructor "Constructor ~A rest-keywords argument ~A is not in its lambda list."
                        name rest-keywords))
    (unless (member validator '(nil :RELATION-PREDICATE) :test #'eq)
      (fail-constructor "Constructor ~A uses unknown validator ~S."
                        name validator))
    (unless (or (eq validate t) (null validate))
      (fail-constructor "Constructor ~A :validate must be boolean." name))
    (make-constructor-spec
     :name name
     :document (star-lang.document-runtime:document-contract-qualified-name contract)
     :lambda-list lambda-list
     :dataset-argument dataset-argument
     :bindings bindings
     :rest-keywords rest-keywords
     :validate validate
     :validator validator
     :export (not (null export)))))

(defun document-declarations (graph)
  (loop for node in (star-lang.loader:loaded-graph-libraries graph)
        append
        (loop for declaration in
              (getf (star-lang.loader:library-node-compiled node) :declarations)
              when (eq (getf declaration :kind) :document)
                collect declaration)))

(defun default-constructor-spec (declaration)
  (let* ((local-name (getf declaration :name))
         (dataset-symbol (intern "DATASET" "STAR-LANG.CONSTRUCTOR-RUNTIME"))
         (args-symbol (intern "ARGS" "STAR-LANG.CONSTRUCTOR-RUNTIME")))
    (make-constructor-spec
     :name (format nil "new-~A" local-name)
     :document (getf declaration :qualified-name)
     :lambda-list (list dataset-symbol '&rest args-symbol)
     :dataset-argument "dataset"
     :bindings '()
     :rest-keywords "args"
     :validate t
     :validator nil
     :export t)))

(defun constructors-in-graph (graph &key (include-defaults t))
  (let ((explicit '())
        (seen (make-hash-table :test #'equal))
        (generate-defaults nil))
    (dolist (node (star-lang.loader:loaded-graph-libraries graph))
      (when (library-generates-default-constructors-p node)
        (setf generate-defaults t))
      (dolist (entry (raw-constructor-entries node))
        (let* ((spec (parse-constructor-entry graph entry))
               (name (constructor-spec-name spec)))
          (when (gethash name seen)
            (fail-constructor "Duplicate constructor named ~A." name))
          (setf (gethash name seen) t)
          (push spec explicit))))
    (setf explicit (nreverse explicit))
    (if (and include-defaults generate-defaults)
        (append
         explicit
         (loop for declaration in (document-declarations graph)
               for spec = (default-constructor-spec declaration)
               unless (gethash (constructor-spec-name spec) seen)
                 collect spec))
        explicit)))

(defun ensure-target-package (package-designator)
  (or (find-package package-designator)
      (make-package (normalized-package-name package-designator)
                    :use '("COMMON-LISP"))))

(defun target-symbol (name package)
  (intern (string-upcase (identifier-string name)) package))

(defun relocate-lambda-item (item package)
  (cond
    ((or (null item) (eq item t)) item)
    ((symbolp item)
     (if (lambda-list-keyword-p item)
         item
         (target-symbol item package)))
    ((consp item)
     (mapcar (lambda (part)
               (relocate-lambda-item part package))
             item))
    (t item)))

(defun compile-source-expression (source package)
  (cond
    ((or (null source) (eq source t)) source)
    ((symbolp source) (target-symbol source package))
    ((atom source) source)
    ((eq (first source) :or)
     (unless (= (length source) 3)
       (fail-constructor ":or constructor source requires two arguments."))
     `(or ,(compile-source-expression (second source) package)
          ,(compile-source-expression (third source) package)))
    ((eq (first source) :email-user)
     (unless (= (length source) 2)
       (fail-constructor ":email-user constructor source requires one argument."))
     `(email-user-part
       ,(compile-source-expression (second source) package)))
    ((eq (first source) :email-domain)
     (unless (= (length source) 2)
       (fail-constructor ":email-domain constructor source requires one argument."))
     `(email-domain-part
       ,(compile-source-expression (second source) package)))
    (t
     (fail-constructor "Unsupported constructor source expression ~S." source))))

(defun generate-constructor-form (spec package-designator)
  (let* ((package (ensure-target-package package-designator))
         (package-name (package-name package))
         (function-symbol (target-symbol (constructor-spec-name spec) package))
         (lambda-list
           (mapcar (lambda (item)
                     (relocate-lambda-item item package))
                   (constructor-spec-lambda-list spec)))
         (dataset-symbol
           (target-symbol (constructor-spec-dataset-argument spec) package))
         (rest-symbol
           (and (constructor-spec-rest-keywords spec)
                (target-symbol (constructor-spec-rest-keywords spec) package)))
         (bindings
           (mapcar
            (lambda (binding)
              `(cons ,(first binding)
                     ,(compile-source-expression (second binding) package)))
            (constructor-spec-bindings spec))))
    `(defun ,function-symbol ,lambda-list
       (invoke-constructor
        ,package-name
        ,(constructor-spec-name spec)
        (list ,@bindings)
        ,rest-symbol
        ,dataset-symbol))))

(defun generate-constructor-source (graph stream
                                    &key
                                      (package "STARINTEL")
                                      (include-defaults t))
  (with-standard-io-syntax
    (let ((*print-pretty* t)
          (*print-circle* nil))
      (dolist (spec (constructors-in-graph graph
                                           :include-defaults include-defaults))
        (write (generate-constructor-form spec package) :stream stream)
        (terpri stream)
        (terpri stream))))
  graph)

(defun normalize-key-map (value)
  (cond
    ((null value) '())
    ((hash-table-p value)
     (let ((result '()))
       (maphash (lambda (key item)
                  (push (cons (identifier-string key) item) result))
                value)
       result))
    ((and (listp value)
          (every (lambda (entry)
                   (and (consp entry)
                        (or (stringp (car entry))
                            (symbolp (car entry)))))
                 value))
     (mapcar (lambda (entry)
               (cons (identifier-string (car entry)) (cdr entry)))
             value))
    ((and (listp value) (evenp (length value)))
     (loop for (key item) on value by #'cddr
           collect (cons (identifier-string key) item)))
    (t
     (fail-constructor "Constructor keyword arguments must be a property list, alist, or hash table."))))

(defun merge-constructor-values (explicit rest-keywords)
  (let* ((explicit-values (normalize-key-map explicit))
         (explicit-names (mapcar #'car explicit-values))
         (rest-values
           (remove-if (lambda (entry)
                        (member (car entry) explicit-names :test #'string=))
                      (normalize-key-map rest-keywords))))
    (append explicit-values rest-values)))

(defun email-user-part (email)
  (unless (stringp email)
    (fail-constructor "new-email* requires an email string, received ~S." email))
  (let ((separator (position #\@ email)))
    (if separator (subseq email 0 separator) email)))

(defun email-domain-part (email)
  (unless (stringp email)
    (fail-constructor "new-email* requires an email string, received ~S." email))
  (let ((separator (position #\@ email)))
    (and separator (subseq email (1+ separator)))))

(defparameter +legacy-relation-predicates+
  '("related-to" "same-as" "duplicate-of" "aka" "alias-of"
    "username-of" "email-of" "phone-of" "account-of"
    "member-of" "employed-by" "contractor-for" "works-with"
    "manages" "reports-to" "owns" "owned-by" "controls"
    "controlled-by" "operates" "operated-by" "administers"
    "administered-by" "registered-to" "registrant-of"
    "whois-registrant-of" "whois-admin-of" "whois-tech-of"
    "located-at" "geolocated-at" "seen-at" "communicates-with"
    "contacted" "contacted-by" "mentions" "replies-to" "follows"
    "links-to" "redirects-to" "canonical-url-of" "hosts" "hosted-by"
    "served-by" "resolves-to" "ptr-to" "has-a" "has-aaaa"
    "has-cname" "has-ns" "has-mx" "has-txt" "has-spf" "has-dkim"
    "has-dmarc" "has-soa" "behind-cdn" "belongs-to-asn" "served-from"
    "shares-ip-with" "shares-asn-with" "hosts-service" "listens-on"
    "exposes-port" "runs" "runs-on" "leaked-in" "credential-for"
    "compromised-by" "observed-on" "observed-by" "collected-from"
    "extracted-from" "derived-from" "downloaded-from" "uploaded-to"
    "created-by" "modified-by" "hashes-to" "matches-hash"
    "evidence-of" "indicates" "attributed-to" "uses" "targets"
    "exploits" "mitigates" "c2-for" "in-scope-of" "out-of-scope-of"
    "discovered-by" "scanned-by" "has-finding" "vulnerable-to"))

(defun validate-constructor-values (spec values)
  (case (constructor-spec-validator spec)
    ((nil) values)
    (:RELATION-PREDICATE
     (let ((predicate (cdr (assoc "predicate" values :test #'string=))))
       (unless (and (stringp predicate)
                    (member predicate +legacy-relation-predicates+
                            :test #'string=))
         (fail-constructor "Invalid relation predicate ~S." predicate))
       values))
    (otherwise
     (fail-constructor "Unhandled constructor validator ~S."
                       (constructor-spec-validator spec)))))

(defun invoke-constructor (package-designator constructor-name
                           explicit-values rest-keywords dataset)
  (let* ((graph (package-constructor-graph package-designator))
         (spec (installed-constructor-spec package-designator constructor-name))
         (values (merge-constructor-values explicit-values rest-keywords)))
    (validate-constructor-values spec values)
    (star-lang.document-runtime:create-document
     graph
     (constructor-spec-document spec)
     values
     :dataset dataset
     :validate (constructor-spec-validate spec))))

(defun install-constructors (graph
                             &key
                               (package "STARINTEL")
                               (include-defaults t)
                               (if-exists :supersede))
  (unless (member if-exists '(:supersede :skip :error) :test #'eq)
    (fail-constructor ":if-exists must be :supersede, :skip, or :error."))
  (let* ((target-package (ensure-target-package package))
         (package-name (package-name target-package))
         (specs (constructors-in-graph graph
                                       :include-defaults include-defaults))
         (table (make-hash-table :test #'equal))
         (installed '()))
    (setf (gethash package-name *package-graphs*) graph
          (gethash package-name *package-specs*) table)
    (dolist (spec specs)
      (let* ((name (constructor-spec-name spec))
             (symbol (target-symbol name target-package)))
        (setf (gethash name table) spec)
        (cond
          ((and (fboundp symbol) (eq if-exists :error))
           (fail-constructor "Function ~A already exists." symbol))
          ((and (fboundp symbol) (eq if-exists :skip))
           nil)
          (t
           (eval (generate-constructor-form spec target-package))
           (when (constructor-spec-export spec)
             (export symbol target-package))
           (push symbol installed)))))
    (nreverse installed)))
