(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "core-semantics-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun semantics-condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun semantics-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun test-fec-library-semantics (fixture)
  (let* ((library (compile-core-library (load-star-form fixture)))
         (native
           (compile-actor
            '(actor amendment-resolver
              (:runtime native
               :accepts (resolve-amendments)
               :produces (filing)
               :handler resolve-amendments-handler
               :restart transient
               :mailbox (bounded 256)))
            library))
         (external
           (compile-actor
            '(actor fec-importer
              (:runtime external
               :protocol star-message-v1
               :endpoint "rabbitmq:star.fec.ingest"
               :accepts (ingest-page)
               :produces (candidate committee filing)
               :restart permanent
               :mailbox (bounded 1024)))
            library))
         (manifest (emit-core-manifest library (list native external))))
    (semantics-assert-true (= (getf manifest :wire-version) 1)
                           "FEC semantic manifest emitted")))

(defun test-inheritance-cycle-rejected ()
  (semantics-assert-true
   (semantics-condition-signaled-p
    'invalid-declaration-error
    (lambda ()
      (compile-core-library
       '(spec-library "test/cycle@1"
          (:version "1.0.0")
          (document first
            (:extends second :persistence persistent))
          (document second
            (:extends first :persistence persistent))))))
   "inheritance cycle rejected"))

(defun test-inherited-field-redefinition-rejected ()
  (semantics-assert-true
   (semantics-condition-signaled-p
    'invalid-field-error
    (lambda ()
      (compile-core-library
       '(spec-library "test/additive@1"
          (:version "1.0.0")
          (document base
            (:persistence persistent)
            (record-id string :required))
          (document child
            (:extends base :persistence persistent)
            (record-id string :required))))))
   "inherited field redefinition rejected"))

(defun test-nondocument-parent-rejected ()
  (semantics-assert-true
   (semantics-condition-signaled-p
    'invalid-type-error
    (lambda ()
      (compile-core-library
       '(spec-library "test/parent@1"
          (:version "1.0.0")
          (enum state (open closed))
          (document broken
            (:extends state :persistence persistent))))))
   "non-document parent rejected"))

(defun test-nondocument-predicate-endpoint-rejected ()
  (semantics-assert-true
   (semantics-condition-signaled-p
    'invalid-type-error
    (lambda ()
      (compile-core-library
       '(spec-library "test/predicate@1"
          (:version "1.0.0")
          (enum state (open closed))
          (document entity
            (:persistence persistent))
          (predicate invalid
            (:source state :destination entity))))))
   "non-document predicate endpoint rejected"))

(defun test-actor-accepts-message-only ()
  (let* ((library
           (compile-core-library
            '(spec-library "test/actors@1"
               (:version "1.0.0")
               (document record
                 (:persistence persistent))
               (message process
                 (:fields ((record reference :required)))))))
         (actor
           (compile-actor
            '(actor broken
              (:runtime native
               :accepts (record)
               :produces (record)
               :handler broken-handler
               :restart transient
               :mailbox (bounded 8)))
            library)))
    (semantics-assert-true
     (semantics-condition-signaled-p
      'invalid-actor-error
      (lambda () (validate-actor-contract library actor)))
     "actor accepts message contracts only")))

(defun run-semantics-tests ()
  (let ((fixture (merge-pathnames "../fixtures/fec-core.star" *load-truename*)))
    (test-fec-library-semantics fixture)
    (test-inheritance-cycle-rejected)
    (test-inherited-field-redefinition-rejected)
    (test-nondocument-parent-rejected)
    (test-nondocument-predicate-endpoint-rejected)
    (test-actor-accepts-message-only)
    (format t "Star-Lang core semantic validation tests passed.~%")
    t))

(unless (run-semantics-tests)
  (error "Star-Lang core semantic validation tests failed."))
