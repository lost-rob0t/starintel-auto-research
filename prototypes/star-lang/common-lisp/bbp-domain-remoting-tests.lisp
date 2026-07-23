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

(in-package #:star-lang.core-surface.prototype)

(defparameter *bbp-test-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defun bbp-test-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun bbp-test-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S."
          label expected actual)))

(defun bbp-test-envelope-kinds (envelopes)
  (mapcar (lambda (envelope) (getf envelope :kind)) envelopes))

(defstruct (fake-domain-context
            (:constructor make-fake-domain-context (&key base-uri)))
  base-uri)

(defstruct (fake-domain-ref
            (:constructor make-fake-domain-ref (&key uri)))
  uri)

(defstruct (fake-domain-network
            (:constructor make-fake-domain-network ()))
  (endpoints (make-hash-table :test #'equal))
  (queue '()))

(defun fake-domain-actor-uri (context name)
  (format nil "~A/user/~A"
          (fake-domain-context-base-uri context)
          name))

(defun fake-domain-network-port (network)
  (make-domain-remoting-port
   :enable
   (lambda (system options)
     (declare (ignore options))
     system)
   :actor-of
   (lambda (system name receive options)
     (declare (ignore options))
     (let* ((uri (fake-domain-actor-uri system name))
            (ref (make-fake-domain-ref :uri uri)))
       (setf (gethash uri (fake-domain-network-endpoints network)) receive)
       ref))
   :remote-ref
   (lambda (system uri options)
     (declare (ignore system options))
     (make-fake-domain-ref :uri uri))
   :tell
   (lambda (actor message sender)
     (setf (fake-domain-network-queue network)
           (append
            (fake-domain-network-queue network)
            (list (list :actor actor
                        :message (copy-tree message)
                        :sender sender))))
     :queued)
   :stop
   (lambda (system actor)
     (declare (ignore system))
     (remhash (fake-domain-ref-uri actor)
              (fake-domain-network-endpoints network))
     :stopped)
   :disable
   (lambda (system)
     (declare (ignore system))
     :disabled)))

(defun fake-domain-pump-next (network)
  (let ((queue (fake-domain-network-queue network)))
    (when queue
      (let* ((item (first queue))
             (ref (getf item :actor))
             (uri (fake-domain-ref-uri ref))
             (receive
               (gethash uri (fake-domain-network-endpoints network))))
        (setf (fake-domain-network-queue network) (rest queue))
        (unless receive
          (fail 'domain-remoting-error
                "Fake remoting has no endpoint for ~A."
                uri))
        (funcall receive (getf item :message))))))

(defun fake-domain-pump-all (network &key (limit 100))
  (loop repeat limit
        while (fake-domain-network-queue network)
        collect (fake-domain-pump-next network)))

(defstruct (bbp-test-environment
            (:constructor %make-bbp-test-environment))
  library
  tools
  domain
  actor
  manifest
  network
  remoting-port
  main-context
  worker-context
  dispatcher
  gateway
  engine
  node
  calls)

(defun make-bbp-fake-tool-runner (calls)
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

(defun make-bbp-test-environment ()
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (let* ((network (make-fake-domain-network))
           (port (fake-domain-network-port network))
           (main-context
             (make-fake-domain-context :base-uri "sento://main:4711"))
           (worker-context
             (make-fake-domain-context :base-uri "sento://worker:4712"))
           (dispatcher (make-deterministic-dispatcher manifest))
           (gateway
             (make-main-domain-gateway
              :system main-context
              :remoting-port port
              :dispatcher dispatcher))
           (calls (list 0))
           (engine
             (make-bbp-domain-engine
              domain tools (make-bbp-fake-tool-runner calls))))
      (start-main-domain-gateway gateway)
      (let ((node
              (start-bbp-remote-node
               :node-id "bbp-node-1"
               :endpoint "sento://worker:4712/user/bbp-domain"
               :system worker-context
               :remoting-port port
               :engine engine
               :main-uri "sento://main:4711/user/star-domain-ingress"
               :tools tools)))
        (fake-domain-pump-all network)
        (%make-bbp-test-environment
         :library library
         :tools tools
         :domain domain
         :actor actor
         :manifest manifest
         :network network
         :remoting-port port
         :main-context main-context
         :worker-context worker-context
         :dispatcher dispatcher
         :gateway gateway
         :engine engine
         :node node
         :calls calls)))))

(defun write-bbp-manifest (manifest)
  (with-open-file (stream "star-lang-bbp-domain-manifest.json"
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string (canonical-manifest-json manifest) stream)
    (terpri stream)))

(defun write-bbp-trace (manifest envelopes)
  (with-open-file (stream "star-lang-bbp-remote-trace.ndjson"
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (dolist (envelope envelopes)
      (write-string
       (canonical-lifecycle-envelope-json manifest envelope)
       stream)
      (terpri stream))))

(defun test-bbp-domain-compilation ()
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library actor))
    (bbp-test-assert-equal 4 (length tools)
                           "BBP declares four fixed tools")
    (bbp-test-assert-equal
     '("subfinder" "httpx" "katana" "nmap")
     (mapcar (lambda (tool) (getf tool :name)) tools)
     "BBP tool names")
    (bbp-test-assert-equal :keyed-aggregate
                           (getf (first (getf manifest :domain-servers))
                                 :authority)
                           "BBP is a keyed domain authority")
    (bbp-test-assert-equal
     "org.starintel/bbp@1/program-id"
     (getf domain :key-type)
     "BBP domain key is program-id")
    (bbp-test-assert-equal
     '(:kind :bounded :capacity 1024)
     (getf domain :mailbox)
     "BBP domain mailbox is bounded")
    (write-bbp-manifest manifest)))

(defun test-bbp-standalone-domain-engine ()
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library actor manifest))
    (let* ((calls (list 0))
           (engine
             (make-bbp-domain-engine
              domain tools (make-bbp-fake-tool-runner calls))))
      (invoke-domain-operation
       engine "program:acme" +bbp-register-program-message+
       '(("program-id" . "program:acme")
         ("name" . "Acme BBP")
         ("scope" . ("example.com"))))
      (let ((result
              (invoke-domain-operation
               engine "program:acme" +bbp-run-tool-message+
               '(("program-id" . "program:acme")
                 ("run-id" . "run:standalone:1")
                 ("tool" . "subfinder")
                 ("target" . "api.example.com")
                 ("options" . ())))))
        (bbp-test-assert-equal
         '("subfinder" "-silent" "-d" "api.example.com")
         (cdr (assoc "argv" result :test #'string=))
         "standalone BBP builds fixed argv without a shell")
        (bbp-test-assert-equal 1 (car calls)
                               "standalone BBP executes tool once")
        (bbp-test-assert-equal 1
                               (domain-server-engine-instance-count engine)
                               "standalone BBP owns one program aggregate")))))

