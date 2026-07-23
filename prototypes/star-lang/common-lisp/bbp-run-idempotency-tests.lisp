(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "core-semantics-prototype.lisp" *load-truename*))
(load (merge-pathnames "canonical-json-prototype.lisp" *load-truename*))
(load (merge-pathnames "message-lifecycle-prototype.lisp" *load-truename*))
(load (merge-pathnames "deterministic-dispatcher-prototype.lisp" *load-truename*))
(load (merge-pathnames "deferred-dispatch-completion-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-server-core-prototype.lisp" *load-truename*))
(load (merge-pathnames "bbp-domain-server-prototype.lisp" *load-truename*))
(load (merge-pathnames "bbp-run-idempotency-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun run-id-test-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S."
          label expected actual)))

(defun run-id-test-runner (calls)
  (make-tool-runner-port
   :run
   (lambda (tool argv request)
     (declare (ignore request))
     (incf (car calls))
     (list :exit-code 0
           :stdout
           (format nil "~A completed for ~A"
                   (getf tool :name)
                   (car (last argv)))
           :stderr ""))))

(defun test-bbp-run-id-replay ()
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library actor manifest))
    (let* ((calls (list 0))
           (engine
             (make-bbp-domain-engine
              domain tools (run-id-test-runner calls)))
           (payload
             '(("program-id" . "program:replay")
               ("run-id" . "run:replay:1")
               ("tool" . "subfinder")
               ("target" . "api.example.com")
               ("options" . ()))))
      (invoke-domain-operation
       engine
       "program:replay"
       +bbp-register-program-message+
       '(("program-id" . "program:replay")
         ("name" . "Replay Test")
         ("scope" . ("example.com"))))
      (let ((first
              (invoke-domain-operation
               engine
               "program:replay"
               +bbp-run-tool-message+
               payload))
            (second
              (invoke-domain-operation
               engine
               "program:replay"
               +bbp-run-tool-message+
               payload)))
        (run-id-test-assert-equal
         first second
         "same run-id replays the stored tool result")
        (run-id-test-assert-equal
         1 (car calls)
         "same run-id executes the external tool once")
        (run-id-test-assert-equal
         1
         (bbp-program-run-count engine "program:replay")
         "same run-id stores one run")
        (let ((cached
                (bbp-program-run-result
                 engine "program:replay" "run:replay:1")))
          (setf (cdr (assoc "stdout" cached :test #'string=)) "mutated")
          (run-id-test-assert-equal
           "subfinder completed for api.example.com"
           (bbp-payload-value
            (bbp-program-run-result
             engine "program:replay" "run:replay:1")
            :stdout)
           "cached run lookup returns a defensive copy"))))))

(defun test-bbp-run-id-conflict ()
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library actor manifest))
    (let* ((calls (list 0))
           (engine
             (make-bbp-domain-engine
              domain tools (run-id-test-runner calls))))
      (invoke-domain-operation
       engine
       "program:conflict"
       +bbp-register-program-message+
       '(("program-id" . "program:conflict")
         ("name" . "Conflict Test")
         ("scope" . ("example.com"))))
      (bbp-invoke-command
       engine
       (make-bbp-run-tool-command
        :message-id "run-id-first"
        :program-id "program:conflict"
        :run-id "run:conflict:1"
        :tool 'subfinder
        :target "api.example.com"))
      (let ((conflict
              (bbp-invoke-command
               engine
               (make-bbp-run-tool-command
                :message-id "run-id-conflict"
                :program-id "program:conflict"
                :run-id "run:conflict:1"
                :tool 'httpx
                :target "api.example.com"))))
        (run-id-test-assert-equal
         :fail
         (getf conflict :outcome)
         "changed request with the same run-id is terminal")
        (run-id-test-assert-equal
         "star.bbp.run-id-conflict"
         (getf conflict :code)
         "run-id conflict has a stable error code")
        (run-id-test-assert-equal
         nil
         (getf conflict :retryable)
         "run-id conflict is not retryable")
        (run-id-test-assert-equal
         1 (car calls)
         "run-id conflict does not execute another tool")))))

(test-bbp-run-id-replay)
(test-bbp-run-id-conflict)
(format t "Star-Lang BBP run-id idempotency tests passed.~%")
