(in-package #:star-lang.core)

(defun source-option-value (spec name runtime &optional default)
  (evaluate-option-node (source-spec-options spec) name runtime default))

(defun source-decoder (spec runtime)
  (let ((designator (source-option-value spec "decoder" runtime nil)))
    (when designator
      (runtime-handler runtime (normalize-reference-key designator)))))

(defun map-reference (value key)
  (let ((normalized (normalize-reference-key key)))
    (cond
      ((core-document-p value)
       (document-field value normalized))
      ((hash-table-p value)
       (multiple-value-bind (result present-p) (gethash normalized value)
         (unless present-p
           (multiple-value-setq (result present-p)
             (gethash (intern (string-upcase normalized) :keyword) value)))
         (unless present-p
           (fail 'execution-error :missing-document-path nil
                 "Map has no key ~A." normalized))
         result))
      ((listp value)
       (let ((entry
               (or (assoc normalized value :test #'equal)
                   (assoc (intern (string-upcase normalized) :keyword)
                          value :test #'eq)
                   (assoc (intern (string-upcase normalized) *package*)
                          value :test #'eq))))
         (unless entry
           (fail 'execution-error :missing-document-path nil
                 "Association list has no key ~A." normalized))
         (if (and (listp entry) (= (length entry) 2))
             (second entry)
             (cdr entry))))
      (t
       (fail 'execution-error :invalid-document-path nil
             "Cannot read key ~A from ~S." normalized value)))))
