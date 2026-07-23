(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "core-semantics-prototype.lisp" *load-truename*))
(load (merge-pathnames "canonical-json-prototype.lisp" *load-truename*))
(load (merge-pathnames "message-lifecycle-prototype.lisp" *load-truename*))
(load (merge-pathnames "deterministic-dispatcher-prototype.lisp" *load-truename*))
(load (merge-pathnames "dispatcher-idempotency-identity-prototype.lisp" *load-truename*))
(load (merge-pathnames "deferred-dispatch-completion-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-server-core-prototype.lisp" *load-truename*))
(load (merge-pathnames "bbp-domain-server-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun identity-test-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S."
          label expected actual)))

(defun identity-test-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun identity-test-command (&key
                                (message-id "identity-command")
                                (idempotency-key "identity-key"))
  (make-bbp-run-tool-command
   :message-id message-id
   :program-id "program:identity"
   :run-id "run:identity:1"
   :tool 'subfinder
   :target "api.example.com"
   :idempotency-key idempotency-key))

(defun identity-test-complete-result ()
  (complete-dispatch
   :message-type +bbp-tool-run-completed-message+
   :payload
   '(("program-id" . "program:identity")
     ("run-id" . "run:identity:1")
     ("tool" . "subfinder")
     ("target" . "api.example.com")
     ("argv" . ("subfinder" "-silent" "-d" "api.example.com"))
     ("exit-code" . 0)
     ("stdout" . "ok")
     ("stderr" . ""))))

(defun identity-test-dispatcher (handler command)
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library tools domain actor))
    (let ((dispatcher (make-deterministic-dispatcher manifest)))
      (register-dispatch-handler
       dispatcher
       (getf command :actor)
       handler)
      dispatcher)))

(defun identity-test-redelivery (dispatcher command message-id sent-at)
  (let ((redelivery
          (redeliver-command
           dispatcher command
           :message-id message-id)))
    (setf (getf redelivery :sent-at) sent-at)
    redelivery))

