(require :asdf)

(let ((quicklisp
        (merge-pathnames "quicklisp/setup.lisp"
                         (user-homedir-pathname))))
  (unless (probe-file quicklisp)
    (error "Quicklisp is not installed at ~A." quicklisp))
  (load quicklisp))

(defun replace-required-text (pathname old new)
  (let ((content (uiop:read-file-string pathname :external-format :utf-8)))
    (unless (search old content)
      (error "Expected compatibility text not found in ~A: ~S" pathname old))
    (with-open-file (stream pathname
                            :direction :output
                            :if-exists :supersede
                            :external-format :utf-8)
      (loop with start = 0
            for position = (search old content :start2 start)
            do
               (if position
                   (progn
                     (write-string content stream :start start :end position)
                     (write-string new stream)
                     (setf start (+ position (length old))))
                   (progn
                     (write-string content stream :start start)
                     (return)))))))

(defun write-lines (pathname lines)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :external-format :utf-8)
    (dolist (line lines)
      (write-line line stream))))

(defun write-modern-cl-couch-http-request (pathname)
  (write-lines
   pathname
   '("(in-package :cl-couchdb-client)"
     ""
     "(setf drakma:*drakma-default-external-format* :utf-8)"
     ""
     "(defun http-request (method uri &key content content-type)"
     "  (multiple-value-bind (body status-code headers reply-uri stream closed-p reason)"
     "      (drakma:http-request"
     "       uri"
     "       :content (when content"
     "                  (if (string= content-type +json-content-type+)"
     "                      (json content)"
     "                      content))"
     "       :force-binary nil"
     "       :content-type content-type"
     "       :method method"
     "       :user-agent \"cl-couchdb-client\""
     "       :external-format-in :utf-8"
     "       :external-format-out :utf-8)"
     "    (declare (ignore headers reply-uri stream closed-p reason))"
     "    (values (dejson body) status-code)))")))

(defun write-modern-cl-couch-conditions (pathname)
  (write-lines
   pathname
   '("(in-package :cl-couchdb-client)"
     ""
     "(export '(couchdb-condition couchdb-server-error couchdb-conflict"
     "          couchdb-not-found old-doc-of new-doc-of))"
     ""
     "(define-condition couchdb-condition (error)"
     "  ((number :initarg :number :initform nil :reader number-of)"
     "   (error-value :initarg :error :initform nil :reader error-of)"
     "   (reason :initarg :reason :initform nil :reader reason-of))"
     "  (:report"
     "   (lambda (condition stream)"
     "     (format stream \"CouchDB returned an error: ~A (~A). Reason: ~A.\""
     "             (error-of condition)"
     "             (number-of condition)"
     "             (reason-of condition)))))"
     ""
     "(define-condition couchdb-not-found (couchdb-condition) ()"
     "  (:documentation \"404\"))"
     ""
     "(define-condition couchdb-conflict (couchdb-condition)"
     "  ((old-doc :initarg :old-doc :initform nil :reader old-doc-of)"
     "   (new-doc :initarg :new-doc :initform nil :reader new-doc-of)"
     "   (server :initarg :server :initform nil :reader server-of)"
     "   (db :initarg :db :initform nil :reader db-of))"
     "  (:default-initargs :number 412)"
     "  (:documentation \"412\")"
     "  (:report"
     "   (lambda (condition stream)"
     "     (format stream"
     "             \"CouchDB returned an error: ~A (~A). Reason: ~A in ~A/~A.\""
     "             (error-of condition)"
     "             (number-of condition)"
     "             (reason-of condition)"
     "             (server-of condition)"
     "             (db-of condition)))))"
     ""
     "(define-condition couchdb-server-error (couchdb-condition) ()"
     "  (:documentation \"50x errors.\"))")))

(defun modernize-cl-couch-client ()
  (let* ((root
           (merge-pathnames
            "quicklisp/local-projects/Cl-Couch/"
            (user-homedir-pathname)))
         (http-request (merge-pathnames "client/http-request.lisp" root))
         (conditions (merge-pathnames "client/conditions.lisp" root))
         (request (merge-pathnames "client/request.lisp" root))
         (utils (merge-pathnames "client/utils.lisp" root)))
    (unless (every #'probe-file (list http-request conditions request utils))
      (error "Pinned Cl-Couch checkout was not found at ~A." root))
    (write-modern-cl-couch-http-request http-request)
    (write-modern-cl-couch-conditions conditions)
    (replace-required-text request "(logv uri)" "nil")
    (replace-required-text
     utils
     "(trivial-utf-8:string-to-utf-8-bytes (string c))"
     "(babel:string-to-octets (string c) :encoding :utf-8)")
    (replace-required-text
     utils
     "trivial-utf-8:utf-8-bytes-to-string"
     "babel:octets-to-string")))

(ql:register-local-projects)
(modernize-cl-couch-client)
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
