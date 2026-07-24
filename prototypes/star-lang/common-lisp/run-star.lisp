(require :asdf)

(load (merge-pathnames "star-lang-api.lisp" *load-truename*))

(in-package #:cl-user)

(defun usage (&optional (stream *standard-output*))
  (format stream
          "Usage: sbcl --script run-star.lisp load FILE [--allow-network] [--cache DIR] [--manifest FILE]~%")
  (format stream
          "       sbcl --script run-star.lisp load-url URL --name NAME --version VERSION --digest SHA256 [options]~%"))

(defun require-argument (arguments option)
  (unless arguments
    (error "Option ~A requires a value." option))
  (values (first arguments) (rest arguments)))

(defun parse-options (arguments)
  (let ((allow-network nil)
        (cache nil)
        (manifest nil)
        (name nil)
        (version nil)
        (digest nil))
    (loop while arguments
          for option = (pop arguments)
          do
             (cond
               ((string= option "--allow-network")
                (setf allow-network t))
               ((string= option "--cache")
                (multiple-value-bind (value rest)
                    (require-argument arguments option)
                  (setf cache value
                        arguments rest)))
               ((string= option "--manifest")
                (multiple-value-bind (value rest)
                    (require-argument arguments option)
                  (setf manifest value
                        arguments rest)))
               ((string= option "--name")
                (multiple-value-bind (value rest)
                    (require-argument arguments option)
                  (setf name value
                        arguments rest)))
               ((string= option "--version")
                (multiple-value-bind (value rest)
                    (require-argument arguments option)
                  (setf version value
                        arguments rest)))
               ((string= option "--digest")
                (multiple-value-bind (value rest)
                    (require-argument arguments option)
                  (setf digest value
                        arguments rest)))
               (t
                (error "Unknown option ~A." option))))
    (list :allow-network allow-network
          :cache cache
          :manifest manifest
          :name name
          :version version
          :digest digest)))

(defun option-value (options key default)
  (let ((value (getf options key)))
    (if value value default)))

(defun write-manifest-file (graph pathname)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (star-lang.loader:write-loaded-graph graph stream))
  pathname)

(defun run-load-command (source options)
  (let* ((cache
           (option-value
            options
            :cache
            (merge-pathnames #P".cache/star-lang/specs/"
                             (user-homedir-pathname))))
         (graph
           (star-lang.api:load-star-file
            source
            :allow-network (getf options :allow-network)
            :cache-directory cache)))
    (star-lang.loader:print-loaded-graph graph)
    (when (getf options :manifest)
      (write-manifest-file graph (getf options :manifest))
      (format t "Wrote loader manifest to ~A.~%"
              (getf options :manifest)))
    graph))

(defun run-load-url-command (source options)
  (let* ((cache
           (option-value
            options
            :cache
            (merge-pathnames #P".cache/star-lang/specs/"
                             (user-homedir-pathname))))
         (graph
           (star-lang.api:load-star-url
            source
            :name (getf options :name)
            :version (getf options :version)
            :digest (getf options :digest)
            :allow-network (getf options :allow-network)
            :cache-directory cache)))
    (star-lang.loader:print-loaded-graph graph)
    (when (getf options :manifest)
      (write-manifest-file graph (getf options :manifest)))
    graph))

(defun main ()
  (let ((arguments (uiop:command-line-arguments)))
    (when (or (null arguments)
              (member (first arguments)
                      '("-h" "--help" "help")
                      :test #'string=))
      (usage)
      (uiop:quit 0))
    (let ((command (pop arguments)))
      (unless arguments
        (usage *error-output*)
        (uiop:quit 2))
      (let ((source (pop arguments))
            (options (parse-options arguments)))
        (cond
          ((string= command "load")
           (run-load-command source options))
          ((string= command "load-url")
           (run-load-url-command source options))
          (t
           (error "Unknown command ~A." command)))))))

(handler-case
    (progn
      (main)
      (uiop:quit 0))
  (condition (caught)
    (format *error-output* "star: ~A~%" caught)
    (uiop:quit 1)))
