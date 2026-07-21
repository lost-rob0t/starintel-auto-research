(in-package #:star-lang.core.tests)

(defparameter +employment-script+
  "(define-actor name-to-email
     (:name \"name-to-email\")
     (:receive name-to-email-handler)
     (:dispatcher :shared)
     (:queue-size 128))

   (start-actor name-to-email)

   (attach-dataset \"flock\" *documents*)

   (loop for relation in *documents*
         when (and (document-type-p relation 'relation)
                   (equal (document-ref relation 'predicate)
                          \"employed\")
                   (equal (document-ref relation 'dest 'org)
                          employer))
           do (send (actor-ref 'name-to-email)
                    (document-ref relation 'source)))")

(defun make-surface-registry ()
  (let ((registry (star-lang.core:make-core-registry)))
    (star-lang.core:register-schema
     registry "person" 1 :persistent
     '(("name" :string t)))
    (star-lang.core:register-schema
     registry "destination" 1 :persistent
     '(("org" :string t)))
    (star-lang.core:register-schema
     registry "relation" 1 :persistent
     '(("predicate" :string t)
       ("dest" :document t)
       ("source" :document t)))
    registry))

(defun make-employment-documents (registry)
  (let* ((ada
           (star-lang.core:make-core-document
            registry "person" '(("name" "Ada"))))
         (grace
           (star-lang.core:make-core-document
            registry "person" '(("name" "Grace"))))
         (acme
           (star-lang.core:make-core-document
            registry "destination" '(("org" "Acme"))))
         (other
           (star-lang.core:make-core-document
            registry "destination" '(("org" "Other")))))
    (list
     (star-lang.core:make-core-document
      registry "relation"
      (list (list "predicate" "employed")
            (list "dest" acme)
            (list "source" ada)))
     (star-lang.core:make-core-document
      registry "relation"
      (list (list "predicate" "employed")
            (list "dest" other)
            (list "source" grace))))))

(defun test-common-lisp-surface ()
  (let* ((registry (make-surface-registry))
         (documents (make-employment-documents registry))
         (plan (star-lang.core:compile-program
                +employment-script+
                :source-name "employment.star"))
         (runtime
           (star-lang.core:make-script-runtime
            :environment
            (list (cons "*documents*" documents)
                  (cons "employer" "Acme"))
            :handlers
            (list
             (cons "name-to-email-handler"
                   (lambda (person actor-runtime)
                     (declare (ignore actor-runtime))
                     (star-lang.core:document-field person "name")))))))
    (multiple-value-bind (output completed-runtime)
        (star-lang.core:run-script plan runtime)
      (declare (ignore output))
      (ensure-equal 1
                    (star-lang.core:script-runtime-send-count completed-runtime)
                    "employment actor send count")
      (ensure-equal 2
                    (length
                     (star-lang.core:script-runtime-dataset
                      completed-runtime "flock"))
                    "attached flock dataset count")
      (ensure-true
       (find :actor-started
             (star-lang.core:script-runtime-events completed-runtime)
             :key #'star-lang.core::script-event-type)
       "actor start event")
      (ensure-true
       (find :message-sent
             (star-lang.core:script-runtime-events completed-runtime)
             :key #'star-lang.core::script-event-type)
       "message send event"))))

(defun test-actor-definition-and-parent ()
  (let* ((source
           "(define-actor supervisor
              (:receive supervisor-handler)
              (:dispatcher :pinned))
            (define-actor worker
              (:receive worker-handler)
              (:parent 'supervisor)
              (:queue-size 64))
            (start-actor supervisor)
            (start-actor worker)
            (send (actor-ref 'worker) \"work\")")
         (plan (star-lang.core:compile-program source :source-name "actors.star"))
         (runtime
           (star-lang.core:make-script-runtime
            :handlers
            (list
             (cons "supervisor-handler"
                   (lambda (message actor-runtime)
                     (declare (ignore actor-runtime))
                     message))
             (cons "worker-handler"
                   (lambda (message actor-runtime)
                     (declare (ignore actor-runtime))
                     (string-upcase message)))))))
    (multiple-value-bind (output completed-runtime)
        (star-lang.core:run-script plan runtime)
      (declare (ignore output))
      (ensure-equal 1
                    (star-lang.core:script-runtime-send-count completed-runtime)
                    "child actor send count"))))

(defun test-memory-document-sources ()
  (let* ((registry (make-surface-registry))
         (documents (make-employment-documents registry))
         (adapter (star-lang.core:make-memory-source-adapter))
         (source
           "(define-couchdb-source flock-couch
              (:server \"http://localhost:5984\")
              (:database \"flock\")
              (:path (list \"flock\" \"_all_docs\"))
              (:keys (list :include_docs true)))
            (define-rabbitmq-source flock-queue
              (:host \"localhost\")
              (:port 5672)
              (:vhost \"/\")
              (:username \"guest\")
              (:password \"guest\")
              (:queue \"flock.documents\")
              (:channel 1)
              (:ack true))
            (load-documents flock-couch *couch-documents*
              (:limit 1)
              (:dataset \"couch-flock\"))
            (load-documents flock-queue *rabbit-documents*
              (:limit 2)
              (:dataset \"rabbit-flock\"))")
         (plan (star-lang.core:compile-program source :source-name "sources.star")))
    (star-lang.core:memory-source-set adapter "flock-couch" documents)
    (star-lang.core:memory-source-set adapter "flock-queue" documents)
    (let ((runtime
            (star-lang.core:make-script-runtime
             :couchdb-adapter adapter
             :rabbitmq-adapter adapter)))
      (star-lang.core:run-script plan runtime)
      (ensure-equal 1
                    (length
                     (star-lang.core:script-runtime-dataset runtime "couch-flock"))
                    "mock couch dataset count")
      (ensure-equal 2
                    (length
                     (star-lang.core:script-runtime-dataset runtime "rabbit-flock"))
                    "mock rabbit dataset count")
      (ensure-equal 1
                    (length
                     (star-lang.core::runtime-variable runtime
                                                       "*couch-documents*"))
                    "mock couch variable count"))))

(defun test-loop-collect-and-append ()
  (let* ((source
           "(set numbers (list 1 2 3))
            (loop for number in numbers
                  when (not (equal number 2))
                  collect number)
            (loop for number in numbers
                  append (list number number))")
         (plan (star-lang.core:compile-program source :source-name "loop-results.star"))
         (runtime (star-lang.core:make-script-runtime)))
    (multiple-value-bind (output completed-runtime)
        (star-lang.core:run-script plan runtime)
      (declare (ignore completed-runtime))
      (ensure-equal '((1 3) (1 1 2 2 3 3)) output
                    "loop collect and append output"))))

(defun test-surface-rejections ()
  (ensure-true
   (signals-code-p
    :invalid-symbol-literal
    (lambda ()
      (star-lang.core:compile-program
       "(send (actor-ref '(bad form)) \"x\")")))
   "quoted form rejection")
  (ensure-true
   (signals-code-p
    :unknown-loop-clause
    (lambda ()
      (star-lang.core:compile-program
       "(loop for x in xs potato x)")))
   "unknown loop clause rejection")
  (ensure-true
   (signals-code-p
    :missing-actor-handler
    (lambda ()
      (star-lang.core:compile-program
       "(define-actor broken (:queue-size 10))")))
   "missing actor handler rejection"))

(defun read-example-source (pathname)
  (uiop:read-file-string pathname :external-format :utf-8))

(defun test-all-examples-compile ()
  (let* ((root (asdf:system-source-directory "star-lang"))
         (pattern (merge-pathnames "../examples/*.star" root))
         (examples (directory pattern)))
    (ensure-true (>= (length examples) 12) "many Star-Lang examples")
    (dolist (example examples)
      (star-lang.core:compile-program
       (read-example-source example)
       :source-name (namestring example)))))

(defun run-surface-tests ()
  (test-common-lisp-surface)
  (test-actor-definition-and-parent)
  (test-memory-document-sources)
  (test-loop-collect-and-append)
  (test-surface-rejections)
  (test-all-examples-compile)
  (format t "Star-Lang Common Lisp surface tests passed.~%")
  t)

(defun run-all-tests ()
  (run-tests)
  (run-surface-tests)
  t)