(defun identity-test-semantic-conflict (command)
  (let ((conflict (copy-tree command)))
    (setf (getf conflict :message-id) "identity-conflict-message"
          (getf conflict :causation-id) (getf command :message-id)
          (getf conflict :attempt) (1+ (getf command :attempt))
          (cdr (assoc "target"
                      (getf conflict :payload)
                      :test #'string=))
          "other.example.com")
    conflict))

(defun identity-test-conflict-signaled-p (dispatcher command)
  (submit-dispatch-envelope dispatcher command)
  (handler-case
      (progn
        (run-dispatcher-next dispatcher)
        nil)
    (dispatcher-idempotency-conflict-error () t)))

(defun test-command-idempotency-identity ()
  (let* ((command (identity-test-command))
         (dispatcher
           (identity-test-dispatcher
            (lambda (received)
              (declare (ignore received))
              (identity-test-complete-result))
            command))
         (redelivery
           (identity-test-redelivery
            dispatcher
            command
            "identity-redelivery"
            "1970-01-01T00:00:01Z"))
         (conflict (identity-test-semantic-conflict command)))
    (identity-test-assert-equal
     (command-idempotency-identity command)
     (command-idempotency-identity redelivery)
     "delivery metadata is excluded from command identity")
    (identity-test-assert-true
     (not (equal (command-idempotency-identity command)
                 (command-idempotency-identity conflict)))
     "payload changes alter command identity")))

(defun test-terminal-record-identity ()
  (let* ((command (identity-test-command))
         (calls (list 0))
         (dispatcher
           (identity-test-dispatcher
            (lambda (received)
              (declare (ignore received))
              (incf (car calls))
              (identity-test-complete-result))
            command)))
    (submit-dispatch-envelope dispatcher command)
    (identity-test-assert-equal
     :completed
     (run-dispatcher-next dispatcher)
     "first terminal command completes")
    (let ((terminal (drain-dispatcher-emitted dispatcher)))
      (let ((redelivery
              (identity-test-redelivery
               dispatcher
               command
               "identity-terminal-redelivery"
               "1970-01-01T00:00:02Z")))
        (submit-dispatch-envelope dispatcher redelivery)
        (identity-test-assert-equal
         :duplicate
         (run-dispatcher-next dispatcher)
         "compatible terminal redelivery replays")
        (identity-test-assert-equal
         terminal
         (drain-dispatcher-emitted dispatcher)
         "terminal redelivery replays deterministic outcomes"))
      (identity-test-assert-true
       (identity-test-conflict-signaled-p
        dispatcher
        (identity-test-semantic-conflict command))
       "terminal record rejects changed command identity")
      (identity-test-assert-equal
       1 (car calls)
       "terminal identity conflict does not invoke handler"))))

(defun test-in-progress-record-identity ()
  (let* ((command
           (identity-test-command
            :message-id "identity-in-progress"
            :idempotency-key "identity-in-progress-key"))
         (calls (list 0))
         (dispatcher
           (identity-test-dispatcher
            (lambda (received)
              (declare (ignore received))
              (incf (car calls))
              (defer-dispatch))
            command)))
    (submit-dispatch-envelope dispatcher command)
    (identity-test-assert-equal
     :deferred
     (run-dispatcher-next dispatcher)
     "first command remains in progress")
    (drain-dispatcher-emitted dispatcher)
    (identity-test-assert-true
     (identity-test-conflict-signaled-p
      dispatcher
      (identity-test-semantic-conflict command))
     "in-progress record rejects changed command identity")
    (identity-test-assert-equal
     1 (car calls)
     "in-progress identity conflict does not invoke handler")))

(defun test-retry-record-identity ()
  (let* ((command
           (identity-test-command
            :message-id "identity-retry"
            :idempotency-key "identity-retry-key"))
         (calls (list 0))
         (dispatcher
           (identity-test-dispatcher
            (lambda (received)
              (declare (ignore received))
              (incf (car calls))
              (retry-dispatch
               :retry-after-ms 1000
               :reason "retry identity test"))
            command)))
    (submit-dispatch-envelope dispatcher command)
    (identity-test-assert-equal
     :retry
     (run-dispatcher-next dispatcher)
     "first command enters retry state")
    (drain-dispatcher-emitted dispatcher)
    (identity-test-assert-true
     (identity-test-conflict-signaled-p
      dispatcher
      (identity-test-semantic-conflict command))
     "retry record rejects changed command identity")
    (identity-test-assert-equal
     1 (car calls)
     "retry identity conflict does not invoke handler")))

(defun test-compatible-retry-redelivery ()
  (let* ((command
           (identity-test-command
            :message-id "identity-retry-redelivery"
            :idempotency-key "identity-retry-redelivery-key"))
         (calls (list 0))
         (dispatcher
           (identity-test-dispatcher
            (lambda (received)
              (declare (ignore received))
              (incf (car calls))
              (if (= 1 (car calls))
                  (retry-dispatch
                   :retry-after-ms 1000
                   :reason "retry once")
                  (identity-test-complete-result)))
            command)))
    (submit-dispatch-envelope dispatcher command)
    (identity-test-assert-equal
     :retry
     (run-dispatcher-next dispatcher)
     "first compatible command retries")
    (drain-dispatcher-emitted dispatcher)
    (submit-dispatch-envelope
     dispatcher
     (identity-test-redelivery
      dispatcher
      command
      "identity-retry-redelivery-2"
      "1970-01-01T00:00:03Z"))
    (identity-test-assert-equal
     :completed
     (run-dispatcher-next dispatcher)
     "compatible retry redelivery may execute again")
    (identity-test-assert-equal
     2 (car calls)
     "compatible retry redelivery invokes handler twice total")))

(test-command-idempotency-identity)
(test-terminal-record-identity)
(test-in-progress-record-identity)
(test-retry-record-identity)
(test-compatible-retry-redelivery)
(format t "Star-Lang dispatcher idempotency identity tests passed.~%")
