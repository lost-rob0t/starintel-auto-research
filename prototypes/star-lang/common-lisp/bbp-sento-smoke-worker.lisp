(load (merge-pathnames "bbp-remoting-runtime-example.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun smoke-worker-runner ()
  (make-tool-runner-port
   :run
   (lambda (tool argv request)
     (declare (ignore request))
     (list :exit-code 0
           :stdout
           (format nil "~A completed for ~A"
                   (getf tool :name)
                   (car (last argv)))
           :stderr ""))))

(defun smoke-worker-write-marker (pathname value)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-line value stream)))

(let* ((config
         (make-domain-remoting-config
          :bind-host "127.0.0.1"
          :advertised-host "127.0.0.1"
          :port 4912))
       (runtime nil))
  (unwind-protect
       (progn
         (setf runtime
               (start-bbp-tool-domain-server
                :main-uri "sento://127.0.0.1:4911/user/star-domain-ingress"
                :node-id "bbp-sento-smoke-worker"
                :config config
                :tool-runner (smoke-worker-runner)))
         (smoke-worker-write-marker
          "bbp-sento-worker.ready"
          (bbp-worker-runtime-uri runtime))
         (loop until (probe-file "bbp-sento-worker.stop")
               do (send-bbp-remote-node-heartbeat
                   (bbp-worker-runtime-node runtime))
                  (sleep 0.25))
         (format t "Two-process Sento BBP worker stopped cleanly.~%"))
    (when runtime
      (stop-bbp-tool-domain-server runtime))))
