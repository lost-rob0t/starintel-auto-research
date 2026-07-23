(in-package #:star-lang.core-surface.prototype)

(export '(make-sento-remoting-domain-port))

(defun make-sento-remoting-domain-port ()
  (make-domain-remoting-port
   :enable
   (lambda (system options)
     (apply #'rem:enable-remoting system options))
   :actor-of
   (lambda (system name receive options)
     (apply #'ac:actor-of
            system
            :name name
            :receive receive
            options))
   :remote-ref
   (lambda (system uri options)
     (apply #'rem:make-remote-ref system uri options))
   :tell
   (lambda (actor message sender)
     (act:tell actor message sender))
   :stop
   (lambda (system actor)
     (ac:stop system actor))
   :disable
   (lambda (system)
     (rem:disable-remoting system))))
