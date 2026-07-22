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

(defun modernize-cl-couch-client ()
  (let* ((root
           (merge-pathnames
            "quicklisp/local-projects/Cl-Couch/"
            (user-homedir-pathname)))
         (http-request (merge-pathnames "client/http-request.lisp" root))
         (utils (merge-pathnames "client/utils.lisp" root)))
    (unless (and (probe-file http-request) (probe-file utils))
      (error "Pinned Cl-Couch checkout was not found at ~A." root))
    (with-open-file (stream http-request
                            :direction :output
                            :if-exists :supersede
                            :external-format :utf-8)
      (write-string
       "(in-package :cl-couchdb-client)\n\n(setf drakma:*drakma-default-external-format* :utf-8)\n\n(defun http-request (method uri &key content content-type)\n  (multiple-value-bind (body status-code headers reply-uri stream closed-p reason)\n      (drakma:http-request\n       uri\n       :content (when content\n                  (if (string= content-type +json-content-type+)\n                      (json content)\n                      content))\n       :force-binary nil\n       :content-type content-type\n       :method method\n       :user-agent \"cl-couchdb-client\"\n       :external-format-in :utf-8\n       :external-format-out :utf-8)\n    (declare (ignore headers reply-uri stream closed-p reason))\n    (values (dejson body) status-code)))\n"
       stream))
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
