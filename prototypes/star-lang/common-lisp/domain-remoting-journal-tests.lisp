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
(load (merge-pathnames "runtime-journal-port-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-remoting-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-remoting-lease-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-remoting-journal-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun journal-test-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S."
          label expected actual)))

(defun journal-test-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun journal-test-command (&key
                               (message-id "journal-command")
                               (idempotency-key "journal-idempotency"))
  (make-bbp-run-tool-command
   :message-id message-id
   :program-id "program:journal"
   :run-id "run:journal:1"
   :tool 'subfinder
   :target "api.example.com"
   :idempotency-key idempotency-key))

(defun journal-test-result ()
  (complete-dispatch
   :message-type +bbp-tool-run-completed-message+
   :payload
   '(("program-id" . "program:journal")
     ("run-id" . "run:journal:1")
     ("tool" . "subfinder")
     ("target" . "api.example.com")
     ("argv" . ("subfinder" "-silent" "-d" "api.example.com"))
     ("exit-code" . 0)
     ("stdout" . "ok")
     ("stderr" . ""))))

(defun journal-test-event (command)
  (list :kind :pending
        :dispatcher-sequence 1
        :dispatcher-now "1970-01-01T00:00:00Z"
        :command (copy-tree command)))

(defun journal-test-remoting-port (sent fail-tell)
  (make-domain-remoting-port
   :enable
   (lambda (system options)
     (declare (ignore options))
     system)
   :actor-of
   (lambda (system name receive options)
     (declare (ignore system receive options))
     (list :actor name))
   :remote-ref
   (lambda (system uri options)
     (declare (ignore system options))
     (list :remote uri))
   :tell
   (lambda (actor message sender)
     (declare (ignore actor sender))
     (when (car fail-tell)
       (fail 'domain-remoting-error "Synthetic remote tell failure."))
     (setf (car sent)
           (append (car sent) (list (copy-tree message))))
     :sent)
   :stop
   (lambda (system actor)
     (declare (ignore system actor))
     :stopped)
   :disable
   (lambda (system)
     (declare (ignore system))
     :disabled)))

(defun journal-test-make-gateway (journal sent fail-tell)
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library tools domain actor))
    (let* ((dispatcher (make-deterministic-dispatcher manifest))
           (gateway
             (make-main-domain-gateway
              :system :journal-test
              :remoting-port
              (journal-test-remoting-port sent fail-tell)
              :dispatcher dispatcher)))
      (configure-main-domain-gateway-journal gateway journal)
      (restore-main-domain-gateway-journal gateway)
      (start-main-domain-gateway gateway)
      (values dispatcher gateway))))

(defun journal-test-register-worker (gateway)
  (main-domain-register-node
   gateway
   '(:node-id "journal-worker"
     :domain "bbp"
     :endpoint "sento://journal-worker:4912/user/bbp-domain"
     :tools ("subfinder" "httpx")
     :generation 1
     :heartbeat 0)))

