(in-package #:star-lang.core.tests)

(defun temporary-journal-pathname (name)
  (merge-pathnames name (uiop:temporary-directory)))

(defun delete-journal-if-present (pathname)
  (when (probe-file pathname)
    (delete-file pathname)))

(defun test-file-journal-reopen-and-resume ()
  (multiple-value-bind (registry plan target dispatch-count)
      (make-single-effect-fixture)
    (let ((pathname
            (temporary-journal-pathname
             "star-lang-file-journal-resume.log")))
      (delete-journal-if-present pathname)
      (unwind-protect
           (progn
             (let ((journal (star-lang.core:make-file-journal pathname)))
               (multiple-value-bind (outputs runtime)
                   (star-lang.core:run-plan-durable
                    plan registry (list target) journal
                    :run-id "file-resume-run")
                 (ensure-equal 1 (length outputs)
                               "file journal initial output")
                 (ensure-equal 1
                               (star-lang.core:runtime-dispatch-count runtime)
                               "file journal initial dispatch"))
               (ensure-true
                (star-lang.core:verify-journal-integrity
                 journal "file-resume-run")
                "file journal initial integrity"))
             (let ((reopened (star-lang.core:make-file-journal pathname)))
               (multiple-value-bind (outputs runtime)
                   (star-lang.core:run-plan-durable
                    plan registry (list target) reopened
                    :run-id "file-resume-run")
                 (ensure-equal 1 (length outputs)
                               "file journal resumed output")
                 (ensure-equal 0
                               (star-lang.core:runtime-dispatch-count runtime)
                               "file journal resumed without redispatch"))
               (ensure-true
                (star-lang.core:verify-journal-integrity
                 reopened "file-resume-run")
                "file journal reopened integrity"))
             (ensure-equal 1 (funcall dispatch-count)
                           "file journal exactly-once dispatch"))
        (delete-journal-if-present pathname)))))

(defun test-file-journal-multiple-runs ()
  (multiple-value-bind (registry plan target dispatch-count)
      (make-single-effect-fixture)
    (declare (ignore dispatch-count))
    (let ((pathname
            (temporary-journal-pathname
             "star-lang-file-journal-runs.log")))
      (delete-journal-if-present pathname)
      (unwind-protect
           (let ((journal (star-lang.core:make-file-journal pathname)))
             (star-lang.core:run-plan-durable
              plan registry (list target) journal :run-id "run-a")
             (star-lang.core:run-plan-durable
              plan registry (list target) journal :run-id "run-b")
             (ensure-true
              (star-lang.core:verify-journal-integrity journal "run-a")
              "file journal run-a integrity")
             (ensure-true
              (star-lang.core:verify-journal-integrity journal "run-b")
              "file journal run-b integrity")
             (ensure-true
              (> (length
                  (star-lang.core:journal-read-events journal "run-a"))
                 0)
              "file journal run-a events")
             (ensure-true
              (> (length
                  (star-lang.core:journal-read-events journal "run-b"))
                 0)
              "file journal run-b events"))
        (delete-journal-if-present pathname)))))

(defun truncate-final-journal-byte (pathname)
  (let ((content (uiop:read-file-string pathname :external-format :utf-8)))
    (with-open-file (stream pathname
                            :direction :output
                            :if-exists :supersede
                            :external-format :utf-8)
      (write-string (subseq content 0 (1- (length content))) stream))))

(defun test-file-journal-truncation-detection ()
  (multiple-value-bind (registry plan target dispatch-count)
      (make-single-effect-fixture)
    (declare (ignore dispatch-count))
    (let ((pathname
            (temporary-journal-pathname
             "star-lang-file-journal-truncated.log")))
      (delete-journal-if-present pathname)
      (unwind-protect
           (progn
             (star-lang.core:run-plan-durable
              plan registry (list target)
              (star-lang.core:make-file-journal pathname)
              :run-id "truncated-run")
             (truncate-final-journal-byte pathname)
             (ensure-true
              (signals-code-p
               :missing-journal-frame-terminator
               (lambda ()
                 (star-lang.core:journal-read-events
                  (star-lang.core:make-file-journal pathname)
                  "truncated-run")))
              "truncated file journal detection"))
        (delete-journal-if-present pathname)))))

(defun test-file-journal-frame-bound ()
  (multiple-value-bind (registry plan target dispatch-count)
      (make-single-effect-fixture)
    (declare (ignore dispatch-count))
    (let ((pathname
            (temporary-journal-pathname
             "star-lang-file-journal-bound.log")))
      (delete-journal-if-present pathname)
      (unwind-protect
           (ensure-true
            (signals-code-p
             :journal-frame-too-large
             (lambda ()
               (star-lang.core:run-plan-durable
                plan registry (list target)
                (star-lang.core:make-file-journal
                 pathname :max-frame-bytes 32)
                :run-id "bounded-run")))
            "file journal frame bound")
        (delete-journal-if-present pathname)))))

(defun run-file-journal-tests ()
  (test-file-journal-reopen-and-resume)
  (test-file-journal-multiple-runs)
  (test-file-journal-truncation-detection)
  (test-file-journal-frame-bound)
  (format t "Star-Lang file journal tests passed.~%")
  t)

(defun run-persistence-tests ()
  (run-actor-runtime-tests)
  (run-file-journal-tests)
  t)
