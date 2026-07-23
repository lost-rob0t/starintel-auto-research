(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "core-semantics-prototype.lisp" *load-truename*))
(load (merge-pathnames "canonical-json-prototype.lisp" *load-truename*))
(load (merge-pathnames "message-lifecycle-prototype.lisp" *load-truename*))
(load (merge-pathnames "deterministic-dispatcher-prototype.lisp" *load-truename*))
(load (merge-pathnames "deferred-dispatch-completion-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-server-core-prototype.lisp" *load-truename*))
(load (merge-pathnames "bbp-domain-server-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-remoting-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-remoting-lease-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun lease-test-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S."
          label expected actual)))

(defun lease-test-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun lease-test-remoting-port ()
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

(defun test-main-domain-heartbeat-lease ()
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library tools domain actor))
    (let* ((clock (list 0))
           (gateway
             (make-main-domain-gateway
              :system :lease-test
              :remoting-port (lease-test-remoting-port)
              :dispatcher (make-deterministic-dispatcher manifest)))
           (command
             (make-bbp-run-tool-command
              :message-id "lease-command"
              :program-id "program:lease"
              :run-id "run:lease:1"
              :tool 'subfinder
              :target "api.example.com")))
      (configure-main-domain-gateway-lease
       gateway
       :timeout-ms 1000
       :clock (lambda () (car clock)))
      (main-domain-register-node
       gateway
       '(:node-id "lease-node"
         :domain "bbp"
         :endpoint "sento://worker:4912/user/bbp-domain"
         :tools ("subfinder")
         :generation 1
         :heartbeat 0))
      (lease-test-assert-equal
       1
       (main-domain-gateway-live-node-count gateway)
       "registered node starts live")
      (setf (car clock) 999)
      (lease-test-assert-equal
       '()
       (expire-main-domain-gateway-nodes gateway)
       "node remains live before timeout")
      (lease-test-assert-true
       (select-domain-node gateway command)
       "live node remains routable")
      (setf (car clock) 1000)
      (lease-test-assert-equal
       '("lease-node")
       (expire-main-domain-gateway-nodes gateway)
       "node expires at timeout boundary")
      (lease-test-assert-equal
       0
       (main-domain-gateway-live-node-count gateway)
       "expired node is not live")
      (lease-test-assert-equal
       nil
       (select-domain-node gateway command)
       "expired node is not routable")
      (setf (car clock) 1200)
      (main-domain-heartbeat
       gateway
       '(:node-id "lease-node"
         :domain "bbp"
         :generation 1
         :heartbeat 1))
      (lease-test-assert-equal
       1
       (main-domain-gateway-live-node-count gateway)
       "heartbeat revives node")
      (lease-test-assert-true
       (select-domain-node gateway command)
       "revived node is routable"))))

(defun test-main-domain-heartbeat-lease-validation ()
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library tools domain actor))
    (let ((gateway
            (make-main-domain-gateway
             :system :lease-test
             :remoting-port (lease-test-remoting-port)
             :dispatcher (make-deterministic-dispatcher manifest)))
          (signaled nil))
      (handler-case
          (configure-main-domain-gateway-lease gateway :timeout-ms 0)
        (domain-remoting-error ()
          (setf signaled t)))
      (lease-test-assert-true signaled "zero heartbeat timeout is rejected"))))

(test-main-domain-heartbeat-lease)
(test-main-domain-heartbeat-lease-validation)
(format t "Star-Lang domain heartbeat lease tests passed.~%")
