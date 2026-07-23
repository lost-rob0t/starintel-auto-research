(in-package #:star-lang.core-surface.prototype)

(export '(register-domain-remoting-runtime-port
          remoting-runtime-port))

(defvar *domain-remoting-runtime-port-readers*
  (make-hash-table :test #'eq))

(defun register-domain-remoting-runtime-port (port reader)
  (unless (domain-remoting-port-p port)
    (fail 'domain-remoting-error
          "Runtime port registration requires a domain remoting port."))
  (unless (functionp reader)
    (fail 'domain-remoting-error
          "Runtime port reader must be a function."))
  (setf (gethash port *domain-remoting-runtime-port-readers*) reader)
  port)

(defun remoting-runtime-port (port system)
  (unless (domain-remoting-port-p port)
    (fail 'domain-remoting-error
          "Runtime port lookup requires a domain remoting port."))
  (let ((reader
          (gethash port *domain-remoting-runtime-port-readers*)))
    (unless reader
      (fail 'domain-remoting-error
            "Domain remoting port does not expose its bound runtime port."))
    (let ((value (funcall reader system)))
      (unless (and (integerp value) (<= 1 value 65535))
        (fail 'domain-remoting-error
              "Bound runtime port must be an integer from 1 through 65535."))
      value)))
