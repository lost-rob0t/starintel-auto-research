(load (merge-pathnames "bbp-remoting-runtime-example.lisp" *load-truename*))
(load (merge-pathnames "bbp-journal-restart-common.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun journal-restart-worker-runner (calls)
  (make-tool-runner-port
   :run
   (lambda (tool argv request)
     (declare (ignore request))
     (incf (car calls))
     (journal-restart-write-marker
      "bbp-journal-runner.started"
      (format nil "~D" (car calls)))
     (journal-restart-wait-until
      (lambda ()
        (probe-file "bbp-journal-allow-complete"))
      "journal restart completion release")
     (list :exit-code 0
           :stdout
           (format nil "call ~D: ~A completed for ~A"
                   (car calls)
                   (getf tool :name)
                   (car (last argv)))
           :stderr ""))))

(let* ((config
         (make-domain-remoting-config
          :bind-host "127.0.0.1"
          :advertised-host "127.0.0.1"
          :port 0))
       (main-uri
         (journal-restart-read-marker
          "bbp-journal-main-1.ready"))
       (calls (list 0))
       (runtime nil)
       (reconnected-p nil))
  (unwind-protect
       (progn
         (setf runtime
               (start-bbp-tool-domain-server
                :main-uri main-uri
                :node-id "bbp-journal-restart-worker"
                :config config
                :tool-runner
                (journal-restart-worker-runner calls)))
         (journal-restart-write-marker
          "bbp-journal-worker.ready"
          (bbp-worker-runtime-uri runtime))
         (loop until (probe-file "bbp-journal-worker.stop")
               do
                  (when (and (not reconnected-p)
                             (probe-file "bbp-journal-main-2.ready"))
                    (reconnect-bbp-remote-node
                     (bbp-worker-runtime-node runtime)
                     (journal-restart-read-marker
                      "bbp-journal-main-2.ready"))
                    (setf reconnected-p t)
                    (journal-restart-write-marker
                     "bbp-journal-worker.reconnected"
                     "reconnected"))
                  (handler-case
                      (send-bbp-remote-node-heartbeat
                       (bbp-worker-runtime-node runtime))
                    (domain-remoting-error () nil))
                  (sleep 0.1))
         (unless (= 1 (car calls))
           (error "Recovered BBP tool ran ~D times."
                  (car calls)))
         (unless (= 1
                    (bbp-program-run-count
                     (bbp-worker-runtime-engine runtime)
                     "program:journal-restart"))
           (error "Recovered BBP program stored an unexpected run count."))
         (journal-restart-write-marker
          "bbp-journal-worker.success"
          "ok")
         (format t
                 "BBP worker preserved state across main-gserver restart.~%"))
    (when runtime
      (stop-bbp-tool-domain-server runtime))))
