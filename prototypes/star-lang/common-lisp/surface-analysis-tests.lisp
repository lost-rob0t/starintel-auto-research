(in-package #:star-lang.core.tests)

(defun diagnostic-code-present-p (diagnostics code)
  (find code diagnostics
        :key #'star-lang.core:script-diagnostic-code
        :test #'eq))

(defun test-static-actor-validation ()
  (ensure-true
   (signals-code-p
    :undefined-actor-reference
    (lambda ()
      (star-lang.core:compile-program
       "(send (actor-ref 'missing) \"x\")"
       :source-name "missing-actor.star")))
   "undefined actor reference")
  (ensure-true
   (signals-code-p
    :duplicate-actor-definition
    (lambda ()
      (star-lang.core:compile-program
       "(define-actor worker (:receive handler))
        (define-actor worker (:receive handler))"
       :source-name "duplicate-actor.star")))
   "duplicate actor definition")
  (ensure-true
   (signals-code-p
    :parent-actor-not-started
    (lambda ()
      (star-lang.core:compile-program
       "(define-actor parent (:receive parent-handler))
        (define-actor child (:receive child-handler) (:parent 'parent))
        (start-actor child)"
       :source-name "parent-order.star")))
   "parent starts before child")
  (let* ((base-compiler
           star-lang.core::*compile-program-before-static-analysis*)
         (plan
           (funcall
            base-compiler
            "(define-actor one (:receive one-handler) (:parent 'two))
             (define-actor two (:receive two-handler) (:parent 'one))"
            :source-name "actor-cycle.star"))
         (diagnostics (star-lang.core:lint-script-plan plan)))
    (ensure-true
     (diagnostic-code-present-p diagnostics :actor-parent-cycle)
     "actor parent cycle diagnostic")))

(defun test-static-source-validation ()
  (ensure-true
   (signals-code-p
    :unbounded-rabbitmq-read
    (lambda ()
      (star-lang.core:compile-program
       "(define-rabbitmq-source queue
          (:host \"localhost\")
          (:queue \"documents\"))
        (load-documents queue documents)"
       :source-name "unbounded-rabbit.star")))
   "RabbitMQ load requires literal bound")
  (ensure-true
   (signals-code-p
    :undefined-source-definition
    (lambda ()
      (star-lang.core:compile-program
       "(load-documents missing documents (:limit 10))"
       :source-name "missing-source.star")))
   "undefined source")
  (let ((star-lang.core:*script-compilation-policy* :production))
    (ensure-true
     (signals-code-p
      :literal-production-credential
      (lambda ()
        (star-lang.core:compile-program
         "(define-rabbitmq-source queue
            (:host \"localhost\")
            (:username \"worker\")
            (:password \"secret\")
            (:queue \"documents\"))
          (load-documents queue documents (:limit 10))"
         :source-name "literal-secret.star")))
     "production literal credential rejection")))

(defun test-plan-manifest-and-explanation ()
  (let* ((plan
           (star-lang.core:compile-program
            "(define-actor worker
               (:receive worker-handler)
               (:queue-size 128))
             (define-couchdb-source couch
               (:server \"http://localhost:5984\")
               (:database \"documents\"))
             (start-actor worker)
             (load-documents couch documents
               (:limit 500)
               (:dataset \"documents\"))
             (attach-dataset \"copy\" documents)
             (loop for document in documents
                   do (send (actor-ref 'worker) document))"
            :source-name "manifest.star"))
         (manifest (star-lang.core:script-plan-manifest plan))
         (explanation (star-lang.core:explain-script-plan plan))
         (dot (star-lang.core:script-plan-to-dot plan)))
    (ensure-equal 1
                  (star-lang.core:script-plan-manifest-actor-count manifest)
                  "manifest actor count")
    (ensure-equal 1
                  (star-lang.core:script-plan-manifest-source-count manifest)
                  "manifest source count")
    (ensure-equal 1
                  (star-lang.core:script-plan-manifest-dataset-attachment-count
                   manifest)
                  "manifest explicit dataset count")
    (ensure-equal 128
                  (star-lang.core:script-plan-manifest-max-declared-queue-size
                   manifest)
                  "manifest max queue")
    (ensure-equal 500
                  (star-lang.core:script-plan-manifest-max-source-batch manifest)
                  "manifest max source batch")
    (ensure-true (search "Star-Lang plan" explanation)
                 "plan explanation")
    (ensure-true (search "digraph star_lang" dot)
                 "plan graph output")))

(defun run-surface-analysis-tests ()
  (test-static-actor-validation)
  (test-static-source-validation)
  (test-plan-manifest-and-explanation)
  (format t "Star-Lang static analysis tests passed.~%")
  t)

(defun run-ultra-tests ()
  (run-super-advanced-tests)
  (run-surface-analysis-tests)
  t)
