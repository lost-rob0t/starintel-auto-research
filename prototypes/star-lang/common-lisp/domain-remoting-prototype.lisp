(in-package #:star-lang.core-surface.prototype)

(export '(send-bbp-remote-node-heartbeat
          main-domain-gateway-node-count
          main-domain-gateway-pending-count
          make-domain-remoting-port
          make-main-domain-gateway
          remoting-actor-of
          remoting-disable
          remoting-enable
          remoting-make-remote-ref
          remoting-stop
          remoting-tell
          start-bbp-remote-node
          bbp-remote-node-program-actor-count
          bbp-remote-node-registered-p
          start-main-domain-gateway
          stop-bbp-remote-node
          stop-main-domain-gateway))

(define-condition domain-remoting-error (star-lang-core-error) ())

(defstruct (domain-remoting-port
            (:constructor %make-domain-remoting-port))
  enable-fn
  actor-of-fn
  remote-ref-fn
  tell-fn
  stop-fn
  disable-fn)

(defun make-domain-remoting-port
    (&key enable actor-of remote-ref tell stop disable)
  (dolist (entry
           (list (cons "enable" enable)
                 (cons "actor-of" actor-of)
                 (cons "remote-ref" remote-ref)
                 (cons "tell" tell)
                 (cons "stop" stop)
                 (cons "disable" disable)))
    (unless (functionp (cdr entry))
      (fail 'domain-remoting-error
            "Domain remoting operation ~A must be a function."
            (car entry))))
  (%make-domain-remoting-port
   :enable-fn enable
   :actor-of-fn actor-of
   :remote-ref-fn remote-ref
   :tell-fn tell
   :stop-fn stop
   :disable-fn disable))

(defun call-domain-remoting-operation (operation thunk)
  (handler-case
      (funcall thunk)
    (domain-remoting-error (condition)
      (error condition))
    (error (condition)
      (fail 'domain-remoting-error
            "Domain remoting operation ~A failed: ~A"
            operation condition))))

(defun remoting-enable (port system options)
  (call-domain-remoting-operation
   "enable"
   (lambda ()
     (funcall (domain-remoting-port-enable-fn port) system options))))

(defun remoting-actor-of
    (port system name receive &key queue-size dispatcher)
  (required-nonempty-string name "remote actor name")
  (unless (functionp receive)
    (fail 'domain-remoting-error
          "Remote actor receive operation must be a function."))
  (call-domain-remoting-operation
   "actor-of"
   (lambda ()
     (funcall (domain-remoting-port-actor-of-fn port)
              system name receive
              (append
               (when queue-size (list :queue-size queue-size))
               (when dispatcher (list :dispatcher dispatcher)))))))

(defun remoting-make-remote-ref
    (port system uri &key max-queue-size dispatcher)
  (required-nonempty-string uri "remote actor URI")
  (call-domain-remoting-operation
   "make-remote-ref"
   (lambda ()
     (funcall (domain-remoting-port-remote-ref-fn port)
              system uri
              (append
               (when max-queue-size
                 (list :max-queue-size max-queue-size))
               (when dispatcher (list :dispatcher dispatcher)))))))

(defun remoting-tell (port actor message &optional sender)
  (call-domain-remoting-operation
   "tell"
   (lambda ()
     (funcall (domain-remoting-port-tell-fn port)
              actor message sender))))

(defun remoting-stop (port system actor)
  (call-domain-remoting-operation
   "stop"
   (lambda ()
     (funcall (domain-remoting-port-stop-fn port)
              system actor))))

(defun remoting-disable (port system)
  (call-domain-remoting-operation
   "disable"
   (lambda ()
     (funcall (domain-remoting-port-disable-fn port)
              system))))

