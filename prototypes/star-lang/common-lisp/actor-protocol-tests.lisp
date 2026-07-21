(in-package #:star-lang.core.tests)

(defun make-protocol-registry ()
  (let ((registry (star-lang.core:make-core-registry)))
    (star-lang.core:register-schema
     registry "relation" 1 :persistent
     '(("predicate" :string t)))
    (star-lang.core:register-schema
     registry "person" 1 :persistent
     '(("name" :string t)))
    registry))

(defparameter +typed-actor-source+
  "(define-message relation-message
      (:schema 'relation))
    (define-supervisor root-supervisor
      (:strategy :one-for-one)
      (:max-restarts 2)
      (:on-exhausted :escalate))
    (define-actor relation-worker
      (:receive relation-handler)
      (:accepts (list 'relation-message))
      (:supervisor 'root-supervisor)
      (:restart :permanent)
      (:queue-size 64))
    (start-actor relation-worker)
    (send (actor-ref 'relation-worker) relation)")

(defun test-typed-actor-message ()
  (let* ((registry (make-protocol-registry))
         (relation
           (star-lang.core:make-core-document
            registry "relation" '(("predicate" "employed"))))
         (runtime
           (star-lang.core:make-script-runtime
            :environment (list (cons "relation" relation))
            :handlers
            (list
             (cons "relation-handler"
                   (lambda (message actor-runtime)
                     (declare (ignore actor-runtime))
                     (star-lang.core:document-field
                      message "predicate"))))))
         (plan
           (star-lang.core:compile-program
            +typed-actor-source+
            :source-name "typed-actor.star")))
    (star-lang.core:run-script plan runtime)
    (ensure-equal 1
                  (star-lang.core:script-runtime-send-count runtime)
                  "typed actor send count")
    (ensure-true
     (find :message-defined
           (star-lang.core:script-runtime-events runtime)
           :key #'star-lang.core::script-event-type)
     "message definition event")
    (ensure-true
     (find :supervisor-defined
           (star-lang.core:script-runtime-events runtime)
           :key #'star-lang.core::script-event-type)
     "supervisor definition event")))

(defun test-typed-actor-rejects-wrong-schema ()
  (let* ((registry (make-protocol-registry))
         (person
           (star-lang.core:make-core-document
            registry "person" '(("name" "Ada"))))
         (runtime
           (star-lang.core:make-script-runtime
            :environment (list (cons "relation" person))
            :handlers
            (list
             (cons "relation-handler"
                   (lambda (message actor-runtime)
                     (declare (ignore actor-runtime))
                     message)))))
         (plan
           (star-lang.core:compile-program
            +typed-actor-source+
            :source-name "wrong-message.star")))
    (ensure-true
     (signals-code-p
      :actor-message-contract-violation
      (lambda ()
        (star-lang.core:run-script plan runtime)))
     "typed actor rejects wrong schema")))

(defun test-protocol-static-validation ()
  (ensure-true
   (signals-code-p
    :undefined-message-contract
    (lambda ()
      (star-lang.core:compile-program
       "(define-actor worker
          (:receive handler)
          (:accepts (list 'missing-message)))"
       :source-name "missing-message.star")))
   "undefined message contract")
  (ensure-true
   (signals-code-p
    :undefined-supervisor
    (lambda ()
      (star-lang.core:compile-program
       "(define-actor worker
          (:receive handler)
          (:supervisor 'missing-supervisor))"
       :source-name "missing-supervisor.star")))
   "undefined supervisor")
  (ensure-true
   (signals-code-p
    :invalid-actor-restart-policy
    (lambda ()
      (star-lang.core:compile-program
       "(define-actor worker
          (:receive handler)
          (:restart :explode))"
       :source-name "bad-restart.star")))
   "invalid restart policy"))

(defun test-supervisor-restart-budget ()
  (let* ((source
           "(define-supervisor root
              (:max-restarts 2)
              (:on-exhausted :escalate))
            (define-actor worker
              (:receive failing-handler)
              (:supervisor 'root)
              (:restart :permanent))
            (start-actor worker)")
         (runtime
           (star-lang.core:make-script-runtime
            :handlers
            (list
             (cons "failing-handler"
                   (lambda (message actor-runtime)
                     (declare (ignore message actor-runtime))
                     (error "worker failure"))))))
         (plan
           (star-lang.core:compile-program
            source :source-name "supervisor-budget.star")))
    (star-lang.core:run-script plan runtime)
    (let* ((adapter
             (star-lang.core::script-runtime-actor-adapter runtime))
           (actor
             (star-lang.core::actor-adapter-ref
              adapter "worker" runtime)))
      (ensure-equal
       :restarted
       (star-lang.core::actor-adapter-send
        adapter actor "one" runtime)
       "first supervised restart")
      (ensure-equal
       :restarted
       (star-lang.core::actor-adapter-send
        adapter actor "two" runtime)
       "second supervised restart")
      (ensure-true
       (handler-case
           (progn
             (star-lang.core::actor-adapter-send
              adapter actor "three" runtime)
             nil)
         (error () t))
       "supervisor escalates after budget"))
    (let ((events (star-lang.core:script-runtime-events runtime)))
      (ensure-equal
       3
       (count :actor-failed events
              :key #'star-lang.core::script-event-type)
       "actor failure events")
      (ensure-equal
       2
       (count :actor-restarted events
              :key #'star-lang.core::script-event-type)
       "actor restart events")
      (ensure-equal
       1
       (count :supervisor-exhausted events
              :key #'star-lang.core::script-event-type)
       "supervisor exhausted event"))))

(defun run-actor-protocol-tests ()
  (test-typed-actor-message)
  (test-typed-actor-rejects-wrong-schema)
  (test-protocol-static-validation)
  (test-supervisor-restart-budget)
  (format t "Star-Lang actor protocol tests passed.~%")
  t)

(defun run-actor-runtime-tests ()
  (run-tooling-tests)
  (run-actor-protocol-tests)
  t)