(defun test-runtime-journal-ports ()
  (let* ((command (journal-test-command))
         (event (journal-test-event command))
         (memory (make-memory-runtime-journal-port))
         (path #p"/tmp/star-lang-runtime-journal-test.sexp"))
    (when (probe-file path)
      (delete-file path))
    (runtime-journal-append memory event)
    (let ((replay (runtime-journal-replay memory)))
      (journal-test-assert-equal
       (list event) replay
       "memory journal replays appended events")
      (setf (getf (first replay) :kind) :remote-result)
      (journal-test-assert-equal
       :pending
       (getf (first (runtime-journal-replay memory)) :kind)
       "memory journal replay returns defensive copies"))
    (let ((file (make-file-runtime-journal-port path)))
      (runtime-journal-append file event)
      (journal-test-assert-equal
       (list event)
       (runtime-journal-replay file)
       "file journal round-trips readable events"))
    (when (probe-file path)
      (delete-file path))))

(defun test-pending-command-recovery-and-terminal-replay ()
  (let* ((journal (make-memory-runtime-journal-port))
         (sent (list '()))
         (fail-tell (list nil))
         (command (journal-test-command)))
    (multiple-value-bind (dispatcher-1 gateway-1)
        (journal-test-make-gateway journal sent fail-tell)
      (journal-test-register-worker gateway-1)
      (submit-dispatch-envelope dispatcher-1 command)
      (journal-test-assert-equal
       :deferred
       (run-dispatcher-next dispatcher-1)
       "initial command defers after durable journal append")
      (drain-dispatcher-emitted dispatcher-1)
      (journal-test-assert-equal
       1 (length (car sent))
       "initial command is delivered once")
      (journal-test-assert-equal
       '(:pending)
       (mapcar (lambda (event) (getf event :kind))
               (runtime-journal-replay journal))
       "pending transition is durable before recovery"))
    (multiple-value-bind (dispatcher-2 gateway-2)
        (journal-test-make-gateway journal sent fail-tell)
      (journal-test-assert-equal
       1
       (main-domain-gateway-pending-count gateway-2)
       "restart restores one pending command")
      (journal-test-assert-equal
       :in-progress
       (deferred-dispatch-status dispatcher-2 command)
       "restart restores dispatcher in-progress state")
      (journal-test-register-worker gateway-2)
      (journal-test-assert-equal
       2 (length (car sent))
       "worker registration redelivers restored pending command")
      (main-domain-complete-command
       gateway-2
       (list :kind :star-domain-result
             :message-id (getf command :message-id)
             :result (journal-test-result)))
      (let ((terminal-outcomes
              (drain-dispatcher-emitted dispatcher-2))
            (terminal-sequence
              (deterministic-dispatcher-sequence dispatcher-2)))
        (journal-test-assert-equal
         0
         (main-domain-gateway-pending-count gateway-2)
         "remote completion clears restored pending command")
        (journal-test-assert-equal
         '(:pending :remote-result)
         (mapcar (lambda (event) (getf event :kind))
                 (runtime-journal-replay journal))
         "remote terminal result is durably journaled")
        (multiple-value-bind (dispatcher-3 gateway-3)
            (journal-test-make-gateway journal sent fail-tell)
          (journal-test-assert-equal
           0
           (main-domain-gateway-pending-count gateway-3)
           "second restart restores no terminal command as pending")
          (journal-test-assert-equal
           terminal-sequence
           (deterministic-dispatcher-sequence dispatcher-3)
           "dispatcher sequence is restored through terminal replay")
          (journal-test-register-worker gateway-3)
          (journal-test-assert-equal
           2 (length (car sent))
           "terminal command is not redelivered")
          (submit-dispatch-envelope dispatcher-3 command)
          (journal-test-assert-equal
           :duplicate
           (run-dispatcher-next dispatcher-3)
           "restored terminal command replays as duplicate")
          (journal-test-assert-equal
           terminal-outcomes
           (drain-dispatcher-emitted dispatcher-3)
           "terminal outcomes replay byte-for-byte after restart"))))))

(defun test-route-failure-recovery ()
  (let* ((journal (make-memory-runtime-journal-port))
         (sent (list '()))
         (fail-tell (list nil))
         (command
           (journal-test-command
            :message-id "journal-route-failure"
            :idempotency-key "journal-route-failure-key")))
    (multiple-value-bind (dispatcher-1 gateway-1)
        (journal-test-make-gateway journal sent fail-tell)
      (journal-test-register-worker gateway-1)
      (setf (car fail-tell) t)
      (submit-dispatch-envelope dispatcher-1 command)
      (journal-test-assert-equal
       :retry
       (run-dispatcher-next dispatcher-1)
       "remote tell failure returns retry")
      (drain-dispatcher-emitted dispatcher-1)
      (journal-test-assert-equal
       '(:pending :route-result)
       (mapcar (lambda (event) (getf event :kind))
               (runtime-journal-replay journal))
       "failed route journals pending and retry result"))
    (setf (car fail-tell) nil)
    (multiple-value-bind (dispatcher-2 gateway-2)
        (journal-test-make-gateway journal sent fail-tell)
      (journal-test-assert-equal
       0
       (main-domain-gateway-pending-count gateway-2)
       "route failure does not restore as pending")
      (journal-test-assert-equal
       :retry
       (deferred-dispatch-status dispatcher-2 command)
       "route retry state is restored")
      (journal-test-register-worker gateway-2)
      (journal-test-assert-equal
       0 (length (car sent))
       "failed route is not automatically redelivered"))))

(test-runtime-journal-ports)
(test-pending-command-recovery-and-terminal-replay)
(test-route-failure-recovery)
(format t "Star-Lang BBP runtime journal tests passed.~%")
