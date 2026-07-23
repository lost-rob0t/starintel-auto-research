(load (merge-pathnames "bbp-remoting-runtime-example.lisp" *load-truename*))
(load (merge-pathnames "bbp-journal-restart-common.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(let* ((config
         (make-domain-remoting-config
          :bind-host "127.0.0.1"
          :advertised-host "127.0.0.1"
          :port 0))
       (journal
         (make-file-runtime-journal-port
          +bbp-journal-restart-path+))
       (runtime nil))
  (unwind-protect
       (progn
         (setf runtime
               (start-bbp-main-gserver
                :config config
                :journal-port journal))
         (unless (= 1
                    (main-domain-gateway-pending-count
                     (bbp-main-runtime-gateway runtime)))
           (error "Phase two did not restore one pending command."))
         (journal-restart-write-marker
          "bbp-journal-main-2.ready"
          (bbp-main-runtime-uri runtime))
         (journal-restart-wait-until
          (lambda ()
            (= 1
               (main-domain-gateway-node-count
                (bbp-main-runtime-gateway runtime))))
          "phase-two worker reconnect")
         (journal-restart-wait-until
          (lambda ()
            (probe-file "bbp-journal-worker.reconnected"))
          "worker reconnect marker")
         (journal-restart-write-marker
          "bbp-journal-allow-complete"
          "complete")
         (let* ((terminal
                  (journal-restart-await-terminal
                   runtime
                   "recovered remote completion"))
                (reply
                  (journal-restart-envelope terminal :reply))
                (stdout
                  (cdr (assoc "stdout"
                              (getf reply :payload)
                              :test #'string=))))
           (unless (string=
                    stdout
                    "call 1: subfinder completed for api.example.com")
             (error "Unexpected recovered tool output ~S."
                    stdout))
           (sleep 0.5)
           (unless (equal
                    '(:pending :remote-result
                      :pending :remote-result)
                    (mapcar
                     (lambda (event) (getf event :kind))
                     (runtime-journal-replay journal)))
             (error "Unexpected restart journal transitions ~S."
                    (runtime-journal-replay journal)))
           (submit-dispatch-envelope
            (bbp-main-runtime-dispatcher runtime)
            (journal-restart-tool-command))
           (unless (eq :duplicate
                       (run-dispatcher-next
                        (bbp-main-runtime-dispatcher runtime)))
             (error "Recovered terminal command did not replay as duplicate."))
           (unless (equal
                    terminal
                    (drain-bbp-main-results runtime))
             (error "Recovered terminal outcomes were not deterministic.")))
         (journal-restart-write-marker
          "bbp-journal-worker.stop"
          "stop")
         (journal-restart-wait-until
          (lambda ()
            (probe-file "bbp-journal-worker.success"))
          "worker success marker")
         (journal-restart-write-marker
          "bbp-journal-restart.success"
          "ok")
         (format t
                 "Live BBP main-gserver journal restart test passed.~%"))
    (journal-restart-write-marker
     "bbp-journal-worker.stop"
     "stop")
    (when runtime
      (stop-bbp-main-gserver runtime))))
