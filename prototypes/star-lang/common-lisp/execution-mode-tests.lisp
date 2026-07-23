(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "core-semantics-prototype.lisp" *load-truename*))
(load (merge-pathnames "canonical-json-prototype.lisp" *load-truename*))
(load (merge-pathnames "message-lifecycle-prototype.lisp" *load-truename*))
(load (merge-pathnames "deterministic-dispatcher-prototype.lisp" *load-truename*))
(load (merge-pathnames "runtime-directory-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun execution-mode-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S."
          label expected actual)))

(defun execution-mode-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun execution-mode-condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun execution-mode-library ()
  (compile-core-library
   (load-star-form
    (merge-pathnames "../fixtures/fec-core.star" *load-truename*))))

(defun execution-mode-native-actor (library)
  (compile-actor
   '(actor fec-standalone-importer
     (:runtime native
      :accepts (ingest-page)
      :produces (index-fec-record)
      :handler fec-standalone-handler
      :restart permanent
      :mailbox (bounded 128)))
   library))

(defun execution-mode-command ()
  (make-command-envelope
   :message-id "standalone-command-1"
   :message-type "org.starintel/fec@1/ingest-page"
   :actor "fec-standalone-importer"
   :sender "standalone-test"
   :idempotency-key "standalone:fec:1"
   :dataset "fec-2026"
   :payload '(("endpoint" . "/candidates/search/")
              ("cycle" . 2026)
              ("page" . 1)
              ("results" . ())
              ("retrieved-at" . "2026-07-23T00:00:00Z"))))

(defun execution-mode-result ()
  (complete-dispatch
   :message-type "org.starintel/fec@1/index-fec-record"
   :payload
   '(("document" .
      (("schema" . "org.starintel/fec@1/candidate")
       ("id" . "H2OH03116")))
     ("source-endpoint" . "/candidates/search/")
     ("cycle" . 2026))))

(defun test-standalone-native-execution ()
  (let* ((library (execution-mode-library))
         (actor (execution-mode-native-actor library))
         (manifest (emit-core-manifest library (list actor)))
         (dispatcher
           (make-deterministic-dispatcher
            manifest :now "2026-07-23T00:00:01Z"))
         (calls 0))
    (register-dispatch-actor
     dispatcher
     "fec-standalone-importer"
     (lambda (runtime command)
       (declare (ignore runtime command))
       (incf calls)
       (execution-mode-result)))
    (submit-dispatch-envelope dispatcher (execution-mode-command))
    (execution-mode-assert-equal
     :completed
     (run-dispatcher-next dispatcher)
     "standalone dispatcher completes native actor")
    (execution-mode-assert-equal 1 calls
                                 "standalone handler executes once")
    (execution-mode-assert-equal
     '(:ack :reply :ack)
     (mapcar (lambda (envelope) (getf envelope :kind))
             (drain-dispatcher-emitted dispatcher))
     "standalone execution emits normal lifecycle outcomes")))

(defun test-runtime-directory-is-optional-introspection ()
  (let* ((context 'fake-gserver-context)
         (directory
           (make-runtime-directory-port
            :snapshot
            (lambda (received-context)
              (execution-mode-assert-equal
               context received-context
               "directory receives runtime context")
              (list
               (list :name "fec-native-importer"
                     :runtime :cl-gserver
                     :alive t
                     :path "/user/fec-native-importer")
               (list :name "stopped-worker"
                     :runtime :cl-gserver
                     :alive nil
                     :path "/user/stopped-worker"))))))
    (execution-mode-assert-equal
     '((:name "fec-native-importer"
        :runtime :cl-gserver
        :alive t
        :path "/user/fec-native-importer")
       (:name "stopped-worker"
        :runtime :cl-gserver
        :alive nil
        :path "/user/stopped-worker"))
     (runtime-directory-snapshot directory context)
     "runtime directory reports actor liveness without executing language")))

(defun test-invalid-runtime-directory-entry ()
  (let ((directory
          (make-runtime-directory-port
           :snapshot
           (lambda (context)
             (declare (ignore context))
             (list (list :name "bad"
                         :runtime :cl-gserver
                         :alive :maybe))))))
    (execution-mode-assert-true
     (execution-mode-condition-signaled-p
      'runtime-directory-error
      (lambda ()
        (runtime-directory-snapshot directory nil)))
     "runtime directory validates liveness values")))

(defun run-execution-mode-tests ()
  (test-standalone-native-execution)
  (test-runtime-directory-is-optional-introspection)
  (test-invalid-runtime-directory-entry)
  (format t "Star-Lang execution mode tests passed.~%")
  t)

(unless (run-execution-mode-tests)
  (error "Star-Lang execution mode tests failed."))