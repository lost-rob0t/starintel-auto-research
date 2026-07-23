(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "core-semantics-prototype.lisp" *load-truename*))
(load (merge-pathnames "canonical-json-prototype.lisp" *load-truename*))
(load (merge-pathnames "message-lifecycle-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-remoting-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-remoting-runtime-port-prototype.lisp" *load-truename*))
(load (merge-pathnames "domain-remoting-config-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun runtime-port-test-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S."
          label expected actual)))

(defun runtime-port-test-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun runtime-port-test-remoting-port ()
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

(defun test-runtime-bound-port-resolution ()
  (let* ((port (runtime-port-test-remoting-port))
         (config
           (make-domain-remoting-config
            :advertised-host "dynamic.internal"
            :port 0)))
    (register-domain-remoting-runtime-port
     port
     (lambda (system)
       (declare (ignore system))
       4920))
    (runtime-port-test-assert-equal
     4920
     (remoting-runtime-port port :runtime-test)
     "runtime reports bound port")
    (runtime-port-test-assert-equal
     0
     (getf (domain-remoting-config-options config) :port)
     "unresolved configuration requests automatic binding")
    (let ((signaled nil))
      (handler-case
          (domain-remoting-base-uri config)
        (domain-remoting-error ()
          (setf signaled t)))
      (runtime-port-test-assert-true
       signaled
       "unresolved configuration cannot advertise port zero"))
    (let ((resolved
            (resolve-domain-remoting-config
             config
             (remoting-runtime-port port :runtime-test))))
      (runtime-port-test-assert-true
       (domain-remoting-config-resolved-p resolved)
       "resolved configuration is advertiseable")
      (runtime-port-test-assert-equal
       "sento://dynamic.internal:4920/user/bbp-domain"
       (domain-remoting-actor-uri resolved "bbp-domain")
       "resolved configuration advertises actual bound port"))))

(defun test-runtime-bound-port-validation ()
  (let ((port (runtime-port-test-remoting-port))
        (signaled nil))
    (register-domain-remoting-runtime-port
     port
     (lambda (system)
       (declare (ignore system))
       0))
    (handler-case
        (remoting-runtime-port port :runtime-test)
      (domain-remoting-error ()
        (setf signaled t)))
    (runtime-port-test-assert-true
     signaled
     "runtime port reader rejects unresolved port zero")))

(test-runtime-bound-port-resolution)
(test-runtime-bound-port-validation)
(format t "Star-Lang runtime bound-port tests passed.~%")
