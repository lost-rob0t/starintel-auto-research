(load (merge-pathnames "bbp-remoting-runtime-example.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun smoke-write-marker (pathname value)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-line value stream)))

(defun smoke-wait-until (predicate label &key (attempts 300) (sleep-seconds 0.05))
  (loop repeat attempts
        when (funcall predicate)
          return t
        do (sleep sleep-seconds)
        finally (error "Timed out waiting for ~A." label)))

(defun smoke-await-terminal (runtime label)
  (let ((envelopes '()))
    (smoke-wait-until
     (lambda ()
       (setf envelopes
             (append envelopes (drain-bbp-main-results runtime)))
       (some (lambda (envelope)
               (member (getf envelope :kind) '(:reply :error) :test #'eq))
             envelopes))
     label)
    envelopes))

(defun smoke-reply (envelopes)
  (or (find :reply envelopes :key (lambda (envelope) (getf envelope :kind)))
      (error "Expected reply envelope, received ~S." envelopes)))

(let* ((config
         (make-domain-remoting-config
          :bind-host "127.0.0.1"
          :advertised-host "127.0.0.1"
          :port 0))
       (runtime nil))
  (unwind-protect
       (progn
         (setf runtime (start-bbp-main-gserver :config config))
         (smoke-write-marker "bbp-sento-main.ready" (bbp-main-runtime-uri runtime))
         (smoke-wait-until
          (lambda ()
            (= 1
               (main-domain-gateway-node-count
                (bbp-main-runtime-gateway runtime))))
          "BBP worker registration")
         (unless (eq :deferred
                     (submit-bbp-main-command
                      runtime
                      (make-bbp-register-program-command
                       :message-id "sento-smoke-register"
                       :program-id "program:sento-smoke"
                       :name "Sento Smoke"
                       :scope '("example.com"))))
           (error "BBP register command did not defer to the remote worker."))
         (smoke-reply
          (smoke-await-terminal runtime "remote program registration"))
         (unless (eq :deferred
                     (submit-bbp-main-command
                      runtime
                      (make-bbp-run-tool-command
                       :message-id "sento-smoke-tool"
                       :program-id "program:sento-smoke"
                       :run-id "run:sento-smoke:1"
                       :tool 'subfinder
                       :target "api.example.com")))
           (error "BBP tool command did not defer to the remote worker."))
         (let* ((reply
                  (smoke-reply
                   (smoke-await-terminal runtime "remote tool completion")))
                (payload (getf reply :payload))
                (stdout (cdr (assoc "stdout" payload :test #'string=))))
           (unless (string= stdout
                            "subfinder completed for api.example.com")
             (error "Unexpected remote tool output ~S." stdout)))
         (smoke-write-marker "bbp-sento-smoke.success" "ok")
         (format t "Two-process Sento BBP smoke test passed.~%"))
    (smoke-write-marker "bbp-sento-worker.stop" "stop")
    (when runtime
      (stop-bbp-main-gserver runtime))))
