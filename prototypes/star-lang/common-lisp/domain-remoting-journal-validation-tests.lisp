(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "core-semantics-prototype.lisp" *load-truename*))
(load (merge-pathnames "canonical-json-prototype.lisp" *load-truename*))
(load (merge-pathnames "message-lifecycle-prototype.lisp" *load-truename*))
(load (merge-pathnames "deterministic-dispatcher-prototype.lisp" *load-truename*))
(load (merge-pathnames "deferred-dispatch-completion-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-server-core-prototype.lisp" *load-truename*))
(load (merge-pathnames "bbp-domain-server-prototype.lisp" *load-truename*))
(load (merge-pathnames "runtime-journal-port-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun journal-validation-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun journal-validation-signaled-p (thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (runtime-journal-error () t)))

(defun journal-validation-command ()
  (make-bbp-run-tool-command
   :message-id "journal-validation-command"
   :program-id "program:journal-validation"
   :run-id "run:journal-validation:1"
   :tool 'subfinder
   :target "api.example.com"
   :idempotency-key "journal-validation-key"))

(defun journal-validation-pending (&key
                                     (sequence 1)
                                     (now "1970-01-01T00:00:00Z"))
  (list :kind :pending
        :dispatcher-sequence sequence
        :dispatcher-now now
        :command (journal-validation-command)))

(defun journal-validation-result (&key
                                    (outcome :retry)
                                    (sequence 1)
                                    (now "1970-01-01T00:00:00Z"))
  (list :kind :route-result
        :dispatcher-sequence sequence
        :dispatcher-now now
        :command (journal-validation-command)
        :result
        (if (eq outcome :retry)
            (retry-dispatch :retry-after-ms 1000 :reason "retry")
            (list :outcome outcome))))

(defun test-journal-event-shape-validation ()
  (let ((journal (make-memory-runtime-journal-port)))
    (journal-validation-assert-true
     (journal-validation-signaled-p
      (lambda ()
        (runtime-journal-append
         journal
         (append (journal-validation-pending)
                 (list :result
                       (retry-dispatch
                        :retry-after-ms 1000
                        :reason "invalid pending result"))))))
     "pending event rejects a result")
    (journal-validation-assert-true
     (journal-validation-signaled-p
      (lambda ()
        (runtime-journal-append
         journal
         (list :kind :route-result
               :dispatcher-sequence 1
               :dispatcher-now "1970-01-01T00:00:00Z"
               :command (journal-validation-command)))))
     "settled event requires a result")
    (journal-validation-assert-true
     (journal-validation-signaled-p
      (lambda ()
        (runtime-journal-append
         journal
         (journal-validation-result :outcome :defer))))
     "journal rejects deferred settled outcome")
    (journal-validation-assert-true
     (journal-validation-signaled-p
      (lambda ()
        (let ((event (journal-validation-pending)))
          (setf (getf (getf event :command) :kind) :event)
          (runtime-journal-append journal event))))
     "journal rejects non-command lifecycle envelope")))

(defun test-journal-order-validation ()
  (let* ((sequence-port
           (make-runtime-journal-port
            :append (lambda (event)
                      (declare (ignore event))
                      :appended)
            :replay
            (lambda ()
              (list
               (journal-validation-pending :sequence 2)
               (journal-validation-pending :sequence 1)))))
         (clock-port
           (make-runtime-journal-port
            :append (lambda (event)
                      (declare (ignore event))
                      :appended)
            :replay
            (lambda ()
              (list
               (journal-validation-pending
                :sequence 1
                :now "1970-01-01T00:00:02Z")
               (journal-validation-pending
                :sequence 1
                :now "1970-01-01T00:00:01Z"))))))
    (journal-validation-assert-true
     (journal-validation-signaled-p
      (lambda () (runtime-journal-replay sequence-port)))
     "journal rejects backward dispatcher sequence")
    (journal-validation-assert-true
     (journal-validation-signaled-p
      (lambda () (runtime-journal-replay clock-port)))
     "journal rejects backward dispatcher clock")))

(test-journal-event-shape-validation)
(test-journal-order-validation)
(format t "Star-Lang runtime journal validation tests passed.~%")
