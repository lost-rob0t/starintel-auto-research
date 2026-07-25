(defpackage #:star-lang.core-surface.prototype
  (:use #:cl)
  (:export
   #:bind-actor-runtime
   #:compile-actor
   #:compile-spec-library
   #:emit-portable-manifest
   #:load-star-form
   #:make-wire-envelope
   #:star-lang-core-error-column
   #:star-lang-core-error-line
   #:star-lang-core-error-pathname
   #:star-lang-source-error
   #:run-tests
   #:validate-wire-envelope))

(in-package #:star-lang.core-surface.prototype)

(defvar *star-source-pathname* nil)
(defvar *star-source-line* nil)
(defvar *star-source-column* nil)
(defvar *star-source-positions* nil)

(define-condition star-lang-core-error (error)
  ((message :initarg :message :reader star-lang-core-error-message)
   (pathname
    :initarg :pathname
    :initform *star-source-pathname*
    :reader star-lang-core-error-pathname)
   (line
    :initarg :line
    :initform *star-source-line*
    :reader star-lang-core-error-line)
   (column
    :initarg :column
    :initform *star-source-column*
    :reader star-lang-core-error-column))
  (:report (lambda (condition stream)
             (let ((pathname (star-lang-core-error-pathname condition))
                   (line (star-lang-core-error-line condition))
                   (column (star-lang-core-error-column condition)))
               (when pathname
                 (format stream "~A" pathname)
                 (when line
                   (format stream ":~D" line)
                   (when column
                     (format stream ":~D" column)))
                 (write-string ": " stream))
               (write-string
                (star-lang-core-error-message condition)
                stream)))))

(define-condition star-lang-source-error (star-lang-core-error) ())
(define-condition invalid-library-error (star-lang-core-error) ())
(define-condition invalid-declaration-error (star-lang-core-error) ())
(define-condition invalid-field-error (star-lang-core-error) ())
(define-condition invalid-type-error (star-lang-core-error) ())
(define-condition invalid-actor-error (star-lang-core-error) ())
(define-condition invalid-envelope-error (star-lang-core-error) ())
(define-condition test-error (star-lang-core-error) ())

(defun fail (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defmacro with-star-source-position ((value) &body body)
  `(let ((position
           (and *star-source-positions*
                (gethash ,value *star-source-positions*))))
     (let ((*star-source-line*
             (if position (first position) *star-source-line*))
           (*star-source-column*
             (if position (second position) *star-source-column*)))
       ,@body)))

(defstruct (star-source-parser
             (:constructor make-star-source-parser
                 (source pathname)))
  source
  pathname
  (index 0 :type fixnum)
  (line 1 :type fixnum)
  (column 1 :type fixnum)
  (positions (make-hash-table :test #'eq)))

(defparameter *star-source-keywords*
  '(("algorithm" . :algorithm)
    ("base" . :base)
    ("bindings" . :bindings)
    ("constructors" . :constructors)
    ("dataset" . :dataset)
    ("default" . :default)
    ("destination" . :destination)
    ("digest" . :digest)
    ("extends" . :extends)
    ("fields" . :fields)
    ("format" . :format)
    ("generate-default-constructors" . :generate-default-constructors)
    ("id-policy" . :id-policy)
    ("lambda-list" . :lambda-list)
    ("maximum" . :maximum)
    ("minimum" . :minimum)
    ("optional" . :optional)
    ("path" . :path)
    ("pattern" . :pattern)
    ("persistence" . :persistence)
    ("required" . :required)
    ("rest-keywords" . :rest-keywords)
    ("scale" . :scale)
    ("source" . :source)
    ("url" . :url)
    ("validate" . :validate)
    ("validator" . :validator)
    ("version" . :version)))

(defun star-source-end-p (parser)
  (>= (star-source-parser-index parser)
      (length (star-source-parser-source parser))))

(defun star-source-character (parser)
  (unless (star-source-end-p parser)
    (char (star-source-parser-source parser)
          (star-source-parser-index parser))))

(defun advance-star-source (parser)
  (let ((character (star-source-character parser)))
    (when character
      (incf (star-source-parser-index parser))
      (if (char= character #\Newline)
          (progn
            (incf (star-source-parser-line parser))
            (setf (star-source-parser-column parser) 1))
          (incf (star-source-parser-column parser))))
    character))

(defun fail-star-source (parser control &rest arguments)
  (error 'star-lang-source-error
         :message (apply #'format nil control arguments)
         :pathname (star-source-parser-pathname parser)
         :line (star-source-parser-line parser)
         :column (star-source-parser-column parser)))

(defun star-source-whitespace-p (character)
  (and character
       (find character '(#\Space #\Tab #\Newline #\Return #\Page))))

(defun skip-star-source-trivia (parser)
  (loop
    (cond
      ((star-source-whitespace-p (star-source-character parser))
       (advance-star-source parser))
      ((eql (star-source-character parser) #\;)
       (loop for character = (star-source-character parser)
             while (and character (not (char= character #\Newline)))
             do (advance-star-source parser)))
      (t
       (return parser)))))

(defun star-source-delimiter-p (character)
  (or (null character)
      (star-source-whitespace-p character)
      (find character '(#\( #\) #\" #\;))))

(defun parse-star-source-string (parser)
  (advance-star-source parser)
  (let ((value (make-array 32
                           :element-type 'character
                           :adjustable t
                           :fill-pointer 0)))
    (loop
      (when (star-source-end-p parser)
        (fail-star-source parser "Unterminated string literal."))
      (let ((character (advance-star-source parser)))
        (cond
          ((char= character #\")
           (return value))
          ((char= character #\\)
           (when (star-source-end-p parser)
             (fail-star-source parser "Unterminated string escape."))
           (let ((escaped (advance-star-source parser)))
             (vector-push-extend
              (case escaped
                (#\n #\Newline)
                (#\r #\Return)
                (#\t #\Tab)
                (otherwise escaped))
              value)))
          (t
           (vector-push-extend character value)))))))

(defun star-source-integer (token)
  (when (and (> (length token) 0)
             (or (every #'digit-char-p token)
                 (and (> (length token) 1)
                      (find (char token 0) '(#\+ #\-))
                      (every #'digit-char-p (subseq token 1)))))
    (parse-integer token)))

(defun parse-star-source-atom (parser)
  (let ((start (star-source-parser-index parser)))
    (loop for character = (star-source-character parser)
          until (star-source-delimiter-p character)
          do
             (when (find character '(#\# #\' #\` #\,))
               (fail-star-source
                parser
                "Reader syntax beginning with ~C is not part of Star-Lang."
                character))
             (advance-star-source parser))
    (let* ((token
             (subseq (star-source-parser-source parser)
                     start
                     (star-source-parser-index parser)))
           (integer (star-source-integer token)))
      (when (zerop (length token))
        (fail-star-source parser "Expected a Star-Lang token."))
      (when (string= token ".")
        (fail-star-source parser "Dotted-list syntax is not part of Star-Lang."))
      (cond
        ((char= (char token 0) #\:)
         (when (or (= (length token) 1)
                   (position #\: token :start 1))
           (fail-star-source parser "Invalid Star-Lang keyword ~A." token))
         (let ((keyword
                 (cdr (assoc (string-downcase (subseq token 1))
                             *star-source-keywords*
                             :test #'string=))))
           (unless keyword
             (fail-star-source parser "Unknown Star-Lang keyword ~A." token))
           keyword))
        ((position #\: token)
         (fail-star-source
          parser
          "Package-qualified symbols are not part of Star-Lang: ~A."
          token))
        ((string-equal token "nil") nil)
        ((string-equal token "t") t)
        (integer integer)
        (t
         (string-downcase token))))))

(defun parse-star-source-value (parser)
  (skip-star-source-trivia parser)
  (let ((character (star-source-character parser)))
    (cond
      ((null character)
       (fail-star-source parser "Unexpected end of Star-Lang source."))
      ((char= character #\()
       (let ((line (star-source-parser-line parser))
             (column (star-source-parser-column parser)))
         (advance-star-source parser)
         (let ((values '()))
         (loop
           (skip-star-source-trivia parser)
           (let ((next (star-source-character parser)))
             (cond
               ((null next)
                (fail-star-source parser "Unterminated list."))
               ((char= next #\))
                (advance-star-source parser)
                (let ((result (nreverse values)))
                  (setf (gethash result
                                 (star-source-parser-positions parser))
                        (list line column))
                  (return result)))
               (t
                (push (parse-star-source-value parser) values))))))))
      ((char= character #\))
       (fail-star-source parser "Unexpected closing parenthesis."))
      ((char= character #\")
       (parse-star-source-string parser))
      (t
       (parse-star-source-atom parser)))))

(defun parse-star-source (source pathname)
  (let ((parser (make-star-source-parser source pathname)))
    (skip-star-source-trivia parser)
    (when (star-source-end-p parser)
      (fail-star-source parser "Star file is empty."))
    (let ((form (parse-star-source-value parser)))
      (skip-star-source-trivia parser)
      (unless (star-source-end-p parser)
        (fail-star-source
         parser
         "Star file must contain exactly one top-level form."))
      (values form (star-source-parser-positions parser)))))

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
  (unless (and (listp declaration)
               declaration
               (or (symbolp (first declaration))
                   (stringp (first declaration))))
    (fail 'invalid-declaration-error "Invalid declaration ~S." declaration))
  (identifier-string (first declaration)))

(defun declaration-name (declaration)
  (unless (>= (length declaration) 2)
    (fail 'invalid-declaration-error "Declaration has no name: ~S." declaration))
  (identifier-string (second declaration)))

(defun ensure-unique-declarations (declarations)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (declaration declarations)
      (with-star-source-position (declaration)
        (let* ((kind (declaration-kind declaration))
               (name (declaration-name declaration))
               (key (cons kind name)))
          (when (gethash key seen)
            (fail 'invalid-declaration-error
                  "Duplicate ~A declaration named ~A."
                  kind name))
          (setf (gethash key seen) t))))))

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
  (with-star-source-position (field)
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
              :default default)))))

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
  (with-star-source-position (declaration)
    (let ((kind (declaration-kind declaration)))
      (cond
        ((string= kind "import") (compile-import declaration))
        ((string= kind "scalar")
         (compile-scalar declaration library-name local-types))
        ((string= kind "enum") (compile-enum declaration library-name))
        ((string= kind "document")
         (compile-document declaration library-name local-types))
        ((string= kind "predicate")
         (compile-predicate declaration library-name local-types))
        ((string= kind "message")
         (compile-message declaration library-name local-types))
        (t
         (fail 'invalid-declaration-error
               "Unknown specification declaration ~S."
               (first declaration)))))))

(defun compile-spec-library (form)
  (with-star-source-position (form)
    (unless (and (listp form)
                 (>= (length form) 3)
                 (string= (declaration-kind form) "spec-library"))
      (fail 'invalid-library-error "Expected one spec-library form."))
    (destructuring-bind (operator name options &rest declarations) form
      (declare (ignore operator))
      (unless (stringp name)
        (fail 'invalid-library-error
              "Specification library name must be a string."))
      (ensure-plist options "spec-library" 'invalid-library-error)
      (ensure-unique-declarations declarations)
      (ensure-unique-local-types declarations)
      (ensure-unique-library-names declarations)
      (let* ((version
               (required-option
                options :version "spec-library" 'invalid-library-error))
             (digest (getf options :digest))
             (local-types (declared-local-types declarations))
             (compiled
               (mapcar (lambda (declaration)
                         (compile-library-declaration
                          declaration name local-types))
                       declarations)))
        (unless (stringp version)
          (fail 'invalid-library-error
                "Specification library version must be a string."))
        (when (and digest (not (digest-p digest)))
          (fail 'invalid-library-error
                "Specification library digest must use sha256:."))
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
                             compiled))))))

(defun load-star-form (pathname)
  (let* ((candidate (pathname pathname))
         (path
           (handler-case
               (truename candidate)
             (file-error ()
               candidate))))
    (let ((*star-source-pathname* path)
          (*star-source-line* 1)
          (*star-source-column* 1))
      (unless (and (pathname-type path)
                   (string-equal (pathname-type path) "star"))
        (fail 'star-lang-source-error
              "Star source pathname must use the .star extension."))
      (handler-case
          (let ((source
                  (with-open-file (stream path :direction :input)
                    (with-output-to-string (output)
                      (loop for character = (read-char stream nil nil)
                            while character
                            do (write-char character output))))))
            (multiple-value-bind (form positions)
                (parse-star-source source path)
              (let ((*star-source-positions* positions))
                (compile-spec-library form))))
        (star-lang-core-error (condition)
          (error condition))
        (file-error (condition)
          (fail 'star-lang-source-error
                "Could not read Star source ~A: ~A."
                path condition))))))
