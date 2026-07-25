(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun captured-condition (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          caught
          (error caught)))))

(defun assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S." label expected actual)))

(defun call-with-temporary-star-file (content function)
  (let ((pathname
          (merge-pathnames
           (make-pathname
            :name (format nil "star-lang-loader-~36R-~36R"
                          (get-universal-time)
                          (random most-positive-fixnum))
            :type "star")
           (truename "/tmp/"))))
    (unwind-protect
         (progn
           (with-open-file (stream pathname
                                   :direction :output
                                   :if-exists :error
                                   :if-does-not-exist :create)
             (write-string content stream))
           (funcall function pathname))
      (when (probe-file pathname)
        (delete-file pathname)))))

(defmacro with-temporary-star-file ((pathname content) &body body)
  `(call-with-temporary-star-file
    ,content
    (lambda (,pathname)
      ,@body)))

(defun read-trusted-fixture-form (pathname)
  (with-open-file (stream pathname :direction :input)
    (let ((*read-eval* nil))
      (read stream nil :eof))))

(defun package-symbol-count (package)
  (let ((count 0))
    (do-symbols (symbol package count)
      (declare (ignore symbol))
      (incf count))))

(defun find-declaration (library kind name)
  (find name (declarations-of-kind library kind)
        :key (lambda (item) (getf item :name))
        :test #'string=))

(defun test-library-surface (library)
  (assert-equal :spec-library (getf library :kind) "library kind")
  (assert-equal "org.starintel/fec@1" (getf library :name) "library name")
  (assert-true (find-declaration library :document "candidate") "candidate document")
  (assert-true (find-declaration library :message "ingest-page") "ingest-page message"))

(defun test-field-compilation (library)
  (let* ((candidate (find-declaration library :document "candidate"))
         (candidate-id (find "candidate-id" (getf candidate :fields)
                             :key (lambda (field) (getf field :name))
                             :test #'string=)))
    (assert-true candidate-id "candidate-id field")
    (assert-true (getf candidate-id :required) "candidate-id is required")
    (assert-equal "org.starintel/fec@1/candidate-id"
                  (getf candidate-id :type)
                  "local type qualification")))

(defun test-portable-manifest (library native external)
  (let ((manifest (emit-portable-manifest library (list native external))))
    (assert-equal 1 (getf manifest :wire-version) "wire version")
    (assert-equal 2 (length (getf manifest :actors)) "actor count")
    (assert-true (message-contract manifest "org.starintel/fec@1/ingest-page")
                 "portable message contract")
    manifest))

(defun test-runtime-bindings (native external)
  (let ((native-binding (bind-actor-runtime native))
        (external-binding (bind-actor-runtime external)))
    (assert-equal :actor-of (getf native-binding :constructor) "native constructor")
    (assert-equal :tell (getf native-binding :send-operation) "native send")
    (assert-equal :external (getf external-binding :runtime) "external runtime")
    (assert-equal :dispatch (getf external-binding :send-operation) "external dispatch")
    (assert-equal "star-message-v1" (getf external-binding :protocol) "external protocol")))

(defun test-envelope-validation (manifest)
  (let ((envelope
          (make-wire-envelope
           :message-type "org.starintel/fec@1/ingest-page"
           :message-id "01JTEST"
           :actor "fec-importer"
           :dataset "fec-2026"
           :payload '(("endpoint" . "/candidates/search/")
                      ("page" . 1)
                      ("results" . ())
                      ("retrieved-at" . "2026-07-22T20:00:00Z")))))
    (assert-true (validate-wire-envelope manifest envelope)
                 "valid envelope accepted")
    (let ((missing-field-rejected-p
            (condition-signaled-p
             'invalid-envelope-error
             (lambda ()
               (validate-wire-envelope
                manifest
                (make-wire-envelope
                 :message-type "org.starintel/fec@1/ingest-page"
                 :message-id "01JBROKEN"
                 :actor "fec-importer"
                 :payload '(("page" . 1))))))))
      (assert-true missing-field-rejected-p
                   "missing required field rejected"))))

(defun test-unknown-type-rejected ()
  (assert-true
   (condition-signaled-p
    'invalid-type-error
    (lambda ()
      (compile-spec-library
       '(spec-library "test/library@1"
          (:version "1.0.0")
          (document broken
            (:persistence persistent)
            (value not-a-real-type :required))))))
   "unknown local type rejected"))

(defun test-duplicate-declaration-rejected ()
  (assert-true
   (condition-signaled-p
    'invalid-declaration-error
    (lambda ()
      (compile-spec-library
       '(spec-library "test/library@1"
          (:version "1.0.0")
          (enum state (one two))
          (enum state (three four))))))
   "duplicate declaration rejected"))

(defun test-file-loader-compiles-exact-ir (path)
  (let ((expected
          (compile-spec-library
           (read-trusted-fixture-form path)))
        (actual (load-star-form path)))
    (assert-equal expected actual "file loader normalized IR")))

(defun test-file-loader-comments-and-whitespace ()
  (with-temporary-star-file
      (path
       " ; leading comment

         ( spec-library \"comments@1\"
           ( :version \"1\" ) ; header comment
           ( enum state ( one two ) ) )
         ; trailing comment
       ")
    (assert-equal
     (compile-spec-library
      '(spec-library "comments@1"
        (:version "1")
        (enum state (one two))))
     (load-star-form path)
     "comments and whitespace")))

(defun test-file-loader-source-errors ()
  (dolist
      (case
       '(("" star-lang-source-error "empty source")
         ("(spec-library \"one@1\" (:version \"1\")) (spec-library \"two@1\" (:version \"1\"))"
          star-lang-source-error
          "multiple top-level forms")
         ("(document wrong (:persistence persistent))"
          invalid-library-error
          "wrong top-level form")
         ("(spec-library \"broken@1\" (:version \"1\")"
          star-lang-source-error
          "malformed list")
         ("(spec-library \"broken@1\" (:version \"unterminated))"
          star-lang-source-error
          "malformed string")
         ("(spec-library \"bad@1\" (:version \"1\") #.(error \"boom\"))"
          star-lang-source-error
          "reader evaluation")
         ("(spec-library \"bad@1\" (:version \"1\") #S(foo))"
          star-lang-source-error
          "structure dispatch")
         ("(spec-library \"bad@1\" (:version \"1\") #P\"/tmp/nope\")"
          star-lang-source-error
          "pathname dispatch")
         ("(spec-library \"bad@1\" (:version \"1\") #(one two))"
          star-lang-source-error
          "vector dispatch")
         ("(spec-library \"bad@1\" (:version \"1\") cl-user::oops)"
          star-lang-source-error
          "package-qualified symbol")))
    (destructuring-bind (source condition-type label) case
      (with-temporary-star-file (path source)
        (let ((condition
                (captured-condition
                 condition-type
                 (lambda () (load-star-form path)))))
          (assert-true condition label)
          (assert-equal (namestring path)
                        (namestring
                         (star-lang-core-error-pathname condition))
                        (format nil "~A pathname" label))
          (assert-true
           (and (plusp (star-lang-core-error-line condition))
                (plusp (star-lang-core-error-column condition)))
           (format nil "~A source position" label)))))))

(defun test-file-loader-semantic-errors ()
  (dolist
      (case
       '(("(spec-library \"duplicate@1\"
            (:version \"1\")
            (enum state (one))
            (enum state (two)))"
          invalid-declaration-error
          "duplicate declaration")
         ("(spec-library \"field@1\"
            (:version \"1\")
            (document broken
              (:persistence persistent)
              (value string)))"
          invalid-field-error
          "invalid field")
         ("(spec-library \"type@1\"
            (:version \"1\")
            (document broken
              (:persistence persistent)
              (value unknown-type :required)))"
          invalid-type-error
          "invalid type")))
    (destructuring-bind (source condition-type label) case
      (with-temporary-star-file (path source)
        (let ((condition
                (captured-condition
                 condition-type
                 (lambda () (load-star-form path)))))
          (assert-true condition label)
          (assert-equal (namestring path)
                        (namestring
                         (star-lang-core-error-pathname condition))
                        (format nil "~A pathname" label))
          (assert-true
           (> (star-lang-core-error-line condition) 1)
           (format nil "~A declaration position" label)))))))

(defun test-rejected-identifiers-do-not-intern ()
  (let* ((package (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))
         (before (package-symbol-count package))
         (identifier
           (format nil "attacker-controlled-~36R"
                   (random most-positive-fixnum))))
    (with-temporary-star-file
        (path
         (format nil
                 "(spec-library \"attacker@1\" (:version \"1\") (~A value))"
                 identifier))
      (assert-true
       (condition-signaled-p
        'invalid-declaration-error
        (lambda () (load-star-form path)))
       "attacker declaration rejected"))
    (assert-equal before
                  (package-symbol-count package)
                  "rejected identifier package symbol count")))

(defun run-tests (&optional fixture-path)
  (let* ((path (or fixture-path
                   (merge-pathnames "../fixtures/fec-core.star" *load-truename*)))
         (library (load-star-form path))
         (native
           (compile-actor
            '(actor amendment-resolver
              (:runtime native
               :accepts (resolve-amendments)
               :produces (filing)
               :handler resolve-amendments-handler
               :restart transient
               :mailbox (bounded 256)
               :capabilities (read-dataset write-dataset)))
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
               :mailbox (bounded 1024)
               :capabilities (network read-dataset write-dataset)))
            library))
         (manifest nil))
    (test-library-surface library)
    (test-field-compilation library)
    (setf manifest (test-portable-manifest library native external))
    (test-runtime-bindings native external)
    (test-envelope-validation manifest)
    (test-unknown-type-rejected)
    (test-duplicate-declaration-rejected)
    (test-file-loader-compiles-exact-ir path)
    (test-file-loader-comments-and-whitespace)
    (test-file-loader-source-errors)
    (test-file-loader-semantic-errors)
    (test-rejected-identifiers-do-not-intern)
    (format t "Star-Lang core surface and wire protocol tests passed.~%")
    t))

(let ((fixture (merge-pathnames "../fixtures/fec-core.star" *load-truename*)))
  (unless (run-tests fixture)
    (error "Star-Lang core surface tests failed.")))
