(in-package #:star-lang.core-surface.prototype)

(export '(domain-remoting-actor-uri
          domain-remoting-base-uri
          domain-remoting-config
          domain-remoting-config-options
          domain-remoting-config-p
          domain-remoting-config-resolved-p
          make-domain-remoting-config
          materialize-domain-actor
          require-domain-remoting-config
          resolve-domain-remoting-config))

(defstruct (domain-remoting-config
            (:constructor %make-domain-remoting-config))
  bind-host
  advertised-host
  port
  tls-config
  serializer
  max-message-length)

(defun valid-domain-remoting-port-p (port &key allow-zero)
  (and (integerp port)
       (if allow-zero
           (<= 0 port 65535)
           (<= 1 port 65535))))

(defun make-domain-remoting-config
    (&key
       (bind-host "0.0.0.0")
       (advertised-host "127.0.0.1")
       port
       tls-config
       serializer
       (max-message-length (* 2 1024 1024)))
  (required-nonempty-string bind-host "domain remoting bind host")
  (required-nonempty-string advertised-host
                            "domain remoting advertised host")
  (unless (valid-domain-remoting-port-p port :allow-zero t)
    (fail 'domain-remoting-error
          "Domain remoting port must be an integer from 0 through 65535."))
  (unless (and (integerp max-message-length)
               (> max-message-length 0))
    (fail 'domain-remoting-error
          "Domain remoting max message length must be a positive integer."))
  (%make-domain-remoting-config
   :bind-host bind-host
   :advertised-host advertised-host
   :port port
   :tls-config tls-config
   :serializer serializer
   :max-message-length max-message-length))

(defun require-domain-remoting-config (config)
  (unless (domain-remoting-config-p config)
    (fail 'domain-remoting-error
          "Runtime requires a validated domain remoting configuration."))
  config)

(defun domain-remoting-config-resolved-p (config)
  (and (domain-remoting-config-p config)
       (valid-domain-remoting-port-p
        (domain-remoting-config-port config))))

(defun resolve-domain-remoting-config (config port)
  (require-domain-remoting-config config)
  (unless (valid-domain-remoting-port-p port)
    (fail 'domain-remoting-error
          "Resolved domain remoting port must be an integer from 1 through 65535."))
  (%make-domain-remoting-config
   :bind-host (domain-remoting-config-bind-host config)
   :advertised-host (domain-remoting-config-advertised-host config)
   :port port
   :tls-config (domain-remoting-config-tls-config config)
   :serializer (domain-remoting-config-serializer config)
   :max-message-length
   (domain-remoting-config-max-message-length config)))

(defun domain-remoting-config-options (config)
  (require-domain-remoting-config config)
  (append
   (list :host (domain-remoting-config-bind-host config)
         :port (domain-remoting-config-port config)
         :hostname (domain-remoting-config-advertised-host config))
   (when (domain-remoting-config-tls-config config)
     (list :tls-config (domain-remoting-config-tls-config config)))
   (when (domain-remoting-config-serializer config)
     (list :serializer (domain-remoting-config-serializer config)))
   (list :max-message-length
         (domain-remoting-config-max-message-length config))))

(defun domain-remoting-base-uri (config)
  (require-domain-remoting-config config)
  (unless (domain-remoting-config-resolved-p config)
    (fail 'domain-remoting-error
          "Domain remoting URI requires a resolved nonzero port."))
  (format nil "sento://~A:~A"
          (domain-remoting-config-advertised-host config)
          (domain-remoting-config-port config)))

(defun domain-remoting-actor-uri (config actor-name)
  (required-nonempty-string actor-name "remote actor name")
  (format nil "~A/user/~A"
          (domain-remoting-base-uri config)
          actor-name))

(defun dynamic-domain-endpoint-actor-name (endpoint)
  (let ((prefix "sento://dynamic/user/"))
    (when (and (stringp endpoint)
               (<= (length prefix) (length endpoint))
               (string= prefix endpoint :end2 (length prefix)))
      (subseq endpoint (length prefix)))))

(defun materialize-domain-actor (actor config)
  (unless (and (listp actor)
               (eq (getf actor :kind) :actor)
               (eq (getf actor :runtime) :external))
    (fail 'domain-remoting-error
          "Endpoint materialization requires a compiled external actor."))
  (let* ((endpoint (getf actor :endpoint))
         (actor-name (dynamic-domain-endpoint-actor-name endpoint))
         (materialized (copy-tree actor)))
    (when actor-name
      (required-nonempty-string actor-name "dynamic remote actor name")
      (setf (getf materialized :endpoint)
            (domain-remoting-actor-uri config actor-name)))
    materialized))
