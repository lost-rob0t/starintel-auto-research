(in-package #:star-lang.core.tests)

(defun call-kind-count (calls kind)
  (count kind calls :key #'first :test #'eq))

(defun test-sento-adapter-contract ()
  (cl-user::reset-star-lang-adapter-stubs)
  (let* ((source
           "(define-actor worker
              (:name \"worker\")
              (:receive worker-handler)
              (:dispatcher :pinned)
              (:queue-size 32))
            (start-actor worker)
            (send (actor-ref 'worker) \"payload\")
            (stop-actor worker)")
         (plan (star-lang.core:compile-program
                source :source-name "sento-contract.star"))
         (adapter (star-lang.core::make-sento-actor-adapter))
         (runtime
           (star-lang.core:make-script-runtime
            :actor-adapter adapter
            :handlers
            (list
             (cons "worker-handler"
                   (lambda (message actor-runtime)
                     (declare (ignore actor-runtime))
                     (string-upcase message)))))))
    (star-lang.core:run-script plan runtime)
    (let ((calls (reverse cl-user::*star-lang-sento-stub-calls*)))
      (ensure-equal 1 (call-kind-count calls :make-actor-system)
                    "Sento actor system creation")
      (ensure-equal 1 (call-kind-count calls :actor-of)
                    "Sento actor creation")
      (ensure-equal 1 (call-kind-count calls :tell)
                    "Sento tell")
      (ensure-equal 1 (call-kind-count calls :stop)
                    "Sento actor stop"))))

(defun test-cl-couch-adapter-contract ()
  (cl-user::reset-star-lang-adapter-stubs)
  (setf cl-user::*star-lang-couch-stub-response*
        '((:ROWS
           (((:DOC "one"))
            ((:DOC "two"))))))
  (let* ((source
           "(define-couchdb-source couch-source
              (:server \"http://localhost:5984\")
              (:path (list \"flock\" \"_all_docs\"))
              (:keys (list :include_docs true)))
            (load-documents couch-source documents
              (:limit 1)
              (:dataset \"couch-documents\"))")
         (plan (star-lang.core:compile-program
                source :source-name "couch-contract.star"))
         (runtime
           (star-lang.core:make-script-runtime
            :couchdb-adapter
            (star-lang.core::make-cl-couch-source-adapter))))
    (star-lang.core:run-script plan runtime)
    (ensure-equal '("one")
                  (star-lang.core:script-runtime-dataset
                   runtime "couch-documents")
                  "Cl-Couch decoded documents")
    (ensure-equal 1
                  (call-kind-count
                   cl-user::*star-lang-couch-stub-calls*
                   :couch-request)
                  "Cl-Couch request count")))

(defun string-octet-vector (string)
  (map 'vector #'char-code string))

(defun test-cl-rabbit-adapter-contract ()
  (cl-user::reset-star-lang-adapter-stubs)
  (setf cl-user::*star-lang-rabbit-stub-bodies*
        (list (string-octet-vector "one")
              (string-octet-vector "two")))
  (let* ((source
           "(define-rabbitmq-source rabbit-source
              (:host \"localhost\")
              (:port 5672)
              (:vhost \"/\")
              (:username \"guest\")
              (:password \"guest\")
              (:queue \"flock.documents\")
              (:channel 1)
              (:ack true))
            (load-documents rabbit-source documents
              (:limit 2)
              (:dataset \"rabbit-documents\"))")
         (plan (star-lang.core:compile-program
                source :source-name "rabbit-contract.star"))
         (runtime
           (star-lang.core:make-script-runtime
            :rabbitmq-adapter
            (star-lang.core::make-cl-rabbit-source-adapter))))
    (star-lang.core:run-script plan runtime)
    (ensure-equal '("one" "two")
                  (star-lang.core:script-runtime-dataset
                   runtime "rabbit-documents")
                  "cl-rabbit decoded documents")
    (let ((calls cl-user::*star-lang-rabbit-stub-calls*))
      (ensure-equal 1 (call-kind-count calls :socket-open)
                    "RabbitMQ socket open")
      (ensure-equal 1 (call-kind-count calls :login)
                    "RabbitMQ login")
      (ensure-equal 1 (call-kind-count calls :basic-consume)
                    "RabbitMQ consume registration")
      (ensure-equal 2 (call-kind-count calls :basic-ack)
                    "RabbitMQ acknowledgements"))))

(defun run-adapter-contract-tests ()
  (test-sento-adapter-contract)
  (test-cl-couch-adapter-contract)
  (test-cl-rabbit-adapter-contract)
  (format t "Star-Lang production adapter contract tests passed.~%")
  t)

(defun run-complete-tests ()
  (run-all-tests)
  (run-adapter-contract-tests)
  t)
