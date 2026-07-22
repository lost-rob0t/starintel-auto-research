(require :asdf)

(let ((quicklisp
        (merge-pathnames "quicklisp/setup.lisp"
                         (user-homedir-pathname))))
  (unless (probe-file quicklisp)
    (error "Quicklisp is not installed at ~A." quicklisp))
  (load quicklisp))

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
