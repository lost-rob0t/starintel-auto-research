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
         (journal-restart-write-marker
          "bbp-journal-main-1.ready"
          (bbp-main-runtime-uri runtime))
         (journal-restart-wait-until
          (lambda ()
            (= 1
               (main-domain-gateway-node-count
                (bbp-main-runtime-gateway runtime))))
          "phase-one worker registration")
         (journal-restart-envelope
          (journal-restart-submit-deferred
           runtime
           (journal-restart-register-command)
           "phase-one program registration")
          :reply)
         (unless (eq :deferred
                     (submit-bbp-main-command
                      runtime
                      (journal-restart-tool-command)))
           (error "Phase-one tool command did not defer."))
         (drain-bbp-main-results runtime)
         (journal-restart-wait-until
          (lambda ()
            (probe-file "bbp-journal-runner.started"))
          "worker tool execution")
         (journal-restart-write-marker
          "bbp-journal-phase-1.pending"
          "pending")
         (format t
                 "BBP journal phase one stopped with one pending tool command.~%"))
    (when runtime
      (stop-bbp-main-gserver runtime))))
