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
(load (merge-pathnames "domain-remoting-config-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun config-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S."
          label expected actual)))

(defun test-remoting-config-values ()
  (let ((config
          (make-domain-remoting-config
           :advertised-host "worker.internal"
           :port 4912
           :serializer :json
           :max-message-length 4096)))
    (config-assert-equal
     '(:host "0.0.0.0" :port 4912 :hostname "worker.internal"
       :serializer :json :max-message-length 4096)
     (domain-remoting-config-options config)
     "Sento options")
    (config-assert-equal
     "sento://worker.internal:4912/user/bbp-domain"
     (domain-remoting-actor-uri config "bbp-domain")
     "actor URI")))

(defun test-bbp-endpoint-materialization ()
  (multiple-value-bind (library tools domain actor manifest)
      (compile-bbp-domain-program)
    (declare (ignore library tools domain manifest))
    (let* ((config
             (make-domain-remoting-config
              :advertised-host "worker.internal"
              :port 4912))
           (materialized (materialize-domain-actor actor config)))
      (config-assert-equal
       "sento://dynamic/user/bbp-domain"
       (getf actor :endpoint)
       "portable endpoint")
      (config-assert-equal
       "sento://worker.internal:4912/user/bbp-domain"
       (getf materialized :endpoint)
       "materialized endpoint"))))

(test-remoting-config-values)
(test-bbp-endpoint-materialization)
(format t "Star-Lang remoting config tests passed.~%")
