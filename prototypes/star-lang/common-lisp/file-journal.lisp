(in-package #:star-lang.core)

(export '(file-journal
          file-journal-pathname
          journal-codec-error
          make-file-journal))

(define-condition journal-codec-error (replay-error) ())

(defclass file-journal (durable-journal)
  ((pathname
    :initarg :pathname
    :reader file-journal-pathname)
   (max-frame-bytes
    :initarg :max-frame-bytes
    :initform (* 4 1024 1024)
    :reader file-journal-max-frame-bytes)
   (max-events
    :initarg :max-events
    :initform 1000000
    :reader file-journal-max-events)))

(defun make-file-journal (pathname &key
                                     (max-frame-bytes (* 4 1024 1024))
                                     (max-events 1000000))
  (make-instance
   'file-journal
   :pathname (pathname pathname)
   :max-frame-bytes max-frame-bytes
   :max-events max-events))

(defun encode-journal-value (value)
  (cond
    ((null value) '(:null))
    ((eq value t) '(:true))
    ((stringp value) (list :string value))
    ((integerp value) (list :integer value))
    ((keywordp value)
     (list :keyword (string-downcase (symbol-name value))))
    ((symbolp value)
     (list :symbol
           (and (symbol-package value)
                (package-name (symbol-package value)))
           (symbol-name value)))
    ((core-document-p value)
     (list :document
           :id (core-document-id value)
           :schema-name (core-document-schema-name value)
           :schema-version (core-document-schema-version value)
           :persistence (encode-journal-value
                         (core-document-persistence value))
           :fields (encode-journal-value
                    (core-document-fields value))
           :content-hash (core-document-content-hash value)
           :provenance (encode-journal-value
                        (core-document-provenance value))))
    ((consp value)
     (list :cons
           (encode-journal-value (car value))
           (encode-journal-value (cdr value))))
    (t
     (fail 'journal-codec-error :unsupported-journal-value nil
           "Cannot encode journal value of type ~S." (type-of value)))))

(defun decode-journal-symbol (package-name symbol-name)
  (cond
    ((null package-name)
     (make-symbol symbol-name))
    ((string= package-name "KEYWORD")
     (intern symbol-name :keyword))
    (t
     (let ((package (find-package package-name)))
       (unless package
         (fail 'journal-codec-error :unknown-journal-package nil
               "Journal references missing package ~A." package-name))
       (intern symbol-name package)))))

(defun decode-journal-value (encoded)
  (unless (and (consp encoded) (keywordp (first encoded)))
    (fail 'journal-codec-error :invalid-journal-value nil
          "Invalid encoded journal value ~S." encoded))
  (case (first encoded)
    (:null nil)
    (:true t)
    (:string
     (unless (and (= (length encoded) 2)
                  (stringp (second encoded)))
       (fail 'journal-codec-error :invalid-journal-string nil
             "Invalid journal string encoding."))
     (second encoded))
    (:integer
     (unless (and (= (length encoded) 2)
                  (integerp (second encoded)))
       (fail 'journal-codec-error :invalid-journal-integer nil
             "Invalid journal integer encoding."))
     (second encoded))
    (:keyword
     (unless (and (= (length encoded) 2)
                  (stringp (second encoded)))
       (fail 'journal-codec-error :invalid-journal-keyword nil
             "Invalid journal keyword encoding."))
     (intern (string-upcase (second encoded)) :keyword))
    (:symbol
     (unless (and (= (length encoded) 3)
                  (or (null (second encoded))
                      (stringp (second encoded)))
                  (stringp (third encoded)))
       (fail 'journal-codec-error :invalid-journal-symbol nil
             "Invalid journal symbol encoding."))
     (decode-journal-symbol (second encoded) (third encoded)))
    (:cons
     (unless (= (length encoded) 3)
       (fail 'journal-codec-error :invalid-journal-cons nil
             "Invalid journal cons encoding."))
     (cons (decode-journal-value (second encoded))
           (decode-journal-value (third encoded))))
    (:document
     (let ((id (getf (rest encoded) :id))
           (schema-name (getf (rest encoded) :schema-name))
           (schema-version (getf (rest encoded) :schema-version))
           (persistence
             (decode-journal-value
              (getf (rest encoded) :persistence)))
           (fields
             (decode-journal-value
              (getf (rest encoded) :fields)))
           (content-hash (getf (rest encoded) :content-hash))
           (provenance
             (decode-journal-value
              (getf (rest encoded) :provenance))))
       (unless (and (stringp id)
                    (stringp schema-name)
                    (integerp schema-version)
                    (member persistence '(:persistent :transient))
                    (listp fields)
                    (stringp content-hash)
                    (listp provenance))
         (fail 'journal-codec-error :invalid-journal-document nil
               "Invalid journal document encoding."))
       (%make-core-document
        :id id
        :schema-name schema-name
        :schema-version schema-version
        :persistence persistence
        :fields fields
        :content-hash content-hash
        :provenance provenance)))
    (otherwise
     (fail 'journal-codec-error :unknown-journal-tag nil
           "Unknown journal value tag ~S." (first encoded)))))

(defun encode-run-event (event)
  (list :run-event
        :sequence (run-event-sequence event)
        :type (encode-journal-value (run-event-type event))
        :run-id (run-event-run-id event)
        :plan-hash (run-event-plan-hash event)
        :node-id (encode-journal-value (run-event-node-id event))
        :payload (encode-journal-value (run-event-payload event))))

(defun decode-run-event (encoded)
  (unless (and (consp encoded) (eq (first encoded) :run-event))
    (fail 'journal-codec-error :invalid-run-event nil
          "Invalid run event encoding."))
  (let ((sequence (getf (rest encoded) :sequence))
        (type (decode-journal-value (getf (rest encoded) :type)))
        (run-id (getf (rest encoded) :run-id))
        (plan-hash (getf (rest encoded) :plan-hash))
        (node-id (decode-journal-value (getf (rest encoded) :node-id)))
        (payload (decode-journal-value (getf (rest encoded) :payload))))
    (unless (and (integerp sequence)
                 (> sequence 0)
                 (keywordp type)
                 (stringp run-id)
                 (stringp plan-hash)
                 (or (null node-id) (stringp node-id)))
      (fail 'journal-codec-error :invalid-run-event-fields nil
            "Invalid run event fields."))
    (make-run-event
     :sequence sequence
     :type type
     :run-id run-id
     :plan-hash plan-hash
     :node-id node-id
     :payload payload)))

(defun readable-frame-string (value)
  (with-output-to-string (stream)
    (let ((*print-readably* t)
          (*print-circle* nil)
          (*print-pretty* nil)
          (*print-case* :downcase))
      (write value :stream stream))))

(defun parse-readable-frame (string)
  (let ((*read-eval* nil))
    (multiple-value-bind (value position)
        (read-from-string string nil :eof)
      (when (eq value :eof)
        (fail 'journal-codec-error :empty-journal-frame nil
              "Journal frame is empty."))
      (unless (every #'whitespace-character-p
                     (subseq string position))
        (fail 'journal-codec-error :trailing-journal-data nil
              "Journal frame contains trailing data."))
      value)))

(defun encode-journal-entry-frame (entry)
  (readable-frame-string
   (list :journal-entry
         :previous-hash (journal-entry-previous-hash entry)
         :hash (journal-entry-hash entry)
         :event (encode-run-event (journal-entry-event entry)))))

(defun decode-journal-entry-frame (frame)
  (let ((encoded (parse-readable-frame frame)))
    (unless (and (consp encoded)
                 (eq (first encoded) :journal-entry))
      (fail 'journal-codec-error :invalid-journal-entry nil
            "Invalid journal entry frame."))
    (let ((previous-hash (getf (rest encoded) :previous-hash))
          (hash (getf (rest encoded) :hash))
          (event (decode-run-event (getf (rest encoded) :event))))
      (unless (and (stringp previous-hash)
                   (= (length previous-hash) 64)
                   (stringp hash)
                   (= (length hash) 64))
        (fail 'journal-codec-error :invalid-journal-hash nil
              "Invalid journal hash encoding."))
      (make-journal-entry
       :event event
       :previous-hash previous-hash
       :hash hash))))

(defun write-journal-frame (stream frame max-frame-bytes)
  (let ((length (length frame)))
    (when (> length max-frame-bytes)
      (fail 'journal-codec-error :journal-frame-too-large nil
            "Journal frame exceeds ~D bytes." max-frame-bytes))
    (format stream "~8,'0X:" length)
    (write-string frame stream)
    (terpri stream)
    (finish-output stream)))

(defun parse-frame-length (header)
  (handler-case
      (parse-integer header :radix 16)
    (error ()
      (fail 'journal-codec-error :invalid-journal-frame-length nil
            "Invalid journal frame length ~S." header))))

(defun read-journal-frame (stream max-frame-bytes)
  (let ((header (make-string 8)))
    (let ((count (read-sequence header stream)))
      (cond
        ((zerop count) nil)
        ((< count 8)
         (fail 'journal-codec-error :truncated-journal-header nil
               "Journal ended inside a frame header."))
        (t
         (unless (char= (or (read-char stream nil #\Null) #\Null) #\:)
           (fail 'journal-codec-error :invalid-journal-frame-separator nil
                 "Journal frame header is missing its separator."))
         (let ((length (parse-frame-length header)))
           (when (> length max-frame-bytes)
             (fail 'journal-codec-error :journal-frame-too-large nil
                   "Journal frame declares ~D bytes; limit is ~D."
                   length max-frame-bytes))
           (let ((frame (make-string length)))
             (unless (= (read-sequence frame stream) length)
               (fail 'journal-codec-error :truncated-journal-frame nil
                     "Journal ended inside a frame payload."))
             (let ((terminator (read-char stream nil nil)))
               (unless (and terminator (char= terminator #\Newline))
                 (fail 'journal-codec-error
                       :missing-journal-frame-terminator nil
                       "Journal frame is missing its newline terminator.")))
             frame)))))))

(defun read-all-file-journal-entries (journal)
  (let ((pathname (file-journal-pathname journal)))
    (if (not (probe-file pathname))
        '()
        (with-open-file (stream pathname
                                :direction :input
                                :external-format :utf-8)
          (loop with entries = '()
                for frame = (read-journal-frame
                             stream
                             (file-journal-max-frame-bytes journal))
                while frame
                do
                   (when (>= (length entries)
                             (file-journal-max-events journal))
                     (fail 'journal-codec-error :too-many-journal-events nil
                           "Journal exceeds ~D events."
                           (file-journal-max-events journal)))
                   (push (decode-journal-entry-frame frame) entries)
                finally (return (nreverse entries)))))))

(defun file-journal-run-entries (journal run-id)
  (remove-if-not
   (lambda (entry)
     (string= run-id
              (run-event-run-id (journal-entry-event entry))))
   (read-all-file-journal-entries journal)))

(defmethod journal-append-event ((journal file-journal) event)
  (let* ((run-id (run-event-run-id event))
         (entries (file-journal-run-entries journal run-id))
         (expected-sequence (1+ (length entries))))
    (unless (= expected-sequence (run-event-sequence event))
      (fail 'replay-error :invalid-event-sequence nil
            "Run ~A expected event sequence ~D, received ~D."
            run-id expected-sequence (run-event-sequence event)))
    (let* ((previous-hash
             (if entries
                 (journal-entry-hash (car (last entries)))
                 (journal-genesis-hash)))
           (entry
             (make-journal-entry
              :event event
              :previous-hash previous-hash
              :hash (journal-entry-digest previous-hash event)))
           (frame (encode-journal-entry-frame entry)))
      (ensure-directories-exist (file-journal-pathname journal))
      (with-open-file (stream (file-journal-pathname journal)
                              :direction :output
                              :if-exists :append
                              :if-does-not-exist :create
                              :external-format :utf-8)
        (write-journal-frame
         stream frame (file-journal-max-frame-bytes journal)))
      event)))

(defmethod journal-read-events ((journal file-journal) run-id)
  (mapcar #'journal-entry-event
          (file-journal-run-entries journal run-id)))

(when (fboundp 'journal-read-entries)
  (fmakunbound 'journal-read-entries))

(defgeneric journal-read-entries (journal run-id))

(defmethod journal-read-entries ((journal chained-memory-journal) run-id)
  (copy-list
   (or (gethash run-id (chained-journal-entries-by-run journal)) '())))

(defmethod journal-read-entries ((journal file-journal) run-id)
  (file-journal-run-entries journal run-id))
