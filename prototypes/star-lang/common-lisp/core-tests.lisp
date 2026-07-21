(defpackage #:star-lang.core.tests
  (:use #:cl)
  (:import-from #:star-lang.core
                #:analysis-plan-hash
                #:analysis-plan-nodes
                #:compile-source
                #:core-document-content-hash
                #:core-document-persistence
                #:document-field
                #:event-signature
                #:make-core-document
                #:make-example-registry
                #:parse-source
                #:plan-node-source-span
                #:run-event-payload
                #:run-event-type
                #:run-plan
                #:runtime-dispatch-count
                #:runtime-events
                #:runtime-persisted
                #:sha256-string
                #:source-span-end-column
                #:source-span-end-line
                #:source-span-start-column
                #:source-span-start-line
                #:star-lang-error
                #:star-lang-error-code)
  (:export #:run-tests))

(in-package #:star-lang.core.tests)

(defparameter +analysis-source+
  "(analysis email-enumeration
     (:version 1)
     (:effects (:actor :agent :persist))
     (sequence
       (from target)
       (filter enumeration-target-p)
       (flat-map generate-email-candidates)
       (parallel 4 (through email-testing-actor))
       (filter found-candidate-p)
       (through review-agent)
       (checkpoint final-review-ready)
       (into persist)))")

(defparameter +branch-source+
  "(analysis branch-test
     (:version 1)
     (:effects ())
     (sequence
       (from target)
       (branch enumeration-target-p
         (then (checkpoint yes))
         (else (checkpoint no)))))")

(defun ensure-equal (expected actual label)
  (unless (equal expected actual)
    (error "~A expected ~S, received ~S." label expected actual)))

(defun ensure-true (value label)
  (unless value
    (error "~A expected a true value." label)))

(defun signals-code-p (code thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (star-lang-error (condition)
      (eq code (star-lang-error-code condition)))))

(defun count-events (events type)
  (count type events :key #'run-event-type :test #'eq))

(defun find-event (events type)
  (find type events :key #'run-event-type :test #'eq))

(defun make-registry ()
  (make-example-registry
   '("gmail.com" "outlook.com" "proton.me")
   '(("ada@gmail.com" . :found)
     ("ada@outlook.com" . :not-found)
     ("ada@proton.me" . :found))))

(defun make-target (registry &key (enumeration t))
  (let ((user
          (make-core-document
           registry
           "user"
           (list (list "username" "ada")))))
    (make-core-document
     registry
     "target"
     (list (list "enumeration" enumeration)
           (list "user" user)))))

(defun test-sha256 ()
  (ensure-equal
   "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
   (sha256-string "")
   "SHA-256 empty vector")
  (ensure-equal
   "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
   (sha256-string "abc")
   "SHA-256 abc vector"))

(defun test-reader ()
  (let* ((syntax (parse-source +analysis-source+ :source-name "analysis.star"))
         (span (star-lang.core:syntax-object-span syntax)))
    (ensure-equal 1 (source-span-start-line span) "root start line")
    (ensure-equal 1 (source-span-start-column span) "root start column")
    (ensure-true (> (source-span-end-line span) 1) "root end line")
    (ensure-true (> (source-span-end-column span) 1) "root end column"))
  (ensure-true
   (signals-code-p :forbidden-reader-syntax
                   (lambda () (parse-source "#.(error \"no\")")))
   "dispatch syntax rejection")
  (ensure-true
   (signals-code-p :forbidden-reader-syntax
                   (lambda () (parse-source "'value")))
   "quote syntax rejection")
  (ensure-true
   (signals-code-p :multiple-top-level-forms
                   (lambda () (parse-source "(a) (b)")))
   "multiple top-level form rejection")
  (ensure-true
   (signals-code-p :unterminated-string
                   (lambda () (parse-source "(a \"broken)")))
   "unterminated string rejection"))

(defun test-compiler ()
  (let* ((registry (make-registry))
         (first (compile-source +analysis-source+ registry :source-name "analysis.star"))
         (second (compile-source +analysis-source+ registry :source-name "analysis.star")))
    (ensure-equal (analysis-plan-hash first)
                  (analysis-plan-hash second)
                  "stable plan hash")
    (ensure-equal 8 (length (analysis-plan-nodes first)) "plan node count")
    (dolist (node (analysis-plan-nodes first))
      (ensure-true (plan-node-source-span node) "plan node source span")))
  (let ((registry (make-registry)))
    (ensure-true
     (signals-code-p
      :undeclared-effect
      (lambda ()
        (compile-source
         "(analysis bad (:version 1) (:effects ()) (through email-testing-actor))"
         registry)))
     "undeclared actor effect")))

(defun test-schema-validation ()
  (let ((registry (make-registry)))
    (ensure-true
     (signals-code-p
      :invalid-field-type
      (lambda ()
        (make-core-document
         registry "email-candidate"
         (list (list "username" "ada")
               (list "email" "not-an-email")))))
     "email field validation")
    (ensure-true
     (signals-code-p
      :unknown-field
      (lambda ()
        (make-core-document
         registry "user"
         (list (list "username" "ada")
               (list "extra" "no")))))
     "closed schema fields")))

(defun test-live-run-and-replay ()
  (let* ((registry (make-registry))
         (plan (compile-source +analysis-source+ registry :source-name "analysis.star"))
         (target (make-target registry)))
    (multiple-value-bind (outputs runtime)
        (run-plan plan registry (list target) :run-id "run-fixed")
      (ensure-equal 1 (length outputs) "live output count")
      (let ((review (first outputs)))
        (ensure-equal
         '("ada@gmail.com" "ada@proton.me")
         (document-field review "found-emails")
         "found emails")
        (ensure-equal :persistent
                      (core-document-persistence review)
                      "review persistence"))
      (ensure-equal 1 (length (runtime-persisted runtime)) "persisted count")
      (ensure-equal 4 (runtime-dispatch-count runtime) "live dispatch count")
      (let ((history (runtime-events runtime)))
        (ensure-equal 4 (count-events history :command-created)
                      "command-created count")
        (ensure-equal 4 (count-events history :command-result)
                      "command-result count")
        (ensure-equal 1 (count-events history :checkpoint-written)
                      "checkpoint count")
        (multiple-value-bind (replayed replay-runtime)
            (run-plan plan registry (list target)
                      :run-id "run-fixed"
                      :history history
                      :mode :replay)
          (ensure-equal 0 (runtime-dispatch-count replay-runtime)
                        "replay dispatch count")
          (ensure-equal
           (core-document-content-hash (first outputs))
           (core-document-content-hash (first replayed))
           "replay output hash")
          (ensure-equal 4
                        (count-events (runtime-events replay-runtime) :command-result)
                        "replayed command-result count"))))))

(defun test-branch ()
  (let* ((registry (make-registry))
         (plan (compile-source +branch-source+ registry :source-name "branch.star"))
         (target (make-target registry)))
    (multiple-value-bind (outputs runtime)
        (run-plan plan registry (list target) :run-id "branch-run")
      (ensure-equal 1 (length outputs) "branch output count")
      (let ((event (find-event (runtime-events runtime) :branch-selected)))
        (ensure-true event "branch event")
        (ensure-equal :then (getf (run-event-payload event) :branch)
                      "selected branch")))))

(defun test-transient-persistence ()
  (let* ((registry (make-registry))
         (source "(analysis persist-transient (:version 1) (:effects (:persist))
                    (sequence (from email-candidate) (into persist)))")
         (plan (compile-source source registry))
         (candidate
           (make-core-document
            registry "email-candidate"
            (list (list "username" "ada")
                  (list "email" "ada@example.com")))))
    (ensure-true
     (signals-code-p
      :transient-persistence-denied
      (lambda () (run-plan plan registry (list candidate))))
     "transient persistence denial")))

(defun test-event-signatures ()
  (let* ((registry (make-registry))
         (plan (compile-source +branch-source+ registry))
         (target (make-target registry)))
    (multiple-value-bind (outputs first-runtime)
        (run-plan plan registry (list target) :run-id "same-run")
      (declare (ignore outputs))
      (multiple-value-bind (second-outputs second-runtime)
          (run-plan plan registry (list target) :run-id "same-run")
        (declare (ignore second-outputs))
        (ensure-equal
         (mapcar #'event-signature (runtime-events first-runtime))
         (mapcar #'event-signature (runtime-events second-runtime))
         "deterministic pure event history")))))

(defun run-tests ()
  (test-sha256)
  (test-reader)
  (test-compiler)
  (test-schema-validation)
  (test-live-run-and-replay)
  (test-branch)
  (test-transient-persistence)
  (test-event-signatures)
  (format t "Star-Lang ASDF core tests passed.~%")
  t)