(defstruct (remote-domain-node
            (:constructor make-remote-domain-node
                (&key node-id domain endpoint ref tools generation heartbeat)))
  node-id
  domain
  endpoint
  ref
  (tools '())
  (generation 1)
  heartbeat
  (alive-p t))

(defstruct (main-domain-gateway
            (:constructor %make-main-domain-gateway))
  system
  remoting-port
  dispatcher
  completion-fn
  (nodes (make-hash-table :test #'equal))
  (pending (make-hash-table :test #'equal))
  (completed (make-hash-table :test #'equal))
  actor
  (retry-delay-ms 1000)
  (started-p nil))

(defun make-main-domain-gateway
    (&key system remoting-port dispatcher completion
          (retry-delay-ms 1000))
  (unless (domain-remoting-port-p remoting-port)
    (fail 'domain-remoting-error
          "Main domain gateway requires a remoting port."))
  (unless (deterministic-dispatcher-p dispatcher)
    (fail 'domain-remoting-error
          "Main domain gateway requires a deterministic dispatcher."))
  (unless (and (integerp retry-delay-ms) (> retry-delay-ms 0))
    (fail 'domain-remoting-error
          "Main domain retry delay must be a positive integer."))
  (%make-main-domain-gateway
   :system system
   :remoting-port remoting-port
   :dispatcher dispatcher
   :completion-fn
   (or completion
       (lambda (command result)
         (finish-deferred-dispatch dispatcher command result)))
   :retry-delay-ms retry-delay-ms))

(defun main-domain-gateway-node-count (gateway)
  (hash-table-count (main-domain-gateway-nodes gateway)))

(defun main-domain-gateway-pending-count (gateway)
  (hash-table-count (main-domain-gateway-pending gateway)))

(defun domain-control-value (message key)
  (getf message key))

(defun validate-domain-registration (message)
  (ensure-plist message "domain registration" 'domain-remoting-error)
  (dolist (key '(:node-id :domain :endpoint))
    (required-nonempty-string
     (domain-control-value message key)
     (format nil "domain registration ~A" key)))
  (let ((tools (domain-control-value message :tools)))
    (unless (and (listp tools) (every #'stringp tools))
      (fail 'domain-remoting-error
            "Domain registration tools must be a string list.")))
  message)

(defun main-domain-register-node (gateway message)
  (validate-domain-registration message)
  (let* ((node-id (getf message :node-id))
         (endpoint (getf message :endpoint))
         (ref
           (remoting-make-remote-ref
            (main-domain-gateway-remoting-port gateway)
            (main-domain-gateway-system gateway)
            endpoint
            :max-queue-size 1024))
         (node
           (make-remote-domain-node
            :node-id node-id
            :domain (getf message :domain)
            :endpoint endpoint
            :ref ref
            :tools (copy-list (getf message :tools))
            :generation (or (getf message :generation) 1)
            :heartbeat (getf message :heartbeat))))
    (setf (gethash node-id (main-domain-gateway-nodes gateway)) node)
    (remoting-tell
     (main-domain-gateway-remoting-port gateway)
     ref
     (list :kind :star-domain-registered
           :node-id node-id
           :domain (getf message :domain)
           :generation (remote-domain-node-generation node))
     (main-domain-gateway-actor gateway))
    :registered))

(defun main-domain-heartbeat (gateway message)
  (ensure-plist message "domain heartbeat" 'domain-remoting-error)
  (let* ((node-id
           (required-nonempty-string
            (getf message :node-id)
            "domain heartbeat node-id"))
         (node (gethash node-id (main-domain-gateway-nodes gateway))))
    (unless node
      (fail 'domain-remoting-error
            "Heartbeat references unknown domain node ~A."
            node-id))
    (setf (remote-domain-node-heartbeat node) (getf message :heartbeat))
    (setf (remote-domain-node-generation node)
          (or (getf message :generation)
              (remote-domain-node-generation node)))
    (setf (remote-domain-node-alive-p node) t)
    :heartbeat-recorded))

(defun main-domain-complete-command (gateway message)
  (ensure-plist message "domain result" 'domain-remoting-error)
  (let* ((message-id
           (required-nonempty-string
            (getf message :message-id)
            "domain result message-id"))
         (command
           (gethash message-id (main-domain-gateway-pending gateway))))
    (cond
      (command
       (let ((result (getf message :result)))
         (ensure-plist result "domain dispatch result" 'domain-remoting-error)
         (let ((completion
                 (funcall (main-domain-gateway-completion-fn gateway)
                          command result)))
           (remhash message-id (main-domain-gateway-pending gateway))
           (setf (gethash message-id
                          (main-domain-gateway-completed gateway))
                 completion)
           completion)))
      ((gethash message-id (main-domain-gateway-completed gateway))
       :duplicate-result)
      (t
       (fail 'domain-remoting-error
             "Domain result references unknown command ~A."
             message-id)))))

(defun main-domain-gateway-receive (gateway)
  (lambda (message)
    (ensure-plist message "main domain ingress message" 'domain-remoting-error)
    (case (getf message :kind)
      (:star-domain-register
       (main-domain-register-node gateway message))
      (:star-domain-heartbeat
       (main-domain-heartbeat gateway message))
      (:star-domain-result
       (main-domain-complete-command gateway message))
      (otherwise
       (fail 'domain-remoting-error
             "Main domain ingress received unsupported message kind ~S."
             (getf message :kind))))))

(defun command-tool-name (command)
  (let ((entry (bbp-payload-entry (getf command :payload) :tool)))
    (and entry (identifier-string (cdr entry)))))

(defun node-supports-command-p (node command)
  (let ((tool (command-tool-name command)))
    (and (remote-domain-node-alive-p node)
         (string= (remote-domain-node-domain node) "bbp")
         (or (null tool)
             (member tool (remote-domain-node-tools node)
                     :test #'string=)))))

(defun select-domain-node (gateway command)
  (let ((nodes '()))
    (maphash
     (lambda (node-id node)
       (declare (ignore node-id))
       (when (node-supports-command-p node command)
         (push node nodes)))
     (main-domain-gateway-nodes gateway))
    (first
     (sort nodes #'string< :key #'remote-domain-node-node-id))))

(defun main-domain-route-command (gateway command)
  (let ((node (select-domain-node gateway command)))
    (unless node
      (return-from main-domain-route-command
        (retry-dispatch
         :retry-after-ms (main-domain-gateway-retry-delay-ms gateway)
         :reason "No live BBP domain node exports the requested tool.")))
    (let ((message-id (getf command :message-id)))
      (setf (gethash message-id (main-domain-gateway-pending gateway))
            (copy-tree command))
      (handler-case
          (progn
            (remoting-tell
             (main-domain-gateway-remoting-port gateway)
             (remote-domain-node-ref node)
             (list :kind :star-domain-command
                   :domain "bbp"
                   :node-id (remote-domain-node-node-id node)
                   :command (copy-tree command))
             (main-domain-gateway-actor gateway))
            (defer-dispatch))
        (domain-remoting-error (condition)
          (declare (ignore condition))
          (remhash message-id (main-domain-gateway-pending gateway))
          (retry-dispatch
           :retry-after-ms (main-domain-gateway-retry-delay-ms gateway)
           :reason "BBP remote tell failed before node acceptance."))))))

(defun start-main-domain-gateway (gateway)
  (when (main-domain-gateway-started-p gateway)
    (fail 'domain-remoting-error
          "Main domain gateway is already started."))
  (setf (main-domain-gateway-actor gateway)
        (remoting-actor-of
         (main-domain-gateway-remoting-port gateway)
         (main-domain-gateway-system gateway)
         "star-domain-ingress"
         (main-domain-gateway-receive gateway)
         :queue-size 1024))
  (register-dispatch-actor
   (main-domain-gateway-dispatcher gateway)
   "bbp-domain"
   (lambda (dispatcher command)
     (declare (ignore dispatcher))
     (main-domain-route-command gateway command)))
  (setf (main-domain-gateway-started-p gateway) t)
  gateway)

(defun stop-main-domain-gateway (gateway)
  (when (main-domain-gateway-started-p gateway)
    (when (main-domain-gateway-actor gateway)
      (remoting-stop
       (main-domain-gateway-remoting-port gateway)
       (main-domain-gateway-system gateway)
       (main-domain-gateway-actor gateway)))
    (setf (main-domain-gateway-started-p gateway) nil))
  :stopped)

(defstruct (bbp-remote-node
            (:constructor %make-bbp-remote-node))
  node-id
  endpoint
  system
  remoting-port
  engine
  actor
  main-ref
  (program-actors (make-hash-table :test #'equal))
  (program-dispatcher :shared)
  (generation 1)
  (heartbeat 0)
  (registered-p nil)
  (started-p nil))

(defun bbp-remote-node-registration (node tools)
  (list :kind :star-domain-register
        :node-id (bbp-remote-node-node-id node)
        :domain "bbp"
        :endpoint (bbp-remote-node-endpoint node)
        :tools (mapcar (lambda (tool) (getf tool :name)) tools)
        :generation (bbp-remote-node-generation node)
        :heartbeat (bbp-remote-node-heartbeat node)))

(defun bbp-remote-node-program-actor-count (node)
  (hash-table-count (bbp-remote-node-program-actors node)))

(defun domain-key-actor-name (domain key)
  (format nil "~A-key-~{~2,'0X~^-~}"
          domain
          (map 'list #'char-code key)))

(defun bbp-remote-node-send-result (node command result sender)
  (remoting-tell
   (bbp-remote-node-remoting-port node)
   (bbp-remote-node-main-ref node)
   (list :kind :star-domain-result
         :node-id (bbp-remote-node-node-id node)
         :domain "bbp"
         :message-id (getf command :message-id)
         :result (copy-tree result))
   sender))

(defun bbp-program-actor-receive (node program-id actor-cell)
  (lambda (message)
    (ensure-plist message "BBP program actor message" 'domain-remoting-error)
    (unless (eq (getf message :kind) :star-domain-command)
      (fail 'domain-remoting-error
            "BBP program actor received unsupported message kind ~S."
            (getf message :kind)))
    (let* ((command (getf message :command))
           (command-program-id (bbp-command-program-id command)))
      (unless (string= command-program-id program-id)
        (fail 'domain-remoting-error
              "BBP program actor ~A rejected command for ~A."
              program-id command-program-id))
      (let ((result
              (bbp-invoke-command
               (bbp-remote-node-engine node)
               command)))
        (bbp-remote-node-send-result node command result (car actor-cell))
        :result-sent))))

(defun ensure-bbp-program-actor (node program-id)
  (or (gethash program-id (bbp-remote-node-program-actors node))
      (let* ((actor-cell (list nil))
             (actor
               (remoting-actor-of
                (bbp-remote-node-remoting-port node)
                (bbp-remote-node-system node)
                (domain-key-actor-name "bbp-program" program-id)
                (bbp-program-actor-receive node program-id actor-cell)
                :queue-size 128
                :dispatcher (bbp-remote-node-program-dispatcher node))))
        (setf (car actor-cell) actor)
        (setf (gethash program-id
                       (bbp-remote-node-program-actors node))
              actor)
        actor)))

(defun route-bbp-domain-command (node message)
  (unless (string= (getf message :domain) "bbp")
    (fail 'domain-remoting-error
          "BBP remote node rejected domain ~S."
          (getf message :domain)))
  (let* ((command (getf message :command))
         (program-id (bbp-command-program-id command))
         (program-actor (ensure-bbp-program-actor node program-id)))
    (remoting-tell
     (bbp-remote-node-remoting-port node)
     program-actor
     message
     (bbp-remote-node-actor node))
    :routed))

(defun bbp-remote-node-receive (node)
  (lambda (message)
    (ensure-plist message "BBP remote node message" 'domain-remoting-error)
    (case (getf message :kind)
      (:star-domain-command
       (route-bbp-domain-command node message))
      (:star-domain-registered
       (unless (string= (getf message :node-id)
                        (bbp-remote-node-node-id node))
         (fail 'domain-remoting-error
               "Registration acknowledgement targets node ~S."
               (getf message :node-id)))
       (setf (bbp-remote-node-registered-p node) t)
       :registered)
      (otherwise
       (fail 'domain-remoting-error
             "BBP remote node received unsupported message kind ~S."
             (getf message :kind))))))

(defun start-bbp-remote-node
    (&key node-id endpoint system remoting-port engine main-uri tools
          (dispatcher :shared))
  (required-nonempty-string node-id "BBP remote node-id")
  (required-nonempty-string endpoint "BBP remote endpoint")
  (required-nonempty-string main-uri "main gserver URI")
  (unless (domain-server-engine-p engine)
    (fail 'domain-remoting-error
          "BBP remote node requires a domain engine."))
  (let ((node
          (%make-bbp-remote-node
           :node-id node-id
           :endpoint endpoint
           :system system
           :remoting-port remoting-port
           :engine engine
           :program-dispatcher dispatcher)))
    (setf (bbp-remote-node-actor node)
          (remoting-actor-of
           remoting-port system "bbp-domain"
           (bbp-remote-node-receive node)
           :queue-size 1024
           :dispatcher dispatcher))
    (setf (bbp-remote-node-main-ref node)
          (remoting-make-remote-ref
           remoting-port system main-uri
           :max-queue-size 1024))
    (setf (bbp-remote-node-started-p node) t)
    (remoting-tell
     remoting-port
     (bbp-remote-node-main-ref node)
     (bbp-remote-node-registration node tools)
     (bbp-remote-node-actor node))
    node))

(defun send-bbp-remote-node-heartbeat (node)
  (unless (bbp-remote-node-started-p node)
    (fail 'domain-remoting-error
          "BBP remote node is not started."))
  (incf (bbp-remote-node-heartbeat node))
  (remoting-tell
   (bbp-remote-node-remoting-port node)
   (bbp-remote-node-main-ref node)
   (list :kind :star-domain-heartbeat
         :node-id (bbp-remote-node-node-id node)
         :domain "bbp"
         :generation (bbp-remote-node-generation node)
         :heartbeat (bbp-remote-node-heartbeat node))
   (bbp-remote-node-actor node))
  (bbp-remote-node-heartbeat node))

(defun stop-bbp-remote-node (node)
  (when (bbp-remote-node-started-p node)
    (maphash
     (lambda (program-id actor)
       (declare (ignore program-id))
       (remoting-stop
        (bbp-remote-node-remoting-port node)
        (bbp-remote-node-system node)
        actor))
     (bbp-remote-node-program-actors node))
    (clrhash (bbp-remote-node-program-actors node))
    (remoting-stop
     (bbp-remote-node-remoting-port node)
     (bbp-remote-node-system node)
     (bbp-remote-node-actor node))
    (setf (bbp-remote-node-started-p node) nil))
  :stopped)
