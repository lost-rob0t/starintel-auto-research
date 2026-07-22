(in-package #:star-lang.core-surface.prototype)

(export '(canonical-envelope-json
          canonical-manifest-json
          validate-wire-value))

(defstruct (json-object (:constructor %make-json-object (entries)))
  entries)

(defstruct (json-array (:constructor %make-json-array (values)))
  values)

(defparameter +json-true+ (gensym "JSON-TRUE"))
(defparameter +json-false+ (gensym "JSON-FALSE"))
(defparameter +json-null+ (gensym "JSON-NULL"))

(defun keyword-plist-p (value)
  (and (listp value)
       (evenp (length value))
       (loop for tail on value by #'cddr
             always (keywordp (first tail)))))

(defun string-alist-p (value)
  (and (listp value)
       value
       (every (lambda (entry)
                (and (consp entry) (stringp (car entry))))
              value)))

(defun json-key-name (key)
  (substitute #\_ #\-
              (string-downcase
               (etypecase key
                 (keyword (symbol-name key))
                 (symbol (symbol-name key))
                 (string key)))))

(defun json-symbol-value (value)
  (substitute #\- #\_
              (string-downcase (symbol-name value))))

(defun json-array-key-p (key)
  (member key
          '(:imports :types :predicates :messages :actors :fields :values
            :accepts :produces :capabilities)
          :test #'eq))

(defun manifest-json-value (value &optional key)
  (cond
    ((eq key :required)
     (if value +json-true+ +json-false+))
    ((json-array-key-p key)
     (%make-json-array
      (mapcar (lambda (item) (manifest-json-value item)) (or value '()))))
    ((eq value t) +json-true+)
    ((null value) +json-null+)
    ((stringp value) value)
    ((integerp value) value)
    ((keywordp value) (json-symbol-value value))
    ((and (symbolp value) (not (keywordp value)))
     (identifier-string value))
    ((keyword-plist-p value)
     (manifest-json-object value))
    ((string-alist-p value)
     (%make-json-object
      (mapcar (lambda (entry)
                (cons (car entry) (manifest-json-value (cdr entry))))
              value)))
    ((listp value)
     (%make-json-array (mapcar #'manifest-json-value value)))
    (t
     (fail 'invalid-envelope-error
           "Cannot convert ~S to canonical JSON." value))))

(defun manifest-json-object (plist)
  (let ((entries '()))
    (loop for (key value) on plist by #'cddr
          do (unless (and (null value)
                          (not (eq key :required))
                          (not (json-array-key-p key)))
               (push (cons (json-key-name key)
                           (manifest-json-value value key))
                     entries)))
    (%make-json-object entries)))

(defun write-json-escaped-string (value stream)
  (write-char #\" stream)
  (loop for character across value
        for code = (char-code character)
        do (case character
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (#\Backspace (write-string "\\b" stream))
             (#\Page (write-string "\\f" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Tab (write-string "\\t" stream))
             (otherwise
              (if (< code 32)
                  (format stream "\\u~4,'0X" code)
                  (write-char character stream)))))
  (write-char #\" stream))

(defun write-canonical-json (value stream)
  (cond
    ((eq value +json-true+) (write-string "true" stream))
    ((eq value +json-false+) (write-string "false" stream))
    ((eq value +json-null+) (write-string "null" stream))
    ((stringp value) (write-json-escaped-string value stream))
    ((integerp value) (format stream "~D" value))
    ((json-array-p value)
     (write-char #\[ stream)
     (loop for item in (json-array-values value)
           for first-p = t then nil
           do (unless first-p (write-char #\, stream))
              (write-canonical-json item stream))
     (write-char #\] stream))
    ((json-object-p value)
     (write-char #\{ stream)
     (loop for entry in (sort (copy-list (json-object-entries value))
                              #'string< :key #'car)
           for first-p = t then nil
           do (unless first-p (write-char #\, stream))
              (write-json-escaped-string (car entry) stream)
              (write-char #\: stream)
              (write-canonical-json (cdr entry) stream))
     (write-char #\} stream))
    (t
     (fail 'invalid-envelope-error
           "Unsupported canonical JSON node ~S." value))))

(defun canonical-json-string (value)
  (with-output-to-string (stream)
    (write-canonical-json value stream)))

(defun canonical-manifest-json (manifest)
  (canonical-json-string (manifest-json-object manifest)))

(defun manifest-type-contract (manifest qualified-name)
  (find qualified-name (getf manifest :types)
        :key (lambda (contract) (getf contract :name))
        :test #'string=))

(defun payload-entry (payload field-name)
  (cond
    ((string-alist-p payload)
     (assoc field-name payload :test #'string=))
    ((keyword-plist-p payload)
     (let ((key (intern (string-upcase field-name) :keyword)))
       (when (plist-has-key-p payload key)
         (cons field-name (getf payload key)))))
    (t nil)))

(defun payload-field-names (payload)
  (cond
    ((string-alist-p payload) (mapcar #'car payload))
    ((keyword-plist-p payload)
     (loop for (key value) on payload by #'cddr
           declare (ignore value)
           collect (identifier-string key)))
    ((null payload) '())
    (t nil)))

(defun generic-wire-json-value (value)
  (cond
    ((eq value t) +json-true+)
    ((null value) +json-null+)
    ((stringp value) value)
    ((integerp value) value)
    ((symbolp value) (identifier-string value))
    ((string-alist-p value)
     (%make-json-object
      (mapcar (lambda (entry)
                (cons (car entry) (generic-wire-json-value (cdr entry))))
              value)))
    ((listp value)
     (%make-json-array (mapcar #'generic-wire-json-value value)))
    (t
     (fail 'invalid-envelope-error
           "Unsupported wire value ~S." value))))

(defun wire-map-value (value context)
  (cond
    ((null value) (%make-json-object '()))
    ((string-alist-p value)
     (%make-json-object
      (mapcar (lambda (entry)
                (cons (car entry) (generic-wire-json-value (cdr entry))))
              value)))
    ((keyword-plist-p value)
     (manifest-json-object value))
    (t
     (fail 'invalid-envelope-error
           "~A requires an object/map value." context))))

(defun wire-reference-value (value context)
  (let ((object (wire-map-value value context))
        (schema (payload-entry value "schema"))
        (id (payload-entry value "id")))
    (unless (and schema (stringp (cdr schema)) id (stringp (cdr id)))
      (fail 'invalid-envelope-error
            "~A requires reference fields schema and id as strings." context))
    object))

(defun wire-enum-value (contract value context)
  (let ((normalized
          (cond
            ((stringp value) value)
            ((symbolp value) (identifier-string value))
            (t nil))))
    (unless (and normalized
                 (member normalized (getf contract :values) :test #'string=))
      (fail 'invalid-envelope-error
            "~A requires one of ~S, received ~S."
            context (getf contract :values) value))
    normalized))

(defun manifest-document-fields (manifest contract)
  (let ((parent-name (getf contract :extends)))
    (append
     (when parent-name
       (let ((parent (manifest-type-contract manifest parent-name)))
         (unless (and parent (eq (getf parent :kind) :document))
           (fail 'invalid-envelope-error
                 "Cannot resolve document parent ~A while validating wire data."
                 parent-name))
         (manifest-document-fields manifest parent)))
     (copy-tree (getf contract :fields)))))

(defun wire-fields-object (manifest fields value context)
  (unless (or (string-alist-p value) (keyword-plist-p value) (null value))
    (fail 'invalid-envelope-error "~A requires an object payload." context))
  (let ((known (mapcar (lambda (field) (getf field :name)) fields))
        (entries '()))
    (dolist (name (payload-field-names value))
      (unless (member name known :test #'string=)
        (fail 'invalid-envelope-error
              "~A contains unknown field ~A." context name)))
    (dolist (field fields)
      (let* ((name (getf field :name))
             (entry (payload-entry value name)))
        (cond
          (entry
           (push (cons name
                       (wire-json-value-for-type
                        manifest (getf field :type) (cdr entry)
                        (format nil "~A field ~A" context name)))
                 entries))
          ((getf field :required)
           (fail 'invalid-envelope-error
                 "~A is missing required field ~A." context name)))))
    (%make-json-object entries)))

(defun decimal-wire-string-p (value)
  (and (stringp value)
       (> (length value) 0)
       (let* ((start (if (member (char value 0) '(#\+ #\-)) 1 0))
              (dot (position #\. value :start start)))
         (and (< start (length value))
              (every #'digit-char-p
                     (if dot (subseq value start dot) (subseq value start)))
              (or (null dot)
                  (and (< dot (1- (length value)))
                       (every #'digit-char-p (subseq value (1+ dot)))))))))

(defun decimal-fraction-digits (value)
  (let ((dot (position #\. value)))
    (if dot (- (length value) dot 1) 0)))

(defun validate-scalar-constraints (contract value context)
  (let ((minimum (getf contract :minimum))
        (maximum (getf contract :maximum))
        (scale (getf contract :scale)))
    (when (and minimum (numberp value) (< value minimum))
      (fail 'invalid-envelope-error
            "~A is below scalar minimum ~A." context minimum))
    (when (and maximum (numberp value) (> value maximum))
      (fail 'invalid-envelope-error
            "~A exceeds scalar maximum ~A." context maximum))
    (when scale
      (unless (and (decimal-wire-string-p value)
                   (<= (decimal-fraction-digits value) scale))
        (fail 'invalid-envelope-error
              "~A requires a decimal string with at most ~D fractional digits."
              context scale))))
  value)

(defun wire-json-value-for-type (manifest type value context)
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2))
     (unless (listp value)
       (fail 'invalid-envelope-error "~A requires a list." context))
     (%make-json-array
      (mapcar (lambda (item)
                (wire-json-value-for-type manifest (second type) item context))
              value)))
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (if (null value)
         +json-null+
         (wire-json-value-for-type manifest (second type) value context)))
    ((not (stringp type))
     (fail 'invalid-envelope-error "~A has invalid type contract ~S." context type))
    ((string= type "any") (generic-wire-json-value value))
    ((member type '("string" "symbol" "iso-date" "iso-datetime") :test #'string=)
     (unless (or (stringp value) (and (string= type "symbol") (symbolp value)))
       (fail 'invalid-envelope-error "~A requires ~A." context type))
     (if (symbolp value) (identifier-string value) value))
    ((string= type "integer")
     (unless (integerp value)
       (fail 'invalid-envelope-error "~A requires an integer." context))
     value)
    ((string= type "boolean")
     (unless (or (eq value t) (null value))
       (fail 'invalid-envelope-error "~A requires a boolean." context))
     (if value +json-true+ +json-false+))
    ((string= type "decimal")
     (unless (decimal-wire-string-p value)
       (fail 'invalid-envelope-error
             "~A requires a decimal string to preserve wire precision." context))
     value)
    ((string= type "map") (wire-map-value value context))
    ((string= type "reference") (wire-reference-value value context))
    (t
     (let ((contract (manifest-type-contract manifest type)))
       (unless contract
         (fail 'invalid-envelope-error "~A references unknown type ~A." context type))
       (case (getf contract :kind)
         (:scalar
          (let ((encoded
                  (wire-json-value-for-type
                   manifest (getf contract :base) value context)))
            (validate-scalar-constraints contract value context)
            encoded))
         (:enum
          (wire-enum-value contract value context))
         (:document
          (wire-fields-object
           manifest (manifest-document-fields manifest contract) value context))
         (otherwise
          (fail 'invalid-envelope-error
                "~A cannot use type kind ~A."
                context (getf contract :kind))))))))

(defun validate-wire-value (manifest type value &optional (context "wire value"))
  (wire-json-value-for-type manifest type value context)
  t)

(defun envelope-json-object (manifest envelope)
  (unless (= (getf envelope :star-version) 1)
    (fail 'invalid-envelope-error "Unsupported Star wire version."))
  (let* ((message-type (getf envelope :message-type))
         (contract (message-contract manifest message-type)))
    (unless contract
      (fail 'invalid-envelope-error "Unknown message type ~A." message-type))
    (let ((entries
            (list (cons "star_version" 1)
                  (cons "message_type" message-type)
                  (cons "message_id" (getf envelope :message-id))
                  (cons "actor" (getf envelope :actor))
                  (cons "payload"
                        (wire-fields-object
                         manifest (getf contract :fields) (getf envelope :payload)
                         (format nil "Message ~A" message-type))))))
      (when (getf envelope :dataset)
        (push (cons "dataset" (getf envelope :dataset)) entries))
      (when (getf envelope :reply-to)
        (push (cons "reply_to" (getf envelope :reply-to)) entries))
      (%make-json-object entries))))

(defun canonical-envelope-json (manifest envelope)
  (canonical-json-string (envelope-json-object manifest envelope)))
