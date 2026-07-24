(require :asdf)

(load (merge-pathnames "star-loader.lisp" *load-truename*))

(in-package #:star-lang.loader)

(define-condition loader-test-error (error)
  ((message :initarg :message :reader loader-test-error-message))
  (:report (lambda (condition stream)
             (write-string (loader-test-error-message condition) stream))))

(defun fail-test (control &rest arguments)
  (error 'loader-test-error :message (apply #'format nil control arguments)))

(defun assert-true (value label)
  (unless value
    (fail-test "Assertion failed: ~A." label))
  value)

(defun assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail-test "~A expected ~S, received ~S." label expected actual))
  actual)

(defun condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun temporary-test-directory ()
  (let ((directory
          (merge-pathnames
           (format nil "star-loader-tests-~36R-~36R/"
                   (get-universal-time)
                   (random most-positive-fixnum))
           (uiop:temporary-directory))))
    (ensure-directories-exist
     (merge-pathnames #P".keep" directory))
    directory))

(defun write-text-file (pathname content)
  (ensure-directories-exist pathname)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string content stream))
  pathname)

(defun declarations-of-kind (library kind)
  (remove-if-not
   (lambda (declaration)
     (eq (getf declaration :kind) kind))
   (getf library :declarations)))

(defun find-document (library name)
  (find name
        (declarations-of-kind library :document)
        :key (lambda (document) (getf document :name))
        :test #'string=))

(defun find-field (document name)
  (find name
        (getf document :fields)
        :key (lambda (field) (getf field :name))
        :test #'string=))

(defun test-starintel-schema ()
  (let* ((fixture
           (merge-pathnames
            "../fixtures/starintel-core.star"
            *load-truename*))
         (cache (temporary-test-directory)))
    (unwind-protect
         (let* ((graph
                  (load-star-file
                   fixture
                   :cache-directory cache))
                (library
                  (library-node-compiled
                   (loaded-graph-root graph)))
                (document (find-document library "document"))
                (expected
                  '("document" "person" "org" "relation" "domain"
                    "service" "port" "network" "asn" "host" "url"
                    "breach" "email" "email-message" "user" "phone"
                    "geo" "address" "message" "socialmpost" "target"
                    "actor-manifest" "artifact" "finding" "scope")))
           (assert-equal "org.starintel/core@1"
                         (library-node-name (loaded-graph-root graph))
                         "root library name")
           (assert-equal 1
                         (length (loaded-graph-libraries graph))
                         "single local library")
           (dolist (name expected)
             (assert-true
              (find-document library name)
              (format nil "ported document ~A" name)))
           (dolist (field
                    '("id" "dataset" "dtype" "schema-version"
                      "sources" "source-urls" "collected-at"
                      "observed-at" "confidence" "provenance"
                      "chain-of-custody" "labels" "tags"
                      "sensitivity" "visibility" "content-hash"
                      "raw" "extensions"))
             (assert-true
              (find-field document field)
              (format nil "base metadata field ~A" field))))
      (uiop:delete-directory-tree
       cache
       :validate t
       :if-does-not-exist :ignore))))

(defun test-local-import-and-cache ()
  (let* ((directory (temporary-test-directory))
         (cache (merge-pathnames #P"cache/" directory))
         (dependency (merge-pathnames #P"dependency.star" directory))
         (root (merge-pathnames #P"root.star" directory)))
    (unwind-protect
         (progn
           (write-text-file
            dependency
            "(spec-library \"test/dependency@1\"
  (:version \"1.0.0\")
  (document item
    (:persistence persistent)
    (id string :required)))
")
           (let ((digest (sha256-file dependency)))
             (write-text-file
              root
              (format nil
                      "(spec-library \"test/root@1\"
  (:version \"1.0.0\")
  (import \"test/dependency@1\"
    :version \"1.0.0\"
    :digest ~S
    :path \"dependency.star\")
  (document root-item
    (:persistence persistent)
    (id string :required)))
"
                      digest))
             (let ((graph
                     (load-star-file
                      root
                      :cache-directory cache)))
               (assert-equal
                2
                (length (loaded-graph-libraries graph))
                "local import graph size")
               (assert-equal
                "test/root@1"
                (library-node-name (loaded-graph-root graph))
                "local import root")
               (assert-equal
                "test/dependency@1"
                (library-node-name
                 (first
                  (library-node-imports
                   (loaded-graph-root graph))))
                "local dependency identity"))))
      (uiop:delete-directory-tree
       directory
       :validate t
       :if-does-not-exist :ignore))))

(defun test-bad-digest-rejected ()
  (let* ((directory (temporary-test-directory))
         (dependency (merge-pathnames #P"dependency.star" directory))
         (root (merge-pathnames #P"root.star" directory)))
    (unwind-protect
         (progn
           (write-text-file
            dependency
            "(spec-library \"test/dependency@1\"
  (:version \"1.0.0\")
  (document item
    (:persistence persistent)
    (id string :required)))
")
           (write-text-file
            root
            "(spec-library \"test/root@1\"
  (:version \"1.0.0\")
  (import \"test/dependency@1\"
    :version \"1.0.0\"
    :digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"
    :path \"dependency.star\")
  (document root-item
    (:persistence persistent)
    (id string :required)))
")
           (assert-true
            (condition-signaled-p
             'digest-error
             (lambda ()
               (load-star-file
                root
                :cache-directory
                (merge-pathnames #P"cache/" directory))))
            "bad local import digest rejected"))
      (uiop:delete-directory-tree
       directory
       :validate t
       :if-does-not-exist :ignore))))

(defun test-network-disabled-before-fetch ()
  (let* ((directory (temporary-test-directory))
         (root (merge-pathnames #P"root.star" directory)))
    (unwind-protect
         (progn
           (write-text-file
            root
            "(spec-library \"test/root@1\"
  (:version \"1.0.0\")
  (import \"test/remote@1\"
    :version \"1.0.0\"
    :digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"
    :url \"https://example.invalid/remote.star\")
  (document root-item
    (:persistence persistent)
    (id string :required)))
")
           (assert-true
            (condition-signaled-p
             'network-disabled-error
             (lambda ()
               (load-star-file
                root
                :cache-directory
                (merge-pathnames #P"cache/" directory))))
            "network imports require explicit enablement"))
      (uiop:delete-directory-tree
       directory
       :validate t
       :if-does-not-exist :ignore))))

(defun test-dispatch-reader-rejected ()
  (assert-true
   (condition-signaled-p
    'source-error
    (lambda ()
      (read-star-source
       "(spec-library \"bad@1\" (:version \"1\") #.(error \"boom\"))"
       "reader-test")))
   "dispatch reader syntax rejected"))

(defun run-tests ()
  (test-starintel-schema)
  (test-local-import-and-cache)
  (test-bad-digest-rejected)
  (test-network-disabled-before-fetch)
  (test-dispatch-reader-rejected)
  (format t "Star-Lang .star loader tests passed.~%")
  t)

(unless (run-tests)
  (error "Star-Lang loader tests failed."))
