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
(load (merge-pathnames "bbp-run-idempotency-prototype.lisp" *load-truename*))
(load (merge-pathnames "runtime-journal-port-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-remoting-prototype.lisp" *load-truename*))
(load (merge-pathnames "bbp-remote-reconnect-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-remoting-runtime-port-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-remoting-lease-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-remoting-journal-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-remoting-config-prototype.lisp" *load-truename*))
(load (merge-pathnames "sento-remoting-domain-adapter.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(export '(bbp-main-runtime-uri
          bbp-worker-runtime-actor-contract
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
  config
  uri)

(defstruct (bbp-worker-runtime (:constructor %make-bbp-worker-runtime))
  system
  remoting-port
  engine
  node
  config
  actor-contract
  uri)

(defun start-bbp-main-gserver
    (&key system
          config
          journal-port
          (heartbeat-timeout-ms 15000)
          heartbeat-clock)
  (require-domain-remoting-config config)
  (when journal-port
    (unless (runtime-journal-port-p journal-port)
      (fail 'runtime-journal-error
            "BBP main runtime journal-port must be a runtime journal port.")))
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
              :dispatcher dispatcher)))
      (configure-main-domain-gateway-lease
       gateway
       :timeout-ms heartbeat-timeout-ms
       :clock heartbeat-clock)
      (when journal-port
        (configure-main-domain-gateway-journal gateway journal-port)
        (restore-main-domain-gateway-journal gateway))
      (remoting-enable
       remoting-port
       actor-system
       (domain-remoting-config-options config))
      (let* ((resolved-config
               (resolve-domain-remoting-config
                config
                (remoting-runtime-port remoting-port actor-system)))
             (uri
               (domain-remoting-actor-uri
                resolved-config "star-domain-ingress")))
        (start-main-domain-gateway gateway)
        (%make-bbp-main-runtime
         :system actor-system
         :remoting-port remoting-port
         :dispatcher dispatcher
         :gateway gateway
         :config resolved-config
         :uri uri)))))

(defun start-bbp-tool-domain-server
    (&key main-uri
          node-id
          system
          config
          (dispatcher :shared)
          tool-runner)
  (required-nonempty-string main-uri "main gserver URI")
  (required-nonempty-string node-id "BBP node-id")
  (require-domain-remoting-config config)
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library manifest))
    (let* ((actor-system (or system (asys:make-actor-system)))
           (remoting-port (make-sento-remoting-domain-port))
           (engine
             (make-bbp-domain-engine
              domain tools (or tool-runner (make-process-tool-runner)))))
      (remoting-enable
       remoting-port
       actor-system
       (domain-remoting-config-options config))
      (let* ((resolved-config
               (resolve-domain-remoting-config
                config
                (remoting-runtime-port remoting-port actor-system)))
             (actor-contract
               (materialize-domain-actor actor resolved-config))
             (uri (getf actor-contract :endpoint))
             (node
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
         :config resolved-config
         :actor-contract actor-contract
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