(defun dispatch-and-drain-accepted (environment command)
  (submit-dispatch-envelope
   (bbp-test-environment-dispatcher environment)
   command)
  (bbp-test-assert-equal
   :deferred
   (run-dispatcher-next
    (bbp-test-environment-dispatcher environment))
   "remote BBP command defers after remoting tell")
  (let ((accepted
          (drain-dispatcher-emitted
           (bbp-test-environment-dispatcher environment))))
    (bbp-test-assert-equal '(:ack)
                           (bbp-test-envelope-kinds accepted)
                           "remote command first publishes accepted")
    accepted))

(defun test-bbp-remoting-round-trip ()
  (let* ((environment (make-bbp-test-environment))
         (dispatcher (bbp-test-environment-dispatcher environment))
         (network (bbp-test-environment-network environment))
         (gateway (bbp-test-environment-gateway environment))
         (register-command
           (make-bbp-register-program-command
            :message-id "bbp-register-1"
            :program-id "program:acme"
            :name "Acme BBP"
            :scope '("example.com")))
         (trace '()))
    (bbp-test-assert-equal 1
                           (main-domain-gateway-node-count gateway)
                           "remote BBP node registers with main gserver")
    (bbp-test-assert-true
     (bbp-remote-node-registered-p
      (bbp-test-environment-node environment))
     "remote BBP node receives registration acknowledgement")
    (setf trace
          (append trace
                  (dispatch-and-drain-accepted
                   environment register-command)))
    (fake-domain-pump-all network)
    (let ((completion (drain-dispatcher-emitted dispatcher)))
      (bbp-test-assert-equal '(:reply :ack)
                             (bbp-test-envelope-kinds completion)
                             "remote registration returns reply and completion")
      (setf trace (append trace completion)))
    (bbp-test-assert-equal '("example.com")
                           (bbp-program-scope
                            (bbp-test-environment-engine environment)
                            "program:acme")
                           "remote worker owns program scope")
    (let ((tool-command
            (make-bbp-run-tool-command
             :message-id "bbp-tool-1"
             :program-id "program:acme"
             :run-id "run:remote:1"
             :tool 'subfinder
             :target "api.example.com")))
      (setf trace
            (append trace
                    (dispatch-and-drain-accepted
                     environment tool-command)))
      (fake-domain-pump-all network)
      (let ((completion (drain-dispatcher-emitted dispatcher)))
        (bbp-test-assert-equal '(:reply :ack)
                               (bbp-test-envelope-kinds completion)
                               "remote tool result returns to main gserver")
        (setf trace (append trace completion)))
      (bbp-test-assert-equal 1
                             (car (bbp-test-environment-calls environment))
                             "remote tool executes once")
      (bbp-test-assert-equal
       1
       (bbp-remote-node-program-actor-count
        (bbp-test-environment-node environment))
       "remote BBP node owns one actor for the program key")
      (bbp-test-assert-equal 0
                             (main-domain-gateway-pending-count gateway)
                             "remote completion clears pending command")
      (submit-dispatch-envelope dispatcher tool-command)
      (bbp-test-assert-equal :duplicate
                             (run-dispatcher-next dispatcher)
                             "duplicate tool command replays terminal result")
      (bbp-test-assert-equal '(:reply :ack)
                             (bbp-test-envelope-kinds
                              (drain-dispatcher-emitted dispatcher))
                             "duplicate result replays without remote tell")
      (bbp-test-assert-equal 1
                             (car (bbp-test-environment-calls environment))
                             "duplicate command does not rerun tool"))
    (send-bbp-remote-node-heartbeat
     (bbp-test-environment-node environment))
    (fake-domain-pump-all network)
    (let ((registered
            (gethash "bbp-node-1"
                     (main-domain-gateway-nodes gateway))))
      (bbp-test-assert-equal 1
                             (remote-domain-node-heartbeat registered)
                             "main gserver records remote heartbeat"))
    (write-bbp-trace (bbp-test-environment-manifest environment) trace)
    trace))

(defun test-bbp-out-of-scope-is-terminal ()
  (let* ((environment (make-bbp-test-environment))
         (dispatcher (bbp-test-environment-dispatcher environment))
         (network (bbp-test-environment-network environment)))
    (dispatch-and-drain-accepted
     environment
     (make-bbp-register-program-command
      :message-id "bbp-register-scope"
      :program-id "program:scope"
      :name "Scope Test"
      :scope '("example.com")))
    (fake-domain-pump-all network)
    (drain-dispatcher-emitted dispatcher)
    (dispatch-and-drain-accepted
     environment
     (make-bbp-run-tool-command
      :message-id "bbp-tool-outside"
      :program-id "program:scope"
      :run-id "run:outside:1"
      :tool 'httpx
      :target "outside.invalid"))
    (fake-domain-pump-all network)
    (bbp-test-assert-equal
     '(:error)
     (bbp-test-envelope-kinds (drain-dispatcher-emitted dispatcher))
     "out-of-scope tool request becomes terminal lifecycle error")
    (bbp-test-assert-equal 0
                           (car (bbp-test-environment-calls environment))
                           "out-of-scope request never invokes tool")))

(defun test-bbp-no-node-retries ()
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library tools domain actor))
    (let* ((network (make-fake-domain-network))
           (port (fake-domain-network-port network))
           (context
             (make-fake-domain-context :base-uri "sento://main:4711"))
           (dispatcher (make-deterministic-dispatcher manifest))
           (gateway
             (make-main-domain-gateway
              :system context
              :remoting-port port
              :dispatcher dispatcher
              :retry-delay-ms 2500)))
      (start-main-domain-gateway gateway)
      (submit-dispatch-envelope
       dispatcher
       (make-bbp-run-tool-command
        :message-id "bbp-no-node"
        :program-id "program:none"
        :run-id "run:none:1"
        :tool 'nmap
        :target "example.com"))
      (bbp-test-assert-equal :retry
                             (run-dispatcher-next dispatcher)
                             "missing BBP node returns retry")
      (bbp-test-assert-equal '(:ack :ack)
                             (bbp-test-envelope-kinds
                              (drain-dispatcher-emitted dispatcher))
                             "missing BBP node publishes accepted and retry"))))

(defun file-string (pathname)
  (with-open-file (stream pathname :direction :input)
    (with-output-to-string (output)
      (loop for line = (read-line stream nil nil)
            while line
            do (write-line line output)))))

(defun test-sento-remoting-adapter-contract ()
  (let ((source
          (file-string
           (merge-pathnames "sento-remoting-domain-adapter.lisp"
                            *bbp-test-directory*))))
    (dolist (needle '("rem:enable-remoting"
                      "rem:make-remote-ref"
                      "ac:actor-of"
                      "act:tell"))
      (bbp-test-assert-true
       (search needle source)
       (format nil "Sento adapter contains ~A" needle)))))

(defun run-bbp-domain-remoting-tests ()
  (test-bbp-domain-compilation)
  (test-bbp-standalone-domain-engine)
  (test-bbp-remoting-round-trip)
  (test-bbp-out-of-scope-is-terminal)
  (test-bbp-no-node-retries)
  (test-sento-remoting-adapter-contract)
  (format t "Star-Lang BBP domain remoting tests passed.~%")
  t)

(unless (run-bbp-domain-remoting-tests)
  (error "Star-Lang BBP domain remoting tests failed."))
