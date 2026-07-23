(in-package #:star-lang.core-surface.prototype)

(export '(reconnect-bbp-remote-node))

(defun bbp-domain-engine-tool-list (engine)
  (unless (domain-server-engine-p engine)
    (fail 'domain-remoting-error
          "BBP reconnect requires a domain server engine."))
  (let ((tools '()))
    (maphash
     (lambda (name tool)
       (declare (ignore name))
       (push tool tools))
     (domain-server-engine-tools engine))
    (sort tools #'string<
          :key (lambda (tool) (getf tool :name)))))

(defun reconnect-bbp-remote-node (node main-uri)
  (unless (bbp-remote-node-p node)
    (fail 'domain-remoting-error
          "BBP reconnect requires a remote node."))
  (unless (bbp-remote-node-started-p node)
    (fail 'domain-remoting-error
          "BBP remote node must be started before reconnect."))
  (required-nonempty-string main-uri "BBP reconnect main URI")
  (setf (bbp-remote-node-main-ref node)
        (remoting-make-remote-ref
         (bbp-remote-node-remoting-port node)
         (bbp-remote-node-system node)
         main-uri
         :max-queue-size 1024))
  (incf (bbp-remote-node-generation node))
  (setf (bbp-remote-node-registered-p node) nil)
  (remoting-tell
   (bbp-remote-node-remoting-port node)
   (bbp-remote-node-main-ref node)
   (bbp-remote-node-registration
    node
    (bbp-domain-engine-tool-list
     (bbp-remote-node-engine node)))
   (bbp-remote-node-actor node))
  node)
