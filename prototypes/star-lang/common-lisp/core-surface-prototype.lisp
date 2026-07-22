(defpackage #:star-lang.core-surface.prototype
  (:use #:cl)
  (:export
   #:bind-actor-runtime
   #:compile-actor
   #:compile-spec-library
   #:emit-portable-manifest
   #:load-star-form
   #:make-wire-envelope
   #:run-tests
   #:validate-wire-envelope))

(in-package #:star-lang.core-surface.prototype)

(define-condition star-lang-core-error (error)
  ((message :initarg :message :reader star-lang-core-error-message))
  (:report (lambda (condition stream)
             (write-string (star-lang-core-error-message condition) stream))))

(define-condition invalid-library-error (star-lang-core-error) ())
(define-condition invalid-declaration-error (star-lang-core-error) ())
(define-condition invalid-field-error (star-lang-core-error) ())
(define-condition invalid-type-error (star-lang-core-error) ())
(define-condition invalid-actor-error (star-lang-core-error) ())
(define-condition invalid-envelope-error (star-lang-core-error) ())
(define-condition test-error (star-lang-core-error) ())

(defun fail (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun identifier-string (value)
  (string-downcase
   (etypecase value
     (string value)
     (symbol (symbol-name value)))))

(defun qualified-name-p (value)
  (and (stringp value) (position #\/ value)))

(defun qualify-name (library-name value)
  (let ((name (identifier-string value)))
    (if (qualified-name-p name)
        name
        (format nil "~A/~A" library-name name))))

(defun plist-has-key-p (plist key)
  (loop for tail on plist by #'cddr
        thereis (eq (first tail) key)))

(defun ensure-plist (value context &optional condition-type)
  (unless (and (listp value) (evenp (length value)))
    (fail (or condition-type 'invalid-declaration-error)
          "~A requires a property list, received ~S."
          context value))
  value)

(defun required-option (options key context &optional condition-type)
  (unless (plist-has-key-p options key)
    (fail (or condition-type 'invalid-declaration-error)
          "~A requires option ~S."
          context key))
  (getf options key))

(defun digest-p (value)
  (and (stringp value)
       (> (length value) 7)
       (string= "sha256:" value :end2 7)))

(defun normalize-persistence (value)
  (let ((name (identifier-string value)))
    (cond
      ((string= name "persistent") :persistent)
      ((string= name "transient") :transient)
      (t
       (fail 'invalid-declaration-error
             "Persistence must be persistent or transient, received ~S."
             value)))))

(defun normalize-runtime (value)
  (let ((name (identifier-string value)))
    (cond
      ((string= name "native") :native)
      ((string= name "external") :external)
      (t
       (fail 'invalid-actor-error
             "Actor runtime must be native or external, received ~S."
             value)))))

(defun normalize-restart (value)
  (let ((name (identifier-string value)))
    (cond
      ((string= name "permanent") :permanent)
      ((string= name "transient") :transient)
      ((string= name "temporary") :temporary)
      (t
       (fail 'invalid-actor-error
             "Actor restart policy must be permanent, transient, or temporary.")))))

(defun normalize-mailbox (value)
  (unless (and (listp value) (= (length value) 2))
    (fail 'invalid-actor-error "Mailbox must be (bounded positive-integer)."))
  (destructuring-bind (kind capacity) value
    (unless (and (string= (identifier-string kind) "bounded")
                 (integerp capacity)
                 (> capacity 0))
      (fail 'invalid-actor-error "Mailbox must be (bounded positive-integer)."))
    (list :kind :bounded :capacity capacity)))

(defun normalize-type-expression (value library-name local-types)
  (cond
    ((consp value)
     (let ((operator (identifier-string (first value))))
       (cond
         ((and (string= operator "list") (= (length value) 2))
          (list :list
                (normalize-type-expression (second value) library-name local-types)))
         ((and (string= operator "optional") (= (length value) 2))
          (list :optional
                (normalize-type-expression (second value) library-name local-types)))
         (t
          (fail 'invalid-type-error "Unknown type expression ~S." value)))))
    ((or (symbolp value) (stringp value))
     (let* ((name (identifier-string value))
            (builtins '("any" "boolean" "decimal" "integer" "map" "reference"
                        "string" "symbol" "iso-date" "iso-datetime")))
       (cond
         ((member name builtins :test #'string=) name)
         ((qualified-name-p name) name)
         ((member name local-types :test #'string=)
          (qualify-name library-name name))
         (t
          (fail 'invalid-type-error
                "Unknown unqualified type ~A in library ~A."
                name library-name)))))
    (t
     (fail 'invalid-type-error "Invalid type expression ~S." value))))

(defun declaration-kind (declaration)
  (unless (and (listp declaration) declaration (symbolp (first declaration)))
    (fail 'invalid-declaration-error "Invalid declaration ~S." declaration))
  (identifier-string (first declaration)))

(defun declaration-name (declaration)
  (unless (>= (length declaration) 2)
    (fail 'invalid-declaration-error "Declaration has no name: ~S." declaration))
  (identifier-string (second declaration)))

(defun ensure-unique-declarations (declarations)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (declaration declarations)
      (let* ((kind (declaration-kind declaration))
             (name (declaration-name declaration))
             (key (cons kind name)))
        (when (gethash key seen)
          (fail 'invalid-declaration-error
                "Duplicate ~A declaration named ~A."
                kind name))
        (setf (gethash key seen) t)))))

(defun declared-local-types (declarations)
  (loop for declaration in declarations
        for kind = (declaration-kind declaration)
        when (member kind '("scalar" "enum" "document") :test #'string=)
          collect (declaration-name declaration)))

(defun ensure-unique-local-types (declarations)
  (let ((types (declared-local-types declarations)))
    (unless (= (length types)
               (length (remove-duplicates types :test #'string=)))
      (fail 'invalid-declaration-error
            "Scalar, enum, and document names share one type namespace."))))

(defun ensure-unique-library-names (declarations)
  (let ((names
          (loop for declaration in declarations
                for kind = (declaration-kind declaration)
                unless (string= kind "import")
                  collect (declaration-name declaration))))
    (unless (= (length names)
               (length (remove-duplicates names :test #'string=)))
      (fail 'invalid-declaration-error
            "Library declarations share one qualified-name namespace."))))

(defun ensure-unique-fields (fields context)
  (let ((names (mapcar (lambda (field) (getf field :name)) fields)))
    (unless (= (length names)
               (length (remove-duplicates names :test #'string=)))
      (fail 'invalid-field-error "~A declares a field more than once." context))))

(defun compile-import (declaration)
  (destructuring-bind (operator name &rest options) declaration
    (declare (ignore operator))
    (ensure-plist options "import" 'invalid-library-error)
    (let ((version (required-option options :version "import" 'invalid-library-error))
          (digest (required-option options :digest "import" 'invalid-library-error)))
      (unless (and (stringp name) (stringp version) (digest-p digest))
        (fail 'invalid-library-error
              "Imports require string name, exact version, and sha256 digest."))
      (list :kind :import
            :name name
            :version version
            :digest digest))))

(defun compile-scalar (declaration library-name local-types)
  (destructuring-bind (operator name options) declaration
    (declare (ignore operator))
    (ensure-plist options "scalar")
    (let ((base (required-option options :base "scalar")))
      (list :kind :scalar
            :name (identifier-string name)
            :qualified-name (qualify-name library-name name)
            :base (normalize-type-expression base library-name local-types)
            :pattern (getf options :pattern)
            :format (and (plist-has-key-p options :format)
                         (identifier-string (getf options :format)))
            :minimum (getf options :minimum)
            :maximum (getf options :maximum)
            :scale (getf options :scale)))))

(defun compile-enum (declaration library-name)
  (destructuring-bind (operator name values) declaration
    (declare (ignore operator))
    (unless (and (listp values) values)
      (fail 'invalid-declaration-error "Enum ~A requires at least one value." name))
    (let ((normalized (mapcar #'identifier-string values)))
      (unless (= (length normalized)
                 (length (remove-duplicates normalized :test #'string=)))
        (fail 'invalid-declaration-error "Enum ~A contains duplicate values." name))
      (list :kind :enum
            :name (identifier-string name)
            :qualified-name (qualify-name library-name name)
            :values normalized))))

(defun parse-field-markers (options field-name)
  (let* ((required-p (member :required options :test #'eq))
         (optional-p (member :optional options :test #'eq))
         (default-position (position :default options :test #'eq))
         (default-p (not (null default-position)))
         (default
           (when default-p
             (unless (< default-position (1- (length options)))
               (fail 'invalid-field-error
                     "Field ~A declares :default without a value."
                     field-name))
             (nth (1+ default-position) options))))
    (when (and required-p optional-p)
      (fail 'invalid-field-error
            "Field ~A cannot be both required and optional."
            field-name))
    (unless (or required-p optional-p)
      (fail 'invalid-field-error
            "Field ~A must declare :required or :optional."
            field-name))
    (values (not (null required-p)) default default-p)))

(defun compile-field (field library-name local-types)
  (unless (and (listp field) (>= (length field) 3))
    (fail 'invalid-field-error "Invalid field declaration ~S." field))
  (destructuring-bind (name type &rest options) field
    (multiple-value-bind (required-p default default-p)
        (parse-field-markers options name)
      (when (and required-p default-p)
        (fail 'invalid-field-error
              "Required field ~A cannot declare a default."
              name))
      (list :name (identifier-string name)
            :type (normalize-type-expression type library-name local-types)
            :required required-p
            :default-p default-p
            :default default))))

(defun compile-document (declaration library-name local-types)
  (destructuring-bind (operator name options &rest fields) declaration
    (declare (ignore operator))
    (ensure-plist options "document")
    (let* ((extends (getf options :extends))
           (persistence (required-option options :persistence "document"))
           (compiled-fields
             (mapcar (lambda (field)
                       (compile-field field library-name local-types))
                     fields)))
      (ensure-unique-fields compiled-fields (format nil "Document ~A" name))
      (list :kind :document
            :name (identifier-string name)
            :qualified-name (qualify-name library-name name)
            :extends (and extends
                          (normalize-type-expression extends library-name local-types))
            :persistence (normalize-persistence persistence)
            :fields compiled-fields))))

(defun compile-predicate (declaration library-name local-types)
  (destructuring-bind (operator name options) declaration
    (declare (ignore operator))
    (ensure-plist options "predicate")
    (list :kind :predicate
          :name (identifier-string name)
          :qualified-name (qualify-name library-name name)
          :source (normalize-type-expression
                   (required-option options :source "predicate")
                   library-name local-types)
          :destination (normalize-type-expression
                        (required-option options :destination "predicate")
                        library-name local-types))))

(defun compile-message (declaration library-name local-types)
  (destructuring-bind (operator name options) declaration
    (declare (ignore operator))
    (ensure-plist options "message")
    (let ((fields (required-option options :fields "message")))
      (unless (listp fields)
        (fail 'invalid-field-error "Message fields must be a list."))
      (let ((compiled-fields
              (mapcar (lambda (field)
                        (compile-field field library-name local-types))
                      fields)))
        (ensure-unique-fields compiled-fields (format nil "Message ~A" name))
        (list :kind :message
              :name (identifier-string name)
              :qualified-name (qualify-name library-name name)
              :fields compiled-fields)))))

(defun compile-library-declaration (declaration library-name local-types)
  (let ((kind (declaration-kind declaration)))
    (cond
      ((string= kind "import") (compile-import declaration))
      ((string= kind "scalar") (compile-scalar declaration library-name local-types))
      ((string= kind "enum") (compile-enum declaration library-name))
      ((string= kind "document") (compile-document declaration library-name local-types))
      ((string= kind "predicate") (compile-predicate declaration library-name local-types))
      ((string= kind "message") (compile-message declaration library-name local-types))
      (t
       (fail 'invalid-declaration-error
             "Unknown specification declaration ~S."
             (first declaration))))))

(defun compile-spec-library (form)
  (unless (and (listp form)
               (>= (length form) 3)
               (string= (declaration-kind form) "spec-library"))
    (fail 'invalid-library-error "Expected one spec-library form."))
  (destructuring-bind (operator name options &rest declarations) form
    (declare (ignore operator))
    (unless (stringp name)
      (fail 'invalid-library-error "Specification library name must be a string."))
    (ensure-plist options "spec-library" 'invalid-library-error)
    (ensure-unique-declarations declarations)
    (ensure-unique-local-types declarations)
    (ensure-unique-library-names declarations)
    (let* ((version (required-option options :version "spec-library" 'invalid-library-error))
           (digest (getf options :digest))
           (local-types (declared-local-types declarations))
           (compiled
             (mapcar (lambda (declaration)
                       (compile-library-declaration declaration name local-types))
                     declarations)))
      (unless (stringp version)
        (fail 'invalid-library-error "Specification library version must be a string."))
      (when (and digest (not (digest-p digest)))
        (fail 'invalid-library-error "Specification library digest must use sha256:."))
      (list :ir-version 1
            :kind :spec-library
            :name name
            :version version
            :digest digest
            :imports (remove-if-not
                      (lambda (item) (eq (getf item :kind) :import))
                      compiled)
            :declarations (remove-if
                           (lambda (item) (eq (getf item :kind) :import))
                           compiled)))))

(defun load-star-form (pathname)
  (with-open-file (stream pathname :direction :input)
    (let ((*read-eval* nil))
      (let ((form (read stream nil :eof)))
        (when (eq form :eof)
          (fail 'invalid-library-error "Star file ~A is empty." pathname))
        (unless (eq (read stream nil :eof) :eof)
          (fail 'invalid-library-error "Star file ~A must contain exactly one top-level form." pathname))
        form))))
