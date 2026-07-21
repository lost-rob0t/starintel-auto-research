(in-package #:star-lang.core.tests)

(defun temporary-star-file (name content)
  (let ((pathname
          (merge-pathnames
           name
           (uiop:temporary-directory))))
    (with-open-file (stream pathname
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create
                            :external-format :utf-8)
      (write-string content stream))
    pathname))

(defun test-cli-file-workflow ()
  (let ((pathname
          (temporary-star-file
           "star-lang-cli-valid.star"
           "(define-actor worker
              (:receive worker-handler)
              (:queue-size 32))
            (start-actor worker)
            (send (actor-ref 'worker) \"payload\")")))
    (unwind-protect
         (let* ((plan (star-lang.cli:compile-script-file pathname))
                (manifest (star-lang.cli:manifest-plist plan))
                (explanation (star-lang.cli:explain-script-file pathname))
                (graph (star-lang.cli:graph-script-file pathname)))
           (ensure-equal 1 (getf manifest :actors)
                         "CLI manifest actor count")
           (ensure-equal 32 (getf manifest :max-queue-size)
                         "CLI manifest queue size")
           (ensure-true (search "Star-Lang plan" explanation)
                        "CLI explanation")
           (ensure-true (search "digraph star_lang" graph)
                        "CLI graph"))
      (ignore-errors (delete-file pathname)))))

(defun test-cli-lint-workflow ()
  (let ((pathname
          (temporary-star-file
           "star-lang-cli-invalid.star"
           "(send (actor-ref 'missing) \"payload\")")))
    (unwind-protect
         (let ((diagnostics (star-lang.cli:lint-script-file pathname)))
           (ensure-true
            (diagnostic-code-present-p
             diagnostics :undefined-actor-reference)
            "CLI lint diagnostic"))
      (ignore-errors (delete-file pathname)))))

(defun test-cli-production-policy ()
  (let ((pathname
          (temporary-star-file
           "star-lang-cli-production.star"
           "(define-rabbitmq-source queue
              (:host \"localhost\")
              (:password \"secret\")
              (:queue \"documents\"))
            (load-documents queue documents (:limit 10))")))
    (unwind-protect
         (let ((diagnostics
                 (star-lang.cli:lint-script-file
                  pathname :policy :production)))
           (ensure-true
            (diagnostic-code-present-p
             diagnostics :literal-production-credential)
            "CLI production policy"))
      (ignore-errors (delete-file pathname)))))

(defun run-cli-tests ()
  (test-cli-file-workflow)
  (test-cli-lint-workflow)
  (test-cli-production-policy)
  (format t "Star-Lang CLI tests passed.~%")
  t)

(defun run-tooling-tests ()
  (run-ultra-tests)
  (run-cli-tests)
  t)
