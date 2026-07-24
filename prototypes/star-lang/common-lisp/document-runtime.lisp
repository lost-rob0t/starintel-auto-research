(require :asdf)

(unless (find-package "STAR-LANG.LOADER")
  (load (merge-pathnames "star-loader.lisp" *load-truename*)))

(defpackage #:star-lang.document-runtime
  (:use #:cl)
  (:export
   #:document-runtime-error
   #:document-runtime-error-message
   #:id-policy
   #:id-policy-kind
   #:id-policy-algorithm
   #:id-policy-fields
   #:id-policy-prefix
   #:document-contract
   #:document-contract-qualified-name
   #:document-contract-fields
   #:document-contract-id-policy
   #:document-instance
   #:document-instance-type
   #:document-instance-values
   #:make-ulid
   #:make-uuidv4
   #:make-digest-id
   #:generate-id
   #:compile-document-contract
   #:create-document
   #:set-document-meta
   #:validate-document
   #:encode-document
   #:decode-document
   #:relate-documents
   #:document-value))

(in-package #:star-lang.document-runtime)

(define-condition document-runtime-error (error)
  ((message :initarg :message :reader document-runtime-error-message))
  (:report (lambda (condition stream)
             (write-string (document-runtime-error-message condition) stream))))

(define-condition unknown-document-error (document-runtime-error) ())
(define-condition invalid-document-error (document-runtime-error) ())
(define-condition invalid-id-policy-error (document-runtime-error) ())
(define-condition id-generation-error (document-runtime-error) ())

(defun fail-runtime (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun identifier-string (value)
  (string-downcase
   (etypecase value
     (string value)
     (symbol (symbol-name value)))))

(defun plist-key-present-p (plist key)
  (loop for tail on plist by #'cddr
        thereis (eq (first tail) key)))

(defun unix-now ()
  (- (get-universal-time) 2208988800))

(defun secure-random-bytes (count)
  (let ((bytes (make-array count :element-type '(unsigned-byte 8))))
    (handler-case
        (with-open-file (stream #P"/dev/urandom"
                                :direction :input
                                :element-type '(unsigned-byte 8))
          (unless (= (read-sequence bytes stream) count)
            (fail-runtime 'id-generation-error
                          "Could not read ~D random bytes." count)))
      (error ()
        (dotimes (index count)
          (setf (aref bytes index) (random 256)))))
    bytes))

(defparameter +crockford-base32+
  "0123456789ABCDEFGHJKMNPQRSTVWXYZ")

(defun bytes-to-integer (bytes)
  (loop with value = 0
        for byte across bytes
        do (setf value (+ (ash value 8) byte))
        finally (return value)))

(defun make-ulid (&key (timestamp-ms (* 1000 (unix-now))))
  (unless (and (integerp timestamp-ms)
               (<= 0 timestamp-ms)
               (< timestamp-ms (ash 1 48)))
    (fail-runtime 'id-generation-error
                  "ULID timestamp is outside the 48-bit range: ~S."
                  timestamp-ms))
  (let ((value (logior (ash timestamp-ms 80)
                       (bytes-to-integer (secure-random-bytes 10))))
        (output (make-string 26)))
    (loop for index downfrom 25 to 0
          do (setf (char output index)
                   (char +crockford-base32+ (logand value 31))
                   value (ash value -5)))
    output))

(defun make-uuidv4 ()
  (let ((bytes (secure-random-bytes 16)))
    (setf (aref bytes 6) (logior #x40 (logand #x0f (aref bytes 6)))
          (aref bytes 8) (logior #x80 (logand #x3f (aref bytes 8))))
    (string-downcase
     (with-output-to-string (stream)
       (dotimes (index 16)
         (when (member index '(4 6 8 10))
           (write-char #\- stream))
         (format stream "~2,'0x" (aref bytes index)))))))

(defstruct id-policy kind algorithm fields prefix)
(defstruct document-contract qualified-name library-name library-version fields id-policy)
(defstruct (document-instance (:constructor %make-document-instance (type values)))
  type values)

(defun map-like-alist-p (value)
  (and (listp value)
       value
       (every (lambda (entry)
                (and (consp entry)
                     (or (stringp (car entry))
                         (symbolp (car entry)))))
              value)))

(defun normalize-input-map (value)
  (cond
    ((null value) '())
    ((hash-table-p value)
     (let ((result '()))
       (maphash (lambda (key item)
                  (push (cons (identifier-string key) item) result))
                value)
       result))
    ((map-like-alist-p value)
     (mapcar (lambda (entry)
               (cons (identifier-string (car entry)) (cdr entry)))
             value))
    ((and (listp value) (evenp (length value)))
     (loop for (key item) on value by #'cddr
           collect (cons (identifier-string key) item)))
    (t
     (fail-runtime 'invalid-document-error
                   "Expected an alist, hash table, or property list."))))

(defun map-value (values key &optional default)
  (let ((entry (assoc (identifier-string key) values :test #'string=)))
    (if entry (cdr entry) default)))

(defun map-has-key-p (values key)
  (not (null (assoc (identifier-string key) values :test #'string=))))

(defun map-set (values key value)
  (acons (identifier-string key)
         value
         (remove (identifier-string key) values :key #'car :test #'string=)))

(defun document-value (document key &optional default)
  (map-value (document-instance-values document) key default))

(defun canonical-star-value (value)
  (cond
    ((null value) "null")
    ((stringp value) (with-standard-io-syntax (write-to-string value)))
    ((numberp value) (with-standard-io-syntax (write-to-string value)))
    ((symbolp value) (identifier-string value))
    ((typep value 'document-instance)
     (canonical-star-value (document-instance-values value)))
    ((hash-table-p value)
     (canonical-star-value (normalize-input-map value)))
    ((map-like-alist-p value)
     (let ((entries
             (sort (mapcar (lambda (entry)
                             (cons (identifier-string (car entry)) (cdr entry)))
                           value)
                   #'string< :key #'car)))
       (format nil "{~{~A~^,~}}"
               (mapcar (lambda (entry)
                         (format nil "~A:~A"
                                 (canonical-star-value (car entry))
                                 (canonical-star-value (cdr entry))))
                       entries))))
    ((listp value)
     (format nil "[~{~A~^,~}]" (mapcar #'canonical-star-value value)))
    ((vectorp value)
     (canonical-star-value (coerce value 'list)))
    (t (with-standard-io-syntax (write-to-string value)))))

(defun normalized-algorithm (algorithm)
  (ecase (intern (string-upcase (identifier-string algorithm)) :keyword)
    (:MD5 :md5)
    (:SHA256 :sha256)))

(defun digest-program (algorithm)
  (ecase algorithm
    (:md5 "md5sum")
    (:sha256 "sha256sum")))

(defun make-digest-id (algorithm value &key prefix)
  (let* ((normalized (normalized-algorithm algorithm))
         (path (merge-pathnames
                (make-pathname
                 :name (format nil "star-lang-id-~36R-~36R"
                               (get-universal-time)
                               (random most-positive-fixnum))
                 :type "txt")
                (uiop:temporary-directory)))
         (input (canonical-star-value value)))
    (unwind-protect
         (progn
           (with-open-file (stream path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string input stream))
           (let* ((output
                    (uiop:run-program
                     (list (digest-program normalized) (namestring path))
                     :output :string
                     :error-output :string
                     :ignore-error-status nil))
                  (end (position-if
                        (lambda (character)
                          (find character '(#\Space #\Tab #\Newline #\Return)))
                        output))
                  (hex (string-downcase (if end (subseq output 0 end) output)))
                  (expected (if (eq normalized :md5) 32 64)))
             (unless (= (length hex) expected)
               (fail-runtime 'id-generation-error
                             "Unexpected digest output: ~S." output))
             (if prefix (concatenate 'string prefix hex) hex)))
      (when (probe-file path)
        (ignore-errors (delete-file path))))))

(defun generate-id (kind &key value algorithm prefix timestamp-ms)
  (case (intern (string-upcase (identifier-string kind)) :keyword)
    (:ULID (make-ulid :timestamp-ms (or timestamp-ms (* 1000 (unix-now)))))
    (:UUIDV4 (make-uuidv4))
    (:MD5 (make-digest-id :md5 value :prefix prefix))
    (:SHA256 (make-digest-id :sha256 value :prefix prefix))
    (:DIGEST
     (unless algorithm
       (fail-runtime 'invalid-id-policy-error
                     "Digest generation requires :algorithm."))
     (make-digest-id algorithm value :prefix prefix))
    (otherwise
     (fail-runtime 'invalid-id-policy-error
                   "Unknown ID strategy ~S." kind))))

(defun compile-id-policy (form)
  (let* ((options (or form '(:kind ulid)))
         (kind (intern
                (string-upcase
                 (identifier-string (or (getf options :kind) 'ulid)))
                :keyword))
         (algorithm (and (getf options :algorithm)
                         (normalized-algorithm (getf options :algorithm))))
         (fields (mapcar #'identifier-string (or (getf options :fields) '())))
         (prefix (getf options :prefix)))
    (unless (and (listp options) (evenp (length options)))
      (fail-runtime 'invalid-id-policy-error
                    "ID policy must be a property list."))
    (unless (member kind '(:ULID :UUIDV4 :DIGEST :SUPPLIED) :test #'eq)
      (fail-runtime 'invalid-id-policy-error
                    "Unsupported ID policy kind ~S." kind))
    (when (eq kind :DIGEST)
      (unless (and algorithm fields)
        (fail-runtime 'invalid-id-policy-error
                      "Digest policies require :algorithm and :fields.")))
    (make-id-policy :kind kind
                    :algorithm algorithm
                    :fields fields
                    :prefix prefix)))

(defun declaration-kind (declaration)
  (and (consp declaration)
       (symbolp (first declaration))
       (identifier-string (first declaration))))

(defun raw-document-declaration (node local-name)
  (find-if
   (lambda (declaration)
     (and (string= (or (declaration-kind declaration) "") "document")
          (string= (identifier-string (second declaration)) local-name)))
   (cdddr (star-lang.loader:library-node-form node))))

(defun find-compiled-declaration (graph qualified-name &optional kind)
  (dolist (node (star-lang.loader:loaded-graph-libraries graph))
    (dolist (declaration
             (getf (star-lang.loader:library-node-compiled node) :declarations))
      (when (and (string= (or (getf declaration :qualified-name) "")
                          qualified-name)
                 (or (null kind) (eq (getf declaration :kind) kind)))
        (return-from find-compiled-declaration
          (values declaration node)))))
  (values nil nil))

(defun resolve-document-name (graph name)
  (let ((normalized (identifier-string name)))
    (if (find #\/ normalized)
        normalized
        (let ((matches '()))
          (dolist (node (star-lang.loader:loaded-graph-libraries graph))
            (dolist (declaration
                     (getf (star-lang.loader:library-node-compiled node)
                           :declarations))
              (when (and (eq (getf declaration :kind) :document)
                         (string= (getf declaration :name) normalized))
                (push (getf declaration :qualified-name) matches))))
          (cond
            ((null matches)
             (fail-runtime 'unknown-document-error
                           "Unknown document type ~A." normalized))
            ((cdr matches)
             (fail-runtime 'unknown-document-error
                           "Ambiguous document type ~A." normalized))
            (t (first matches)))))))

(defun merge-fields (parent child)
  (let ((result (copy-list parent)))
    (dolist (field child)
      (setf result
            (append
             (remove (getf field :name) result
                     :key (lambda (item) (getf item :name))
                     :test #'string=)
             (list field))))
    result))

(defun compile-document-contract (graph document-name)
  (let ((active (make-hash-table :test #'equal)))
    (labels
        ((compile-one (qualified-name)
           (when (gethash qualified-name active)
             (fail-runtime 'invalid-document-error
                           "Document inheritance cycle at ~A." qualified-name))
           (setf (gethash qualified-name active) t)
           (multiple-value-bind (compiled node)
               (find-compiled-declaration graph qualified-name :document)
             (unless compiled
               (fail-runtime 'unknown-document-error
                             "No contract named ~A." qualified-name))
             (let* ((raw (raw-document-declaration node (getf compiled :name)))
                    (options (third raw))
                    (parent-name (getf compiled :extends))
                    (parent (and parent-name (compile-one parent-name)))
                    (policy-form (and (plist-key-present-p options :id-policy)
                                      (getf options :id-policy)))
                    (policy (cond
                              (policy-form (compile-id-policy policy-form))
                              (parent (document-contract-id-policy parent))
                              (t (compile-id-policy '(:kind ulid)))))
                    (contract
                      (make-document-contract
                       :qualified-name qualified-name
                       :library-name (star-lang.loader:library-node-name node)
                       :library-version (star-lang.loader:library-node-version node)
                       :fields (merge-fields
                                (if parent
                                    (document-contract-fields parent)
                                    '())
                                (getf compiled :fields))
                       :id-policy policy)))
               (remhash qualified-name active)
               contract))))
      (compile-one (resolve-document-name graph document-name)))))

(defun declaration-for-type (graph type-name)
  (multiple-value-bind (declaration node)
      (find-compiled-declaration graph type-name)
    (declare (ignore node))
    declaration))

(defun value-matches-type-p (graph value type)
  (cond
    ((null value) t)
    ((and (consp type) (eq (first type) :list))
     (and (listp value)
          (every (lambda (item)
                   (value-matches-type-p graph item (second type)))
                 value)))
    ((and (consp type) (eq (first type) :optional))
     (value-matches-type-p graph value (second type)))
    ((not (stringp type)) nil)
    ((string= type "any") t)
    ((string= type "boolean") (or (eq value t) (null value)))
    ((string= type "decimal") (numberp value))
    ((string= type "integer") (integerp value))
    ((string= type "map")
     (or (null value) (hash-table-p value) (map-like-alist-p value)))
    ((string= type "reference")
     (or (stringp value)
         (hash-table-p value)
         (map-like-alist-p value)
         (typep value 'document-instance)))
    ((member type '("string" "iso-date" "iso-datetime") :test #'string=)
     (stringp value))
    ((string= type "symbol") (or (stringp value) (symbolp value)))
    (t
     (let ((declaration (declaration-for-type graph type)))
       (unless declaration
         (fail-runtime 'invalid-document-error
                       "Unknown field type ~A." type))
       (case (getf declaration :kind)
         (:scalar
          (and (value-matches-type-p graph value (getf declaration :base))
               (or (null (getf declaration :minimum))
                   (and (numberp value)
                        (>= value (getf declaration :minimum))))
               (or (null (getf declaration :maximum))
                   (and (numberp value)
                        (<= value (getf declaration :maximum))))))
         (:enum
          (member (identifier-string value)
                  (getf declaration :values)
                  :test #'string=))
         (:document
          (or (stringp value)
              (hash-table-p value)
              (map-like-alist-p value)
              (typep value 'document-instance)))
         (otherwise nil))))))

(defun validate-document (graph document &optional contract)
  (let* ((resolved (or contract
                       (compile-document-contract
                        graph (document-instance-type document))))
         (values (document-instance-values document))
         (fields (document-contract-fields resolved))
         (known (mapcar (lambda (field) (getf field :name)) fields)))
    (dolist (entry values)
      (unless (member (car entry) known :test #'string=)
        (fail-runtime 'invalid-document-error
                      "Unknown field ~A for ~A."
                      (car entry)
                      (document-contract-qualified-name resolved))))
    (dolist (field fields)
      (let ((name (getf field :name)))
        (when (and (getf field :required)
                   (not (map-has-key-p values name)))
          (fail-runtime 'invalid-document-error
                        "Missing required field ~A." name))
        (when (map-has-key-p values name)
          (unless (value-matches-type-p
                   graph (map-value values name) (getf field :type))
            (fail-runtime 'invalid-document-error
                          "Field ~A does not match type ~S."
                          name (getf field :type))))))
    document))

(defun apply-field-defaults (contract values)
  (dolist (field (document-contract-fields contract) values)
    (when (and (getf field :default-p)
               (not (map-has-key-p values (getf field :name))))
      (setf values
            (map-set values (getf field :name) (getf field :default))))))

(defun assign-policy-id (policy values)
  (case (id-policy-kind policy)
    (:ULID (make-ulid))
    (:UUIDV4 (make-uuidv4))
    (:DIGEST
     (make-digest-id
      (id-policy-algorithm policy)
      (mapcar (lambda (field)
                (cons field (map-value values field)))
              (id-policy-fields policy))
      :prefix (id-policy-prefix policy)))
    (:SUPPLIED
     (or (map-value values "id")
         (fail-runtime 'id-generation-error
                       "Supplied ID policy requires an id field.")))
    (otherwise
     (fail-runtime 'invalid-id-policy-error
                   "Unhandled ID policy."))))

(defun set-document-meta (document contract &key dataset)
  (let* ((values (document-instance-values document))
         (resolved-dataset (or dataset (map-value values "dataset")))
         (now (unix-now)))
    (unless (and (stringp resolved-dataset)
                 (> (length resolved-dataset) 0))
      (fail-runtime 'invalid-document-error
                    "A non-empty dataset is required."))
    (setf values (map-set values "dataset" resolved-dataset)
          values (map-set values "dtype"
                          (document-contract-qualified-name contract))
          values (map-set values "schema-version"
                          (document-contract-library-version contract)))
    (unless (map-has-key-p values "created-at")
      (setf values (map-set values "created-at" now)))
    (unless (map-has-key-p values "date-added")
      (setf values (map-set values "date-added" now)))
    (setf values (map-set values "updated-at" now)
          values (map-set values "date-updated" now))
    (unless (map-has-key-p values "id")
      (setf values
            (map-set values "id"
                     (assign-policy-id
                      (document-contract-id-policy contract)
                      values))))
    (setf (document-instance-values document) values)
    document))

(defun create-document (graph document-type values &key dataset (validate t))
  (let* ((contract (compile-document-contract graph document-type))
         (document
           (%make-document-instance
            (document-contract-qualified-name contract)
            (apply-field-defaults contract (normalize-input-map values)))))
    (set-document-meta document contract :dataset dataset)
    (when validate
      (validate-document graph document contract))
    document))

(defun couchdb-revision-p (value)
  (and (stringp value)
       (let ((dash (position #\- value)))
         (and dash
              (> dash 0)
              (< dash (1- (length value)))
              (every #'digit-char-p (subseq value 0 dash))))))

(defun camel-key (key)
  (with-output-to-string (stream)
    (loop with uppercase-next = nil
          for character across key
          do (cond
               ((char= character #\-)
                (setf uppercase-next t))
               (uppercase-next
                (write-char (char-upcase character) stream)
                (setf uppercase-next nil))
               (t (write-char character stream))))))

(defun encoded-key (key key-style couchdb)
  (cond
    ((and couchdb (string= key "id")) "_id")
    ((and couchdb (string= key "rev")) "_rev")
    ((eq key-style :camel) (camel-key key))
    ((eq key-style :snake) (substitute #\_ #\- key))
    (t key)))

(defun encode-document (document &key (key-style :camel) (couchdb t))
  (loop for (key . value) in (document-instance-values document)
        unless (and couchdb
                    (string= key "rev")
                    (not (couchdb-revision-p value)))
          collect
          (cons (encoded-key key key-style couchdb)
                (if (typep value 'document-instance)
                    (encode-document value
                                     :key-style key-style
                                     :couchdb couchdb)
                    value))))

(defun decoded-field-name (contract external-key key-style couchdb)
  (cond
    ((and couchdb (string-equal external-key "_id")) "id")
    ((and couchdb (string-equal external-key "_rev")) "rev")
    (t
     (let ((field
             (find external-key
                   (document-contract-fields contract)
                   :key (lambda (item)
                          (encoded-key (getf item :name)
                                       key-style couchdb))
                   :test #'string-equal)))
       (and field (getf field :name))))))

(defun decode-document (graph document-type encoded
                        &key dataset (key-style :camel) (couchdb t))
  (let* ((contract (compile-document-contract graph document-type))
         (input (normalize-input-map encoded))
         (values
           (loop for (external-key . value) in input
                 for internal-key =
                   (decoded-field-name contract external-key key-style couchdb)
                 do (unless internal-key
                      (fail-runtime 'invalid-document-error
                                    "Unknown encoded field ~A." external-key))
                 collect (cons internal-key value))))
    (create-document graph document-type values
                     :dataset (or dataset (map-value values "dataset")))))

(defun relate-documents (graph source target
                         &key
                           (relation-type "relation")
                           (predicate "related-to")
                           note
                           dataset)
  (unless (and (typep source 'document-instance)
               (typep target 'document-instance))
    (fail-runtime 'invalid-document-error
                  "relate-documents requires document instances."))
  (create-document
   graph relation-type
   (list
    (cons "source" (document-value source "id"))
    (cons "target" (document-value target "id"))
    (cons "predicate" predicate)
    (cons "note" (or note "")))
   :dataset (or dataset
                (document-value source "dataset")
                (document-value target "dataset"))))
