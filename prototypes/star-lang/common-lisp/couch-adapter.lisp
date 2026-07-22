(in-package #:star-lang.core)

(export '(cl-couch-source-adapter
          make-cl-couch-source-adapter))

(defclass cl-couch-source-adapter (star-lang-source-adapter) ())

(defun make-cl-couch-source-adapter ()
  (make-instance 'cl-couch-source-adapter))

(defun two-element-proper-list-p (value)
  (and (consp value)
       (consp (cdr value))
       (null (cddr value))))

(defun association-result (entry)
  (if (two-element-proper-list-p entry)
      (second entry)
      (cdr entry)))

(defun couch-field (object key)
  (when (listp object)
    (let ((entry
            (or (assoc key object :test #'eq)
                (assoc (string-downcase (symbol-name key)) object
                       :test #'string-equal)
                (assoc (string-upcase (symbol-name key)) object
                       :test #'string-equal))))
      (when entry (association-result entry)))))

(defun couch-result-documents (response)
  (let ((rows (couch-field response :rows)))
    (cond
      (rows
       (mapcar (lambda (row) (or (couch-field row :doc) row)) rows))
      ((and (listp response) (every #'consp response))
       (list response))
      ((listp response)
       response)
      (t
       (list response)))))

(defmethod source-adapter-read ((adapter cl-couch-source-adapter)
                                spec runtime &key limit)
  (declare (ignore adapter))
  (let* ((server (source-option-value spec "server" runtime
                                      "http://localhost:5984"))
         (database (source-option-value spec "database" runtime nil))
         (path (source-option-value
                spec "path" runtime
                (and database (list database "_all_docs"))))
         (keys (source-option-value spec "keys" runtime
                                    (list :include_docs t)))
         (decoder (source-decoder spec runtime)))
    (unless path
      (fail 'execution-error :couchdb-path-required nil
            "CouchDB source ~A requires (:DATABASE ...) or (:PATH ...)."
            (source-spec-name spec)))
    (let* ((response
             (couchdb-client:couch-request* :get server path keys))
           (documents (couch-result-documents response))
           (decoded
             (if decoder
                 (mapcan
                  (lambda (document)
                    (let ((value (funcall decoder document runtime)))
                      (if (listp value) value (list value))))
                  documents)
                 documents)))
      (if limit
          (subseq decoded 0 (min limit (length decoded)))
          decoded))))
