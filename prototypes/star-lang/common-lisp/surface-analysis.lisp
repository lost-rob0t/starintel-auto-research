(in-package #:star-lang.core)

(export '(*script-compilation-policy*
          explain-script-plan
          lint-script-plan
          script-diagnostic
          script-diagnostic-code
          script-diagnostic-message
          script-diagnostic-node-id
          script-diagnostic-severity
          script-diagnostic-span
          script-plan-manifest
          script-plan-manifest-actor-count
          script-plan-manifest-dataset-attachment-count
          script-plan-manifest-effects
          script-plan-manifest-max-declared-queue-size
          script-plan-manifest-max-source-batch
          script-plan-manifest-source-count
          script-plan-to-dot
          validate-script-plan))

(defparameter *script-compilation-policy* :development)

(defstruct script-diagnostic
  severity
  code
  message
  node-id
  span)

(defstruct script-plan-manifest
  actor-count
  source-count
  dataset-attachment-count
  max-declared-queue-size
  max-source-batch
  effects)

(defun analysis-diagnostic (severity code node control &rest arguments)
  (make-script-diagnostic
   :severity severity
   :code code
   :message (apply #'format nil control arguments)
   :node-id (and node (surface-node-id node))
   :span (and node (surface-node-span node))))

(defun node-literal-value (node &optional default)
  (if (and node (eq (surface-node-operation node) :literal))
      (getf (surface-node-arguments node) :value)
      default))

(defun node-reference-name (node)
  (let ((value (node-literal-value node :not-literal)))
    (cond
      ((symbol-literal-p value) (symbol-literal-name value))
      ((stringp value) value)
      ((and node (eq (surface-node-operation node) :variable))
       (getf (surface-node-arguments node) :name)))))

(defun source-option-node (spec name)
  (cdr (assoc name (source-spec-options spec) :test #'string=)))

(defun positive-literal-integer (node)
  (let ((value (node-literal-value node :not-literal)))
    (and (integerp value) (> value 0) value)))

(defun collect-expression-actor-references (node)
  (let ((references '()))
    (labels ((walk (current)
               (when (surface-node-p current)
                 (when (eq (surface-node-operation current) :actor-ref)
                   (let ((name (node-reference-name
                                (first (surface-node-arguments current)))))
                     (when name (push name references))))
                 (let ((arguments (surface-node-arguments current)))
                   (cond
                     ((listp arguments)
                      (dolist (argument arguments)
                        (cond
                          ((surface-node-p argument) (walk argument))
                          ((consp argument)
                           (walk (car argument))
                           (walk (cdr argument)))))))))))
      (walk node))
    (nreverse references)))

(defun actor-parent-cycle-p (actors)
  (let ((visiting (make-hash-table :test #'equal))
        (visited (make-hash-table :test #'equal)))
    (labels ((visit (name)
               (cond
                 ((gethash name visiting) t)
                 ((gethash name visited) nil)
                 (t
                  (setf (gethash name visiting) t)
                  (let* ((spec (gethash name actors))
                         (parent (and spec (actor-spec-parent spec)))
                         (cycle (and parent (visit parent))))
                    (remhash name visiting)
                    (setf (gethash name visited) t)
                    cycle)))))
      (loop for name being the hash-keys of actors
            thereis (visit name)))))

(defun lint-script-plan (plan)
  (let ((actors (make-hash-table :test #'equal))
        (sources (make-hash-table :test #'equal))
        (started (make-hash-table :test #'equal))
        (diagnostics '()))
    (labels ((emit (severity code node control &rest arguments)
               (push (apply #'analysis-diagnostic
                            severity code node control arguments)
                     diagnostics))
             (defined-actor-p (name)
               (gethash name actors))
             (defined-source-p (name)
               (gethash name sources)))
      (dolist (node (script-plan-nodes plan))
        (let ((arguments (surface-node-arguments node)))
          (case (surface-node-operation node)
            (:define-actor
             (let* ((spec (getf arguments :spec))
                    (name (actor-spec-name spec))
                    (queue-node (actor-spec-queue-size spec)))
               (if (defined-actor-p name)
                   (emit :error :duplicate-actor-definition node
                         "Actor ~A is defined more than once." name)
                   (setf (gethash name actors) spec))
               (when queue-node
                 (unless (positive-literal-integer queue-node)
                   (emit :error :invalid-actor-queue-size node
                         "Actor ~A requires a positive literal queue size."
                         name)))))
            (:define-source
             (let* ((spec (getf arguments :spec))
                    (name (source-spec-name spec)))
               (if (defined-source-p name)
                   (emit :error :duplicate-source-definition node
                         "Source ~A is defined more than once." name)
                   (setf (gethash name sources) spec))
               (when (and (eq *script-compilation-policy* :production)
                          (source-option-node spec "password")
                          (stringp
                           (node-literal-value
                            (source-option-node spec "password") nil)))
                 (emit :error :literal-production-credential node
                       "Source ~A contains a literal password under production policy."
                       name))))
            (:start-actor
             (let ((name (getf arguments :name)))
               (unless (defined-actor-p name)
                 (emit :error :undefined-actor-definition node
                       "Actor ~A is started before it is defined." name))
               (when (gethash name started)
                 (emit :error :actor-started-twice node
                       "Actor ~A is started more than once." name))
               (let* ((spec (defined-actor-p name))
                      (parent (and spec (actor-spec-parent spec))))
                 (when (and parent (not (gethash parent started)))
                   (emit :error :parent-actor-not-started node
                         "Actor ~A requires parent ~A to start first."
                         name parent)))
               (setf (gethash name started) t)))
            (:stop-actor
             (let ((name (getf arguments :name)))
               (unless (gethash name started)
                 (emit :error :actor-stop-before-start node
                       "Actor ~A is stopped before it starts." name))
               (remhash name started)))
            (:load-documents
             (let* ((name (getf arguments :source))
                    (spec (defined-source-p name))
                    (limit-node
                      (cdr (assoc "limit" (getf arguments :options)
                                  :test #'string=))))
               (unless spec
                 (emit :error :undefined-source-definition node
                       "Source ~A is loaded before it is defined." name))
               (when (and spec (eq (source-spec-kind spec) :rabbitmq)
                          (not (positive-literal-integer limit-node)))
                 (emit :error :unbounded-rabbitmq-read node
                       "RabbitMQ source ~A requires a positive literal load limit."
                       name))))
            (otherwise nil))
          (dolist (reference (collect-expression-actor-references node))
            (unless (defined-actor-p reference)
              (emit :error :undefined-actor-reference node
                    "Actor reference ~A has no definition." reference)))))
      (when (actor-parent-cycle-p actors)
        (emit :error :actor-parent-cycle nil
              "Actor parent declarations contain a cycle.")))
    (nreverse diagnostics)))

(defun validate-script-plan (plan)
  (let ((diagnostics (lint-script-plan plan)))
    (let ((failure
            (find :error diagnostics
                  :key #'script-diagnostic-severity
                  :test #'eq)))
      (when failure
        (fail 'compile-error
              (script-diagnostic-code failure)
              (script-diagnostic-span failure)
              "~A" (script-diagnostic-message failure))))
    plan))

(defun script-plan-manifest (plan)
  (let ((actor-count 0)
        (source-count 0)
        (dataset-count 0)
        (max-queue 0)
        (max-batch 0))
    (dolist (node (script-plan-nodes plan))
      (let ((arguments (surface-node-arguments node)))
        (case (surface-node-operation node)
          (:define-actor
           (incf actor-count)
           (let* ((spec (getf arguments :spec))
                  (queue (positive-literal-integer
                          (actor-spec-queue-size spec))))
             (when queue (setf max-queue (max max-queue queue)))))
          (:define-source
           (incf source-count))
          (:attach-dataset
           (incf dataset-count))
          (:load-documents
           (let* ((limit-node
                    (cdr (assoc "limit" (getf arguments :options)
                                :test #'string=)))
                  (limit (positive-literal-integer limit-node)))
             (if limit
                 (setf max-batch (max max-batch limit))
                 (setf max-batch :unbounded)))))))
    (make-script-plan-manifest
     :actor-count actor-count
     :source-count source-count
     :dataset-attachment-count dataset-count
     :max-declared-queue-size max-queue
     :max-source-batch max-batch
     :effects (copy-list (script-plan-effects plan)))))

(defun explain-script-plan (plan)
  (with-output-to-string (stream)
    (format stream "Star-Lang plan ~A~%" (script-plan-hash plan))
    (format stream "Source: ~A~%" (script-plan-source-name plan))
    (format stream "Effects: ~{~A~^, ~}~%" (script-plan-effects plan))
    (dolist (node (script-plan-nodes plan))
      (format stream "~A  ~A~%"
              (surface-node-id node)
              (surface-node-operation node)))))

(defun script-plan-to-dot (plan)
  (with-output-to-string (stream)
    (format stream "digraph star_lang {~%  rankdir=LR;~%")
    (loop for node in (script-plan-nodes plan)
          for previous = nil then node
          do
             (format stream "  \"~A\" [label=\"~A\"];~%"
                     (surface-node-id node)
                     (string-downcase
                      (symbol-name (surface-node-operation node))))
             (when previous
               (format stream "  \"~A\" -> \"~A\";~%"
                       (surface-node-id previous)
                       (surface-node-id node))))
    (format stream "}~%")))

(defparameter *compile-program-before-static-analysis*
  (symbol-function 'compile-program))

(defun compile-program (source &key (source-name "<program>"))
  (validate-script-plan
   (funcall *compile-program-before-static-analysis*
            source :source-name source-name)))
