(in-package #:star-lang.core-surface.prototype)

(export '(make-runtime-directory-port
          runtime-directory-snapshot))

(define-condition runtime-directory-error (star-lang-core-error) ())

(defstruct (runtime-directory-port
            (:constructor %make-runtime-directory-port))
  snapshot-fn)

(defun make-runtime-directory-port (&key snapshot)
  (unless (functionp snapshot)
    (fail 'runtime-directory-error
          "Runtime directory snapshot operation must be a function."))
  (%make-runtime-directory-port :snapshot-fn snapshot))

(defun valid-runtime-alive-value-p (value)
  (or (eq value t)
      (null value)
      (eq value :unknown)))

(defun validate-runtime-directory-entry (entry)
  (ensure-plist entry "runtime directory entry" 'runtime-directory-error)
  (required-nonempty-string
   (getf entry :name)
   "runtime directory actor name")
  (unless (keywordp (getf entry :runtime))
    (fail 'runtime-directory-error
          "Runtime directory actor ~A requires a keyword runtime."
          (getf entry :name)))
  (unless (valid-runtime-alive-value-p (getf entry :alive))
    (fail 'runtime-directory-error
          "Runtime directory actor ~A has invalid alive value ~S."
          (getf entry :name)
          (getf entry :alive)))
  (copy-tree entry))

(defun runtime-directory-snapshot (port context)
  (unless (runtime-directory-port-p port)
    (fail 'runtime-directory-error
          "Runtime directory snapshot requires a directory port."))
  (handler-case
      (let ((entries
              (funcall (runtime-directory-port-snapshot-fn port)
                       context)))
        (unless (listp entries)
          (fail 'runtime-directory-error
                "Runtime directory snapshot must return a list."))
        (mapcar #'validate-runtime-directory-entry entries))
    (runtime-directory-error (condition)
      (error condition))
    (error (condition)
      (fail 'runtime-directory-error
            "Runtime directory snapshot failed: ~A"
            condition))))