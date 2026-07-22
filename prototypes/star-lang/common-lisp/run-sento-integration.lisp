(require :asdf)

(let ((quicklisp
        (merge-pathnames "quicklisp/setup.lisp"
                         (user-homedir-pathname))))
  (unless (probe-file quicklisp)
    (error "Quicklisp is not installed at ~A." quicklisp))
  (load quicklisp))

(ql:register-local-projects)
(ql:quickload :sento)

(let* ((directory
         (uiop/pathname:pathname-directory-pathname *load-truename*))
       (system-file (merge-pathnames "star-lang.asd" directory)))
  (asdf:load-asd system-file)
  (asdf:load-system "star-lang/sento"))

(let* ((received 0)
       (adapter (star-lang.core:make-sento-actor-adapter))
       (runtime
         (star-lang.core:make-script-runtime
          :actor-adapter adapter
          :handlers
          (list
           (cons "integration-handler"
                 (lambda (message actor-runtime)
                   (declare (ignore actor-runtime))
                   (unless (equal message "hello")
                     (error "Unexpected Sento message ~S." message))
                   (incf received)
                   :ok)))))
       (plan
         (star-lang.core:compile-program
          "(define-actor integration-worker
             (:name \"integration-worker\")
             (:receive integration-handler)
             (:dispatcher :shared)
             (:queue-size 16))
           (start-actor integration-worker)
           (send (actor-ref 'integration-worker) \"hello\")"
          :source-name "sento-integration.star")))
  (unwind-protect
       (progn
         (star-lang.core:run-script plan runtime)
         (loop repeat 200
               until (= received 1)
               do (sleep 0.01))
         (unless (= received 1)
           (error "Sento actor did not process the message."))
         (format t "Star-Lang real Sento integration passed.~%"))
    (star-lang.core::actor-adapter-shutdown adapter runtime)))
