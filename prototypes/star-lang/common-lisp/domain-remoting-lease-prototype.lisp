(in-package #:star-lang.core-surface.prototype)

(export '(configure-main-domain-gateway-lease
          expire-main-domain-gateway-nodes
          main-domain-gateway-live-node-count))

(defstruct (main-domain-lease-state
            (:constructor %make-main-domain-lease-state))
  clock-fn
  timeout-ms
  (last-seen (make-hash-table :test #'equal)))

(defvar *main-domain-gateway-leases* (make-hash-table :test #'eq))

(defun domain-monotonic-milliseconds ()
  (floor (* 1000
            (/ (get-internal-real-time)
               internal-time-units-per-second))))

(defun configure-main-domain-gateway-lease
    (gateway &key (timeout-ms 15000) clock)
  (unless (main-domain-gateway-p gateway)
    (fail 'domain-remoting-error
          "Heartbeat lease configuration requires a main domain gateway."))
  (unless (and (integerp timeout-ms) (> timeout-ms 0))
    (fail 'domain-remoting-error
          "Heartbeat lease timeout must be a positive integer."))
  (when clock
    (unless (functionp clock)
      (fail 'domain-remoting-error
            "Heartbeat lease clock must be a function.")))
  (setf (gethash gateway *main-domain-gateway-leases*)
        (%make-main-domain-lease-state
         :clock-fn (or clock #'domain-monotonic-milliseconds)
         :timeout-ms timeout-ms))
  gateway)

(defun main-domain-gateway-lease-state (gateway)
  (or (gethash gateway *main-domain-gateway-leases*)
      (progn
        (configure-main-domain-gateway-lease gateway)
        (gethash gateway *main-domain-gateway-leases*))))

(defun main-domain-lease-now (gateway)
  (funcall
   (main-domain-lease-state-clock-fn
    (main-domain-gateway-lease-state gateway))))

(defun note-main-domain-node-seen (gateway node-id)
  (setf (gethash node-id
                 (main-domain-lease-state-last-seen
                  (main-domain-gateway-lease-state gateway)))
        (main-domain-lease-now gateway))
  node-id)

(defun expire-main-domain-gateway-nodes (gateway)
  (let* ((lease (main-domain-gateway-lease-state gateway))
         (now (main-domain-lease-now gateway))
         (timeout (main-domain-lease-state-timeout-ms lease))
         (expired '()))
    (maphash
     (lambda (node-id node)
       (let ((last-seen
               (gethash node-id
                        (main-domain-lease-state-last-seen lease))))
         (when (and last-seen
                    (>= (- now last-seen) timeout)
                    (remote-domain-node-alive-p node))
           (setf (remote-domain-node-alive-p node) nil)
           (push node-id expired))))
     (main-domain-gateway-nodes gateway))
    (sort expired #'string<)))

(defun main-domain-gateway-live-node-count (gateway)
  (expire-main-domain-gateway-nodes gateway)
  (let ((count 0))
    (maphash
     (lambda (node-id node)
       (declare (ignore node-id))
       (when (remote-domain-node-alive-p node)
         (incf count)))
     (main-domain-gateway-nodes gateway))
    count))

(defvar *main-domain-register-node-without-lease*
  (symbol-function 'main-domain-register-node))

(defvar *main-domain-heartbeat-without-lease*
  (symbol-function 'main-domain-heartbeat))

(defvar *select-domain-node-without-lease*
  (symbol-function 'select-domain-node))

(defun main-domain-register-node (gateway message)
  (prog1
      (funcall *main-domain-register-node-without-lease* gateway message)
    (note-main-domain-node-seen gateway (getf message :node-id))))

(defun main-domain-heartbeat (gateway message)
  (prog1
      (funcall *main-domain-heartbeat-without-lease* gateway message)
    (note-main-domain-node-seen gateway (getf message :node-id))))

(defun select-domain-node (gateway command)
  (expire-main-domain-gateway-nodes gateway)
  (funcall *select-domain-node-without-lease* gateway command))
