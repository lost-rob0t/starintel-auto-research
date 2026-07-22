(require :asdf)

(let ((quicklisp
        (merge-pathnames "quicklisp/setup.lisp"
                         (user-homedir-pathname))))
  (unless (probe-file quicklisp)
    (error "Quicklisp is not installed at ~A." quicklisp))
  (load quicklisp))

(defun write-lines (pathname lines)
  (ensure-directories-exist pathname)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create
                          :external-format :utf-8)
    (dolist (line lines)
      (write-line line stream))))

(defun install-cl-couch-api-compatibility ()
  (let* ((local-projects
           (merge-pathnames
            "quicklisp/local-projects/"
            (user-homedir-pathname)))
         (legacy-asd
           (merge-pathnames "Cl-Couch/cl-couchdb-client.asd"
                            local-projects))
         (compat-root
           (merge-pathnames "cl-couchdb-client-compat/"
                            local-projects))
         (compat-asd
           (merge-pathnames "cl-couchdb-client.asd" compat-root))
         (compat-source
           (merge-pathnames "cl-couchdb-client.lisp" compat-root)))
    (when (probe-file legacy-asd)
      (delete-file legacy-asd))
    (write-lines
     compat-asd
     '("(asdf:defsystem \"cl-couchdb-client\""
       "  :description \"Modern compatibility implementation of the Cl-Couch client API used by Star-Lang.\""
       "  :depends-on (\"drakma\" \"cl-json\" \"babel\")"
       "  :serial t"
       "  :components ((:file \"cl-couchdb-client\")))"))
    (write-lines
     compat-source
     '("(defpackage #:cl-couchdb-client"
       "  (:use #:cl)"
       "  (:nicknames #:couchdb-client)"
       "  (:export #:couch-request*))"
       ""
       "(in-package #:cl-couchdb-client)"
       ""
       "(defun query-key-string (key)"
       "  (string-downcase"
       "   (substitute #\_ #\-"
       "               (etypecase key"
       "                 (symbol (symbol-name key))"
       "                 (string key)))))"
       ""
       "(defun query-value-string (value)"
       "  (cond"
       "    ((eq value t) \"true\")"
       "    ((null value) \"false\")"
       "    ((stringp value) value)"
       "    ((symbolp value) (string-downcase (symbol-name value)))"
       "    ((numberp value) (princ-to-string value))"
       "    (t (error \"Unsupported CouchDB query value ~S.\" value))))"
       ""
       "(defun query-string (keys)"
       "  (when keys"
       "    (format nil \"?~{~A~^&~}\""
       "            (loop for (key value) on keys by #'cddr"
       "                  collect (format nil \"~A=~A\""
       "                                  (query-key-string key)"
       "                                  (query-value-string value))))))"
       ""
       "(defun response-string (body)"
       "  (etypecase body"
       "    (string body)"
       "    ((vector (unsigned-byte 8))"
       "     (babel:octets-to-string body :encoding :utf-8))))"
       ""
       "(defun couch-request* (method server path &optional keys content-type content)"
       "  (let* ((uri (format nil \"~A~{/~A~}~A\""
       "                      server path (or (query-string keys) \"\")))"
       "         (arguments"
       "           (list uri"
       "                 :method method"
       "                 :force-binary nil"
       "                 :external-format-in :utf-8"
       "                 :external-format-out :utf-8)))"
       "    (when content"
       "      (setf arguments"
       "            (append arguments"
       "                    (list :content"
       "                          (if (and content-type"
       "                                   (search \"application/json\" content-type))"
       "                              (json:encode-json-to-string content)"
       "                              content)"
       "                          :content-type content-type))))"
       "    (multiple-value-bind (body status-code)"
       "        (apply #'drakma:http-request arguments)"
       "      (unless (<= 200 status-code 299)"
       "        (error \"CouchDB request ~A returned status ~D.\" uri status-code))"
       "      (let ((text (response-string body)))"
       "        (if (zerop (length text))"
       "            nil"
       "            (json:decode-json-from-string text))))))"))))

(install-cl-couch-api-compatibility)
(ql:register-local-projects)
(ql:quickload :cl-couchdb-client)
(ql:quickload :cl-rabbit)

(let* ((directory
         (uiop/pathname:pathname-directory-pathname *load-truename*))
       (system-file (merge-pathnames "star-lang.asd" directory)))
  (asdf:load-asd system-file)
  (asdf:load-system "star-lang/cl-couch")
  (asdf:load-system "star-lang/cl-rabbit"))

(defun ensure-integration (value control &rest arguments)
  (unless value
    (error (apply #'format nil control arguments))))

(let* ((plan
         (star-lang.core:compile-program
          "(define-couchdb-source live-couch
             (:server \"http://admin:password@localhost:5984\")
             (:path (list \"star_lang\" \"_all_docs\"))
             (:keys (list :include_docs true)))
           (load-documents live-couch documents
             (:limit 2)
             (:dataset \"couch-live\"))"
          :source-name "couch-live.star"))
       (runtime
         (star-lang.core:make-script-runtime
          :couchdb-adapter
          (star-lang.core:make-cl-couch-source-adapter))))
  (star-lang.core:run-script plan runtime)
  (let ((documents
          (star-lang.core:script-runtime-dataset runtime "couch-live")))
    (ensure-integration (= (length documents) 2)
                        "Expected two CouchDB documents, got ~D."
                        (length documents))))

(let ((queue "star-lang.integration"))
  (cl-rabbit:with-connection (connection)
    (let ((socket (cl-rabbit:tcp-socket-new connection)))
      (cl-rabbit:socket-open socket "localhost" 5672)
      (cl-rabbit:login-sasl-plain
       connection "/" "guest" "guest")
      (cl-rabbit:with-channel (connection 1)
        (cl-rabbit:queue-declare connection 1 :queue queue)
        (cl-rabbit:basic-publish
         connection 1
         :exchange ""
         :routing-key queue
         :body "one")
        (cl-rabbit:basic-publish
         connection 1
         :exchange ""
         :routing-key queue
         :body "two")))))

(let* ((plan
         (star-lang.core:compile-program
          "(define-rabbitmq-source live-rabbit
             (:host \"localhost\")
             (:port 5672)
             (:vhost \"/\")
             (:username \"guest\")
             (:password \"guest\")
             (:queue \"star-lang.integration\")
             (:channel 1)
             (:declare true)
             (:ack true))
           (load-documents live-rabbit documents
             (:limit 2)
             (:dataset \"rabbit-live\"))"
          :source-name "rabbit-live.star"))
       (runtime
         (star-lang.core:make-script-runtime
          :rabbitmq-adapter
          (star-lang.core:make-cl-rabbit-source-adapter))))
  (star-lang.core:run-script plan runtime)
  (let ((documents
          (star-lang.core:script-runtime-dataset runtime "rabbit-live")))
    (ensure-integration (equal documents '("one" "two"))
                        "Unexpected RabbitMQ documents: ~S."
                        documents)))

(format t "Star-Lang live CouchDB and RabbitMQ integrations passed.~%")
