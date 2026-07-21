(defpackage #:star-lang.cli
  (:use #:cl)
  (:export #:compile-script-file
           #:explain-script-file
           #:graph-script-file
           #:lint-script-file
           #:main
           #:manifest-plist))

(in-package #:star-lang.cli)

(defun script-source (pathname)
  (uiop:read-file-string pathname :external-format :utf-8))

(defun compile-script-file (pathname &key (policy :development))
  (let ((star-lang.core:*script-compilation-policy* policy))
    (star-lang.core:compile-program
     (script-source pathname)
     :source-name (namestring (pathname pathname)))))

(defun lint-script-file (pathname &key (policy :development))
  (let* ((star-lang.core:*script-compilation-policy* policy)
         (source (script-source pathname))
         (plan
           (funcall star-lang.core::*compile-program-before-static-analysis*
                    source
                    :source-name (namestring (pathname pathname)))))
    (star-lang.core:lint-script-plan plan)))

(defun explain-script-file (pathname &key (policy :development))
  (star-lang.core:explain-script-plan
   (compile-script-file pathname :policy policy)))

(defun graph-script-file (pathname &key (policy :development))
  (star-lang.core:script-plan-to-dot
   (compile-script-file pathname :policy policy)))

(defun manifest-plist (plan)
  (let ((manifest (star-lang.core:script-plan-manifest plan)))
    (list
     :plan-hash (star-lang.core:script-plan-hash plan)
     :actors
     (star-lang.core:script-plan-manifest-actor-count manifest)
     :sources
     (star-lang.core:script-plan-manifest-source-count manifest)
     :dataset-attachments
     (star-lang.core:script-plan-manifest-dataset-attachment-count manifest)
     :max-queue-size
     (star-lang.core:script-plan-manifest-max-declared-queue-size manifest)
     :max-source-batch
     (star-lang.core:script-plan-manifest-max-source-batch manifest)
     :effects
     (star-lang.core:script-plan-manifest-effects manifest))))

(defun diagnostic-plist (diagnostic)
  (let ((span (star-lang.core:script-diagnostic-span diagnostic)))
    (list
     :severity (star-lang.core:script-diagnostic-severity diagnostic)
     :code (star-lang.core:script-diagnostic-code diagnostic)
     :message (star-lang.core:script-diagnostic-message diagnostic)
     :node-id (star-lang.core:script-diagnostic-node-id diagnostic)
     :source (and span (star-lang.core:source-span-source-name span))
     :line (and span (star-lang.core:source-span-start-line span))
     :column (and span (star-lang.core:source-span-start-column span)))))

(defun print-readable (value &optional (stream *standard-output*))
  (let ((*print-pretty* t)
        (*print-circle* t)
        (*print-readably* t))
    (pprint value stream)
    (terpri stream)))

(defun command-policy (arguments)
  (if (member "--production" arguments :test #'string=)
      :production
      :development))

(defun positional-arguments (arguments)
  (remove-if (lambda (argument)
               (and (> (length argument) 1)
                    (string= "--" argument :end2 2)))
             arguments))

(defun usage (&optional (stream *standard-output*))
  (format stream
          "Usage: star-lang <compile|lint|explain|graph> FILE [--production]~%"))

(defun execute-command (arguments)
  (let* ((positionals (positional-arguments arguments))
         (command (first positionals))
         (file (second positionals))
         (policy (command-policy arguments)))
    (unless (and command file)
      (usage *error-output*)
      (return-from execute-command 64))
    (handler-case
        (cond
          ((string= command "compile")
           (print-readable
            (manifest-plist
             (compile-script-file file :policy policy)))
           0)
          ((string= command "lint")
           (let ((diagnostics
                   (lint-script-file file :policy policy)))
             (dolist (diagnostic diagnostics)
               (print-readable (diagnostic-plist diagnostic)))
             (if (find :error diagnostics
                       :key #'star-lang.core:script-diagnostic-severity
                       :test #'eq)
                 1
                 0)))
          ((string= command "explain")
           (write-string
            (explain-script-file file :policy policy)
            *standard-output*)
           0)
          ((string= command "graph")
           (write-string
            (graph-script-file file :policy policy)
            *standard-output*)
           0)
          (t
           (usage *error-output*)
           64))
      (star-lang.core:star-lang-error (condition)
        (format *error-output* "~A~%" condition)
        1)
      (error (condition)
        (format *error-output* "Unhandled error: ~A~%" condition)
        70))))

(defun main ()
  (uiop:quit
   (execute-command (uiop:command-line-arguments))))
