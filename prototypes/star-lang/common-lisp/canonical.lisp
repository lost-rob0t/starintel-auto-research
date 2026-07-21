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

(defun schema-field-definition (schema field-name)
  (find (normalize-name field-name)
        (schema-definition-fields schema)
        :test #'equal
        :key (lambda (field) (normalize-name (first field)))))

(defun make-core-document (registry schema-name fields &key (provenance '()))
  (let* ((schema (require-schema registry schema-name nil))
         (normalized-fields
           (sort (copy-list fields) #'string<
                 :key (lambda (entry) (normalize-name (first entry))))))
    (dolist (field (schema-definition-fields schema))
      (destructuring-bind (field-name field-type required-p) field
        (declare (ignore field-type))
        (when (and required-p
                   (null (assoc field-name normalized-fields :test #'equal)))
          (fail 'schema-error :missing-field nil
                "Schema ~A requires field ~A."
                (schema-definition-name schema) field-name))))
    (dolist (entry normalized-fields)
      (let ((definition (schema-field-definition schema (first entry))))
        (unless definition
          (fail 'schema-error :unknown-field nil
                "Schema ~A does not define field ~A."
                (schema-definition-name schema) (first entry)))
        (unless (value-type-valid-p (second definition) (second entry))
          (fail 'schema-error :invalid-field-type nil
                "Field ~A on schema ~A does not satisfy type ~S."
                (first entry) (schema-definition-name schema) (second definition)))))
    (let* ((content-hash
             (sha256-string
              (format nil "(~A ~D ~A ~A)"
                      (schema-definition-name schema)
                      (schema-definition-version schema)
                      (canonical-value (schema-definition-persistence schema))
                      (canonical-value normalized-fields))))
           (identifier (subseq content-hash 0 24)))
      (%make-core-document
       :id identifier
       :schema-name (schema-definition-name schema)
       :schema-version (schema-definition-version schema)
       :persistence (schema-definition-persistence schema)
       :fields normalized-fields
       :content-hash content-hash
       :provenance provenance))))
