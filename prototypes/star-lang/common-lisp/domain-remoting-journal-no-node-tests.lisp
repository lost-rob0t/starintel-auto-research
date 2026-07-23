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

(defun no-node-journal-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S."
          label expected actual)))

(defun no-node-journal-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun no-node-journal-remoting-port ()
  (make-domain-remoting-port
   :enable (lambda (system options)
             (declare (ignore options))
             system)
   :actor-of (lambda (system name receive options)
               (declare (ignore system receive options))
               (list :actor name))
   :remote-ref (lambda (system uri options)
                 (declare (ignore system options))
                 (list :remote uri))
   :tell (lambda (actor message sender)
           (declare (ignore actor message sender))
           :sent)
   :stop (lambda (system actor)
           (declare (ignore system actor))
           :stopped)
   :disable (lambda (system)
              (declare (ignore system))
              :disabled)))

(defun no-node-journal-gateway (journal)
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library tools domain actor))
    (let* ((dispatcher (make-deterministic-dispatcher manifest))
           (gateway
             (make-main-domain-gateway
              :system :no-node-journal-test
              :remoting-port (no-node-journal-remoting-port)
              :dispatcher dispatcher
              :retry-delay-ms 2500)))
      (configure-main-domain-gateway-journal gateway journal)
      (restore-main-domain-gateway-journal gateway)
      (start-main-domain-gateway gateway)
      (values dispatcher gateway))))

(defun no-node-journal-envelope-kinds (envelopes)
  (mapcar (lambda (envelope) (getf envelope :kind)) envelopes))

(defun test-no-node-route-retry-recovery ()
  (let* ((journal (make-memory-runtime-journal-port))
         (command
           (make-bbp-run-tool-command
            :message-id "journal-no-node"
            :program-id "program:no-node"
            :run-id "run:no-node:1"
            :tool 'subfinder
            :target "api.example.com"
            :idempotency-key "journal-no-node-key")))
    (multiple-value-bind (dispatcher gateway)
        (no-node-journal-gateway journal)
      (declare (ignore gateway))
      (submit-dispatch-envelope dispatcher command)
      (no-node-journal-assert-equal
       :retry
       (run-dispatcher-next dispatcher)
       "no-node route returns retry")
      (no-node-journal-assert-equal
       '(:ack :ack)
       (no-node-journal-envelope-kinds
        (drain-dispatcher-emitted dispatcher))
       "no-node route emits accepted and retry acknowledgements")
      (no-node-journal-assert-equal
       '(:route-result)
       (mapcar (lambda (event) (getf event :kind))
               (runtime-journal-replay journal))
       "no-node retry is journaled without a pending delivery"))
    (multiple-value-bind (dispatcher gateway)
        (no-node-journal-gateway journal)
      (no-node-journal-assert-equal
       0
       (main-domain-gateway-pending-count gateway)
       "no-node retry restores no pending command")
      (no-node-journal-assert-equal
       :retry
       (deferred-dispatch-status dispatcher command)
       "no-node retry state is restored")
      (submit-dispatch-envelope dispatcher command)
      (no-node-journal-assert-equal
       :retry
       (run-dispatcher-next dispatcher)
       "restored no-node command can be attempted again")
      (no-node-journal-assert-equal
       '(:ack :ack)
       (no-node-journal-envelope-kinds
        (drain-dispatcher-emitted dispatcher))
       "reattempt emits a fresh accepted and retry pair")
      (let* ((events (runtime-journal-replay journal))
             (sequences
               (mapcar
                (lambda (event) (getf event :dispatcher-sequence))
                events)))
        (no-node-journal-assert-equal
         '(:route-result :route-result)
         (mapcar (lambda (event) (getf event :kind)) events)
         "each no-node attempt has a durable retry transition")
        (no-node-journal-assert-true
         (< (first sequences) (second sequences))
         "reattempt advances the restored dispatcher sequence")))))

(test-no-node-route-retry-recovery)
(format t "Star-Lang BBP no-node journal tests passed.~%")
