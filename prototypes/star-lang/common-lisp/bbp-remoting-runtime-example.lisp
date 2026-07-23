(require :asdf)
(asdf:load-system :sento-remoting)

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
(load (merge-pathnames "sento-remoting-domain-adapter.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(export '(bbp-main-runtime-uri
          drain-bbp-main-results
          run-bbp-runtime-loop
          start-bbp-main-gserver
          start-bbp-tool-domain-server
          stop-bbp-main-gserver
          stop-bbp-tool-domain-server
          submit-bbp-main-command))

(defstruct (bbp-main-runtime (:constructor %make-bbp-main-runtime))
  system
  remoting-port
  dispatcher
  gateway
  uri)

(defstruct (bbp-worker-runtime (:constructor %make-bbp-worker-runtime))
  system
  remoting-port
  engine
  node
  uri)

(defun sento-remoting-options
    (host port hostname tls-config serializer max-message-length)
  (append
   (list :host host :port port :hostname hostname)
   (when tls-config (list :tls-config tls-config))
   (when serializer (list :serializer serializer))
   (when max-message-length
     (list :max-message-length max-message-length))))

(defun start-bbp-main-gserver
    (&key system
          (host "0.0.0.0")
          (port 4711)
          (hostname "127.0.0.1")
          tls-config serializer
          (max-message-length (* 2 1024 1024)))
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library tools domain actor))
    (let* ((actor-system (or system (asys:make-actor-system)))
           (remoting-port (make-sento-remoting-domain-port))
           (dispatcher
             (make-deterministic-dispatcher manifest))
           (gateway
             (make-main-domain-gateway
              :system actor-system
              :remoting-port remoting-port
              :dispatcher dispatcher))
           (uri
             (format nil "sento://~A:~A/user/star-domain-ingress"
                     hostname port)))
      (remoting-enable
       remoting-port
       actor-system
       (sento-remoting-options
        host port hostname tls-config serializer max-message-length))
      (start-main-domain-gateway gateway)
      (%make-bbp-main-runtime
       :system actor-system
       :remoting-port remoting-port
       :dispatcher dispatcher
       :gateway gateway
       :uri uri))))

(defun start-bbp-tool-domain-server
    (&key main-uri
          node-id
          system
          (host "0.0.0.0")
          (port 4712)
          (hostname "127.0.0.1")
          tls-config serializer
          (max-message-length (* 2 1024 1024))
          (dispatcher :shared)
          tool-runner)
  (required-nonempty-string main-uri "main gserver URI")
  (required-nonempty-string node-id "BBP node-id")
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library actor manifest))
    (let* ((actor-system (or system (asys:make-actor-system)))
           (remoting-port (make-sento-remoting-domain-port))
           (engine
             (make-bbp-domain-engine
              domain tools (or tool-runner (make-process-tool-runner))))
           (uri
             (format nil "sento://~A:~A/user/bbp-domain"
                     hostname port)))
      (remoting-enable
       remoting-port
       actor-system
       (sento-remoting-options
        host port hostname tls-config serializer max-message-length))
      (let ((node
              (start-bbp-remote-node
               :node-id node-id
               :endpoint uri
               :system actor-system
               :remoting-port remoting-port
               :engine engine
               :main-uri main-uri
               :tools tools
               :dispatcher dispatcher)))
        (%make-bbp-worker-runtime
         :system actor-system
         :remoting-port remoting-port
         :engine engine
         :node node
         :uri uri)))))

(defun submit-bbp-main-command (runtime command)
  (submit-dispatch-envelope
   (bbp-main-runtime-dispatcher runtime)
   command)
  (run-dispatcher-next
   (bbp-main-runtime-dispatcher runtime)))

(defun drain-bbp-main-results (runtime)
  (drain-dispatcher-emitted
   (bbp-main-runtime-dispatcher runtime)))

(defun stop-bbp-main-gserver (runtime)
  (stop-main-domain-gateway (bbp-main-runtime-gateway runtime))
  (remoting-disable
   (bbp-main-runtime-remoting-port runtime)
   (bbp-main-runtime-system runtime))
  (ac:shutdown (bbp-main-runtime-system runtime))
  :stopped)

(defun stop-bbp-tool-domain-server (runtime)
  (stop-bbp-remote-node (bbp-worker-runtime-node runtime))
  (remoting-disable
   (bbp-worker-runtime-remoting-port runtime)
   (bbp-worker-runtime-system runtime))
  (ac:shutdown (bbp-worker-runtime-system runtime))
  :stopped)

(defun run-bbp-runtime-loop (&key (sleep-seconds 1))
  (loop (sleep sleep-seconds)))
