(load (merge-pathnames "bbp-remoting-runtime-example.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun smoke-worker-runner (calls)
  (make-tool-runner-port
   :run
   (lambda (tool argv request)
     (declare (ignore request))
     (incf (car calls))
     (list :exit-code 0
           :stdout
           (format nil "call ~D: ~A completed for ~A"
                   (car calls)
                   (getf tool :name)
                   (car (last argv)))
           :stderr ""))))

(defun smoke-worker-write-marker (pathname value)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-line value stream)))

(defun smoke-worker-read-marker (pathname)
  (with-open-file (stream pathname :direction :input)
    (or (read-line stream nil nil)
        (error "Marker ~A is empty." pathname))))

(let* ((config
         (make-domain-remoting-config
          :bind-host "127.0.0.1"
          :advertised-host "127.0.0.1"
          :port 0))
       (main-uri (smoke-worker-read-marker "bbp-sento-main.ready"))
       (calls (list 0))
       (runtime nil))
  (unwind-protect
       (progn
         (setf runtime
               (start-bbp-tool-domain-server
                :main-uri main-uri
                :node-id "bbp-sento-smoke-worker"
                :config config
                :tool-runner (smoke-worker-runner calls)))
         (smoke-worker-write-marker
          "bbp-sento-worker.ready"
          (bbp-worker-runtime-uri runtime))
         (loop until (probe-file "bbp-sento-worker.stop")
               do (send-bbp-remote-node-heartbeat
                   (bbp-worker-runtime-node runtime))
                  (sleep 0.25))
         (unless (= 1 (car calls))
           (error "Remote replay invoked the tool ~D times." (car calls)))
         (format t "Two-process Sento BBP worker stopped cleanly.~%"))
    (when runtime
      (stop-bbp-tool-domain-server runtime))))
