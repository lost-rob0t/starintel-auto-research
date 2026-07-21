(in-package #:star-lang.core)

(export '(make-sento-actor-adapter
          sento-actor-adapter
          sento-actor-system))

(defclass sento-actor-adapter (star-lang-actor-adapter)
  ((system :initarg :system :reader sento-actor-system)
   (actors :initform (make-hash-table :test #'equal)
           :reader sento-actors)))

(defun make-sento-actor-adapter (&key system config)
  (make-instance
   'sento-actor-adapter
   :system (or system (asys:make-actor-system config))))

(defun sento-dispatcher-designator (value)
  (etypecase value
    (keyword value)
    (string (intern (string-upcase value) :keyword))
    (symbol value)))

(defmethod actor-adapter-start ((adapter sento-actor-adapter) spec runtime)
  (let* ((logical-name (actor-spec-name spec))
         (parent-name (actor-spec-parent spec))
         (context
           (if parent-name
               (or (gethash parent-name (sento-actors adapter))
                   (fail 'execution-error :parent-actor-not-started nil
                         "Parent actor ~A is not started." parent-name))
               (sento-actor-system adapter)))
         (arguments
           (list :name (actor-spec-external-name spec)
                 :receive
                 (lambda (message)
                   (invoke-supervised-actor-handler runtime spec message))
                 :state (actor-spec-state spec)
                 :dispatcher
                 (sento-dispatcher-designator
                  (actor-spec-dispatcher spec)))))
    (when (gethash logical-name (sento-actors adapter))
      (fail 'execution-error :actor-already-started nil
            "Actor ~A is already started." logical-name))
    (when (actor-spec-queue-size spec)
      (setf arguments
            (append arguments
                    (list :queue-size (actor-spec-queue-size spec)))))
    (let ((actor (apply #'ac:actor-of context arguments)))
      (setf (gethash logical-name (sento-actors adapter)) actor)
      actor)))

(defmethod actor-adapter-ref ((adapter sento-actor-adapter) actor-name runtime)
  (declare (ignore runtime))
  (or (gethash actor-name (sento-actors adapter))
      (fail 'execution-error :actor-not-started nil
            "Actor ~A is not started." actor-name)))

(defmethod actor-adapter-send ((adapter sento-actor-adapter)
                               actor-reference message runtime)
  (declare (ignore adapter runtime))
  (act:tell actor-reference message))

(defmethod actor-adapter-stop ((adapter sento-actor-adapter) actor-name runtime)
  (declare (ignore runtime))
  (let ((actor (or (gethash actor-name (sento-actors adapter))
                   (fail 'execution-error :actor-not-started nil
                         "Actor ~A is not started." actor-name))))
    (ac:stop (sento-actor-system adapter) actor :wait t)
    (remhash actor-name (sento-actors adapter))
    t))

(defmethod actor-adapter-shutdown ((adapter sento-actor-adapter) runtime)
  (declare (ignore runtime))
  (ac:shutdown (sento-actor-system adapter) :wait t)
  (clrhash (sento-actors adapter))
  t)
