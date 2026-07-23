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

(defun smoke-envelope-of-kind (envelopes kind)
  (or (find kind envelopes :key (lambda (envelope) (getf envelope :kind)))
      (error "Expected ~S envelope, received ~S." kind envelopes)))

(defun smoke-submit-deferred (runtime command label)
  (unless (eq :deferred (submit-bbp-main-command runtime command))
    (error "~A did not defer to the remote worker." label))
  (smoke-await-terminal runtime label))

(defun smoke-reply-stdout (envelopes)
  (let* ((reply (smoke-envelope-of-kind envelopes :reply))
         (payload (getf reply :payload)))
    (or (cdr (assoc "stdout" payload :test #'string=))
        (error "Remote reply omitted stdout: ~S." reply))))

(defun smoke-assert-error-code (envelopes expected)
  (let ((error-envelope (smoke-envelope-of-kind envelopes :error)))
    (unless (string= (getf (getf error-envelope :payload) :code) expected)
      (error "Expected error code ~A, received ~S."
             expected error-envelope))
    error-envelope))

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
         (smoke-envelope-of-kind
          (smoke-submit-deferred
           runtime
           (make-bbp-register-program-command
            :message-id "sento-smoke-register"
            :program-id "program:sento-smoke"
            :name "Sento Smoke"
            :scope '("example.com"))
           "remote program registration")
          :reply)
         (let* ((first-command
                  (make-bbp-run-tool-command
                   :message-id "sento-smoke-tool"
                   :program-id "program:sento-smoke"
                   :run-id "run:sento-smoke:1"
                   :tool 'subfinder
                   :target "api.example.com"))
                (first-stdout
                  (smoke-reply-stdout
                   (smoke-submit-deferred
                    runtime first-command "remote tool completion"))))
           (unless (string= first-stdout
                            "call 1: subfinder completed for api.example.com")
             (error "Unexpected remote tool output ~S." first-stdout))
           (smoke-envelope-of-kind
            (smoke-submit-deferred
             runtime
             (make-bbp-register-program-command
              :message-id "sento-smoke-register-replay"
              :program-id "program:sento-smoke"
              :name "Sento Smoke"
              :scope '("example.com")
              :idempotency-key "bbp:recovery-register:sento-smoke")
             "remote registration replay")
            :reply)
           (let* ((replay-command
                    (make-bbp-run-tool-command
                     :message-id "sento-smoke-tool-replay"
                     :program-id "program:sento-smoke"
                     :run-id "run:sento-smoke:1"
                     :tool 'subfinder
                     :target "api.example.com"
                     :idempotency-key "bbp:recovery-replay:sento-smoke"))
                  (replay-stdout
                    (smoke-reply-stdout
                     (smoke-submit-deferred
                      runtime replay-command "remote run-id replay"))))
             (unless (string= first-stdout replay-stdout)
               (error "Remote recovery replay reran the tool: first ~S replay ~S."
                      first-stdout replay-stdout)))
           (smoke-assert-error-code
            (smoke-submit-deferred
             runtime
             (make-bbp-register-program-command
              :message-id "sento-smoke-register-conflict"
              :program-id "program:sento-smoke"
              :name "Sento Smoke"
              :scope '("other.example.com")
              :idempotency-key "bbp:recovery-register-conflict:sento-smoke")
             "remote registration conflict")
            "star.bbp.program-registration-conflict")
           (smoke-assert-error-code
            (smoke-submit-deferred
             runtime
             (make-bbp-run-tool-command
              :message-id "sento-smoke-tool-conflict"
              :program-id "program:sento-smoke"
              :run-id "run:sento-smoke:1"
              :tool 'httpx
              :target "api.example.com"
              :idempotency-key "bbp:recovery-conflict:sento-smoke")
             "remote run-id conflict")
            "star.bbp.run-id-conflict"))
         (smoke-write-marker "bbp-sento-smoke.success" "ok")
         (format t "Two-process Sento BBP recovery smoke test passed.~%"))
    (smoke-write-marker "bbp-sento-worker.stop" "stop")
    (when runtime
      (stop-bbp-main-gserver runtime))))
