(require :asdf)

(unless (find-package #:star-lang.core-surface.prototype)
  (load (merge-pathnames "core-surface-prototype.lisp" *load-truename*)))

(defpackage #:star-lang.loader
  (:use #:cl)
  (:export
   #:library-node
   #:library-node-name
   #:library-node-version
   #:library-node-digest
   #:library-node-source
   #:library-node-cache-path
   #:library-node-form
   #:library-node-compiled
   #:library-node-imports
   #:loaded-graph
   #:loaded-graph-root
   #:loaded-graph-libraries
   #:loaded-graph-cache-directory
   #:loader-error
   #:loader-error-message
   #:load-star
   #:load-star-file
   #:load-star-url
   #:print-loaded-graph
   #:write-loaded-graph))

(in-package #:star-lang.loader)

(define-condition loader-error (error)
  ((message :initarg :message :reader loader-error-message))
  (:report (lambda (condition stream)
             (write-string (loader-error-message condition) stream))))

(define-condition source-error (loader-error) ())
(define-condition import-error (loader-error) ())
(define-condition digest-error (loader-error) ())
(define-condition network-disabled-error (loader-error) ())
(define-condition dependency-error (loader-error) ())

(defstruct library-node
  name
  version
  digest
  source
  cache-path
  form
  compiled
  imports)

(defstruct loaded-graph
  root
  libraries
  cache-directory)

(defparameter *maximum-source-bytes* (* 16 1024 1024))
(defparameter *maximum-form-depth* 128)
(defparameter *maximum-form-nodes* 100000)
(defparameter *curl-program* "curl")
(defparameter *sha256-program* "sha256sum")

(defun fail-loader (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun string-prefix-p (prefix value)
  (and (stringp value)
       (<= (length prefix) (length value))
       (string= prefix value :end2 (length prefix))))

(defun url-p (value)
  (or (string-prefix-p "https://" value)
      (string-prefix-p "http://" value)))

(defun full-sha256-digest-p (value)
  (and (stringp value)
       (= (length value) 71)
       (string-prefix-p "sha256:" value)
       (every (lambda (character)
                (or (digit-char-p character)
                    (find character "abcdefABCDEF")))
              (subseq value 7))))

(defun normalize-digest (value)
  (unless (full-sha256-digest-p value)
    (fail-loader 'digest-error
                 "Expected a full sha256:<64 hex digits> digest, received ~S."
                 value))
  (string-downcase value))

(defun default-cache-directory ()
  (merge-pathnames #P".cache/star-lang/specs/"
                   (user-homedir-pathname)))

(defun ensure-cache-directory (pathname)
  (let ((directory (uiop:ensure-directory-pathname pathname)))
    (ensure-directories-exist (merge-pathnames #P".keep" directory))
    directory))

(defun source-byte-length (pathname)
  (with-open-file (stream pathname :direction :input :element-type '(unsigned-byte 8))
    (file-length stream)))

(defun ensure-source-size (pathname maximum-source-bytes)
  (let ((size (source-byte-length pathname)))
    (when (> size maximum-source-bytes)
      (fail-loader 'source-error
                   "Star source ~A is ~D bytes; the configured limit is ~D."
                   pathname size maximum-source-bytes))
    size))

(defun slurp-source-file (pathname maximum-source-bytes)
  (ensure-source-size pathname maximum-source-bytes)
  (uiop:read-file-string pathname))

(defun rejecting-sharp-reader (stream character)
  (declare (ignore stream character))
  (fail-loader 'source-error
               "Dispatch reader syntax beginning with # is not part of Star-Lang source."))

(defun validate-source-tree (form)
  (let ((nodes 0)
        (active (make-hash-table :test #'eq)))
    (labels ((walk (value depth)
               (incf nodes)
               (when (> nodes *maximum-form-nodes*)
                 (fail-loader 'source-error
                              "Star source exceeds the ~D-node form limit."
                              *maximum-form-nodes*))
               (when (> depth *maximum-form-depth*)
                 (fail-loader 'source-error
                              "Star source exceeds the ~D-level nesting limit."
                              *maximum-form-depth*))
               (cond
                 ((consp value)
                  (when (gethash value active)
                    (fail-loader 'source-error
                                 "Circular reader structures are not valid Star-Lang source."))
                  (setf (gethash value active) t)
                  (walk (car value) (1+ depth))
                  (walk (cdr value) (1+ depth))
                  (remhash value active))
                 ((or (null value)
                      (symbolp value)
                      (stringp value)
                      (numberp value)
                      (characterp value))
                  t)
                 (t
                  (fail-loader 'source-error
                               "Reader object ~S is not valid Star-Lang source."
                               value)))))
      (walk form 0))
    form))

(defun read-star-source (source source-name)
  (let ((*read-eval* nil)
        (*package* (find-package #:star-lang.loader))
        (*readtable* (copy-readtable nil)))
    (set-macro-character #\# #'rejecting-sharp-reader nil *readtable*)
    (with-input-from-string (stream source)
      (let ((form (read stream nil :eof)))
        (when (eq form :eof)
          (fail-loader 'source-error "Star source ~A is empty." source-name))
        (unless (eq (read stream nil :eof) :eof)
          (fail-loader 'source-error
                       "Star source ~A must contain exactly one top-level form."
                       source-name))
        (validate-source-tree form)))))

(defun read-star-file (pathname maximum-source-bytes)
  (let ((path (truename pathname)))
    (read-star-source
     (slurp-source-file path maximum-source-bytes)
     (namestring path))))

(defun plist-key-present-p (plist key)
  (loop for tail on plist by #'cddr
        thereis (eq (first tail) key)))

(defun require-option (options key context)
  (unless (plist-key-present-p options key)
    (fail-loader 'import-error "~A requires ~S." context key))
  (getf options key))

(defun identifier-string (value)
  (string-downcase
   (etypecase value
     (string value)
     (symbol (symbol-name value)))))

(defun declaration-kind (form)
  (unless (and (consp form) (symbolp (first form)))
    (fail-loader 'source-error "Invalid Star declaration ~S." form))
  (identifier-string (first form)))

(defun parse-library-header (form)
  (unless (and (listp form)
               (>= (length form) 3)
               (string= (declaration-kind form) "spec-library"))
    (fail-loader 'source-error "Expected one spec-library form."))
  (destructuring-bind (operator name options &rest declarations) form
    (declare (ignore operator declarations))
    (unless (and (stringp name)
                 (listp options)
                 (evenp (length options)))
      (fail-loader 'source-error "Invalid spec-library header in ~S." form))
    (let ((version (require-option options :version "spec-library")))
      (unless (stringp version)
        (fail-loader 'source-error
                     "Specification library version must be a string."))
      (values name version))))

(defun raw-import-declarations (form)
  (remove-if-not
   (lambda (declaration)
     (string= (declaration-kind declaration) "import"))
   (cdddr form)))

(defun parse-import-declaration (declaration)
  (destructuring-bind (operator name &rest options) declaration
    (declare (ignore operator))
    (unless (and (stringp name)
                 (listp options)
                 (evenp (length options)))
      (fail-loader 'import-error "Invalid import declaration ~S." declaration))
    (let* ((version (require-option options :version "import"))
           (digest (normalize-digest
                    (require-option options :digest "import")))
           (url (getf options :url))
           (path (getf options :path)))
      (unless (stringp version)
        (fail-loader 'import-error
                     "Import ~A requires a string version."
                     name))
      (when (and url path)
        (fail-loader 'import-error
                     "Import ~A cannot declare both :url and :path."
                     name))
      (unless (or url path)
        (fail-loader 'import-error
                     "Import ~A requires either :url or :path."
                     name))
      (when (and url (not (url-p url)))
        (fail-loader 'import-error
                     "Import URL ~S must use http:// or https://."
                     url))
      (when (and path (not (stringp path)))
        (fail-loader 'import-error "Import path must be a string."))
      (list :name name
            :version version
            :digest digest
            :url url
            :path path))))

(defun command-output (program arguments context)
  (handler-case
      (string-trim
       '(#\Space #\Tab #\Newline #\Return)
       (uiop:run-program
        (cons program arguments)
        :output :string
        :error-output :string
        :ignore-error-status nil))
    (error (condition)
      (fail-loader 'dependency-error
                   "~A failed through ~A: ~A"
                   context program condition))))

(defun sha256-file (pathname)
  (let* ((output (command-output
                  *sha256-program*
                  (list (namestring pathname))
                  "SHA-256 calculation"))
         (separator (position-if
                     (lambda (character)
                       (find character '(#\Space #\Tab)))
                     output))
         (hex (if separator (subseq output 0 separator) output)))
    (unless (and (= (length hex) 64)
                 (every (lambda (character)
                          (or (digit-char-p character)
                              (find character "abcdefABCDEF")))
                        hex))
      (fail-loader 'digest-error
                   "Could not parse sha256sum output ~S."
                   output))
    (format nil "sha256:~A" (string-downcase hex))))

(defun verify-file-digest (pathname expected-digest)
  (let ((actual (sha256-file pathname))
        (expected (normalize-digest expected-digest)))
    (unless (string= actual expected)
      (fail-loader 'digest-error
                   "Digest mismatch for ~A: expected ~A, received ~A."
                   pathname expected actual))
    actual))

(defun digest-cache-path (cache-directory digest)
  (merge-pathnames
   (make-pathname :name (subseq (normalize-digest digest) 7)
                  :type "star")
   cache-directory))

(defun temporary-cache-path (cache-directory digest)
  (merge-pathnames
   (make-pathname
    :name (format nil ".~A.~36R.~36R"
                  (subseq (normalize-digest digest) 7 23)
                  (get-universal-time)
                  (random most-positive-fixnum))
    :type "tmp")
   cache-directory))

(defun fetch-url-to-cache (url digest cache-directory maximum-source-bytes)
  (let* ((cache-path (digest-cache-path cache-directory digest))
         (temporary-path (temporary-cache-path cache-directory digest)))
    (when (probe-file cache-path)
      (handler-case
          (progn
            (ensure-source-size cache-path maximum-source-bytes)
            (verify-file-digest cache-path digest)
            (return-from fetch-url-to-cache cache-path))
        (loader-error ()
          (ignore-errors (delete-file cache-path)))))
    (unwind-protect
         (progn
           (uiop:run-program
            (list *curl-program*
                  "--fail"
                  "--silent"
                  "--show-error"
                  "--location"
                  "--max-redirs" "5"
                  "--connect-timeout" "10"
                  "--max-time" "60"
                  "--proto" "=http,https"
                  "--output" (namestring temporary-path)
                  url)
            :output :string
            :error-output :string
            :ignore-error-status nil)
           (ensure-source-size temporary-path maximum-source-bytes)
           (verify-file-digest temporary-path digest)
           (rename-file temporary-path cache-path)
           cache-path)
      (when (probe-file temporary-path)
        (ignore-errors (delete-file temporary-path))))))

(defun resolve-local-import-path (path parent-path)
  (let* ((candidate (pathname path))
         (resolved
           (if (uiop:absolute-pathname-p candidate)
               candidate
               (merge-pathnames candidate
                                (uiop:pathname-directory-pathname parent-path)))))
    (unless (probe-file resolved)
      (fail-loader 'import-error
                   "Imported Star file ~A does not exist."
                   resolved))
    (truename resolved)))

(defun library-key (name version)
  (format nil "~A@~A" name version))

(defun compile-library-form (form)
  (star-lang.core-surface.prototype:compile-spec-library form))

(defun load-star-file (pathname
                       &key
                         (allow-network nil)
                         (cache-directory (default-cache-directory))
                         (maximum-source-bytes *maximum-source-bytes*))
  (let ((seen (make-hash-table :test #'equal))
        (active (make-hash-table :test #'equal))
        (ordered '())
        (cache (ensure-cache-directory cache-directory)))
    (labels
        ((load-library (path source expected-name expected-version expected-digest)
           (let* ((form (read-star-file path maximum-source-bytes))
                  (actual-digest (sha256-file path)))
             (when expected-digest
               (unless (string= actual-digest (normalize-digest expected-digest))
                 (fail-loader 'digest-error
                              "Digest mismatch for imported library ~A."
                              source)))
             (multiple-value-bind (name version)
                 (parse-library-header form)
               (when (and expected-name (not (string= name expected-name)))
                 (fail-loader 'import-error
                              "Import expected library ~A but ~A declared itself."
                              expected-name name))
               (when (and expected-version (not (string= version expected-version)))
                 (fail-loader 'import-error
                              "Import ~A expected version ~A but received ~A."
                              name expected-version version))
               (let* ((key (library-key name version))
                      (existing (gethash key seen)))
                 (when existing
                   (unless (string= (library-node-digest existing) actual-digest)
                     (fail-loader 'import-error
                                  "Library ~A was resolved with conflicting digests."
                                  key))
                   (return-from load-library existing))
                 (when (gethash key active)
                   (fail-loader 'import-error
                                "Specification import cycle detected at ~A."
                                key))
                 (setf (gethash key active) t)
                 (let* ((imports
                          (mapcar
                           (lambda (declaration)
                             (resolve-import
                              (parse-import-declaration declaration)
                              path))
                           (raw-import-declarations form)))
                        (compiled (compile-library-form form))
                        (node (make-library-node
                               :name name
                               :version version
                               :digest actual-digest
                               :source source
                               :cache-path path
                               :form form
                               :compiled compiled
                               :imports imports)))
                   (remhash key active)
                   (setf (gethash key seen) node)
                   (push node ordered)
                   node)))))
         (resolve-import (import parent-path)
           (let ((url (getf import :url))
                 (path (getf import :path))
                 (digest (getf import :digest)))
             (cond
               (url
                (unless allow-network
                  (let ((cached (digest-cache-path cache digest)))
                    (unless (probe-file cached)
                      (fail-loader 'network-disabled-error
                                   "Remote import ~A is not cached; rerun with network imports enabled."
                                   url))))
                (let ((cached
                        (if allow-network
                            (fetch-url-to-cache
                             url digest cache maximum-source-bytes)
                            (let ((cached-path
                                    (digest-cache-path cache digest)))
                              (unless (probe-file cached-path)
                                (fail-loader 'network-disabled-error
                                             "Remote import ~A is not cached."
                                             url))
                              (verify-file-digest cached-path digest)
                              cached-path))))
                  (load-library cached
                                url
                                (getf import :name)
                                (getf import :version)
                                digest)))
               (path
                (let ((resolved (resolve-local-import-path path parent-path)))
                  (load-library resolved
                                (namestring resolved)
                                (getf import :name)
                                (getf import :version)
                                digest)))
               (t
                (fail-loader 'import-error "Unreachable import state."))))))
      (let* ((root-path (truename pathname))
             (root (load-library root-path
                                 (namestring root-path)
                                 nil nil nil)))
        (make-loaded-graph
         :root root
         :libraries (nreverse ordered)
         :cache-directory cache)))))

(defun load-star-url (url
                      &key
                        name
                        version
                        digest
                        (allow-network nil)
                        (cache-directory (default-cache-directory))
                        (maximum-source-bytes *maximum-source-bytes*))
  (unless (and name version digest)
    (fail-loader 'import-error
                 "Loading a root URL requires :name, :version, and :digest."))
  (let* ((cache (ensure-cache-directory cache-directory))
         (normalized (normalize-digest digest))
         (cached (digest-cache-path cache normalized)))
    (setf cached
          (if allow-network
              (fetch-url-to-cache
               url normalized cache maximum-source-bytes)
              (progn
                (unless (probe-file cached)
                  (fail-loader 'network-disabled-error
                               "Root URL ~A is not cached; enable network loading."
                               url))
                (verify-file-digest cached normalized)
                cached)))
    (let ((graph (load-star-file
                  cached
                  :allow-network allow-network
                  :cache-directory cache
                  :maximum-source-bytes maximum-source-bytes)))
      (let ((root (loaded-graph-root graph)))
        (unless (and (string= name (library-node-name root))
                     (string= version (library-node-version root))
                     (string= normalized (library-node-digest root)))
          (fail-loader 'import-error
                       "Root URL identity did not match the requested library lock.")))
      graph)))

(defun load-star (source &rest arguments &key &allow-other-keys)
  (if (url-p source)
      (apply #'load-star-url source arguments)
      (apply #'load-star-file source arguments)))

(defun library-node-summary (node)
  (list :name (library-node-name node)
        :version (library-node-version node)
        :digest (library-node-digest node)
        :source (library-node-source node)
        :imports
        (mapcar (lambda (imported)
                  (library-key
                   (library-node-name imported)
                   (library-node-version imported)))
                (library-node-imports node))))

(defun write-loaded-graph (graph stream)
  (with-standard-io-syntax
    (let ((*print-pretty* t)
          (*print-circle* nil))
      (write
       (list :root
             (library-key
              (library-node-name (loaded-graph-root graph))
              (library-node-version (loaded-graph-root graph)))
             :cache-directory
             (namestring (loaded-graph-cache-directory graph))
             :libraries
             (mapcar #'library-node-summary
                     (loaded-graph-libraries graph)))
       :stream stream)
      (terpri stream)))
  graph)

(defun print-loaded-graph (graph &optional (stream *standard-output*))
  (format stream "Loaded ~A version ~A.~%"
          (library-node-name (loaded-graph-root graph))
          (library-node-version (loaded-graph-root graph)))
  (format stream "Resolved ~D specification librar~:@P.~%"
          (length (loaded-graph-libraries graph)))
  (dolist (node (loaded-graph-libraries graph))
    (format stream "  ~A ~A  ~A~%"
            (library-node-name node)
            (library-node-version node)
            (library-node-digest node)))
  graph)
