(in-package #:star-lang.core)

(defun canonical-node-value (value)
  (cond
    ((plan-node-p value)
     (canonical-node-value (plan-node-canonical value)))
    ((consp value)
     (format nil "(~{~A~^ ~})" (mapcar #'canonical-node-value value)))
    (t
     (canonical-value value))))

(defun stable-node-id (analysis-name index operation arguments)
  (subseq
   (sha256-string
    (format nil "(~A ~D ~A ~A)"
            analysis-name
            index
            operation
            (canonical-node-value arguments)))
   0 24))
