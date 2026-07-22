(in-package #:star-lang.core-surface.prototype)

(export '(generate-python-bindings generate-typescript-bindings))

(defun qualified-local-name (qualified-name)
  (let ((position (position #\/ qualified-name :from-end t)))
    (if position
        (subseq qualified-name (1+ position))
        qualified-name)))

(defun identifier-words (value)
  (let ((words '())
        (current (make-string-output-stream)))
    (labels ((finish-word ()
               (let ((word (get-output-stream-string current)))
                 (unless (string= word "")
                   (push word words)))
               (setf current (make-string-output-stream))))
      (loop for character across value
            do (if (alphanumericp character)
                   (write-char character current)
                   (finish-word)))
      (finish-word))
    (nreverse words)))

(defun pascal-name (value)
  (with-output-to-string (stream)
    (dolist (word (identifier-words (qualified-local-name value)))
      (when (> (length word) 0)
        (write-char (char-upcase (char word 0)) stream)
        (loop for character across (subseq word 1)
              do (write-char (char-downcase character) stream))))))

(defun source-string (value)
  (canonical-json-string value))

(defun document-contract-fields (manifest contract)
  (let ((parent-name (getf contract :extends)))
    (append
     (when parent-name
       (let ((parent (manifest-type-contract manifest parent-name)))
         (unless (and parent (eq (getf parent :kind) :document))
           (fail 'invalid-type-error
                 "Generated binding cannot resolve document parent ~A."
                 parent-name))
         (document-contract-fields manifest parent)))
     (copy-tree (getf contract :fields)))))

(defun python-type-expression (type)
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2))
     (format nil "list[~A]" (python-type-expression (second type))))
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (format nil "~A | None" (python-type-expression (second type))))
    ((not (stringp type))
     (fail 'invalid-type-error "Cannot generate Python type for ~S." type))
    ((string= type "any") "Any")
    ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
             :test #'string=)
     "str")
    ((string= type "integer") "int")
    ((string= type "boolean") "bool")
    ((string= type "map") "dict[str, Any]")
    ((string= type "reference") "StarReference")
    (t (pascal-name type))))

(defun typescript-type-expression (type)
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2))
     (format nil "Array<~A>" (typescript-type-expression (second type))))
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (format nil "~A | null" (typescript-type-expression (second type))))
    ((not (stringp type))
     (fail 'invalid-type-error "Cannot generate TypeScript type for ~S." type))
    ((string= type "any") "unknown")
    ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
             :test #'string=)
     "string")
    ((string= type "integer") "number")
    ((string= type "boolean") "boolean")
    ((string= type "map") "Record<string, unknown>")
    ((string= type "reference") "StarReference")
    (t (pascal-name type))))

(defun write-python-typed-dict (stream name fields)
  (format stream "~A = TypedDict(~A, {~%"
          name (source-string name))
  (dolist (field fields)
    (format stream "    ~A: ~A[~A],~%"
            (source-string (getf field :name))
            (if (getf field :required) "Required" "NotRequired")
            (python-type-expression (getf field :type))))
  (format stream "})~%~%"))

(defun write-python-string-list (stream values)
  (write-char #\[ stream)
  (loop for value in values
        for first-p = t then nil
        do (unless first-p (write-string ", " stream))
           (write-string (source-string value) stream))
  (write-char #\] stream))

(defun write-python-actor-contracts (stream actors)
  (format stream "ACTOR_CONTRACTS: dict[str, dict[str, object]] = {~%")
  (dolist (actor actors)
    (format stream "    ~A: {~%" (source-string (getf actor :name)))
    (format stream "        \"runtime\": ~A,~%"
            (source-string (identifier-string (getf actor :runtime))))
    (when (getf actor :protocol)
      (format stream "        \"protocol\": ~A,~%"
              (source-string (getf actor :protocol))))
    (when (getf actor :endpoint)
      (format stream "        \"endpoint\": ~A,~%"
              (source-string (getf actor :endpoint))))
    (write-string "        \"accepts\": " stream)
    (write-python-string-list stream (getf actor :accepts))
    (format stream ",~%        \"produces\": ")
    (write-python-string-list stream (getf actor :produces))
    (format stream ",~%    },~%"))
  (format stream "}~%"))

(defun generate-python-bindings (manifest)
  (with-output-to-string (stream)
    (format stream "from __future__ import annotations~%~%")
    (format stream "from typing import Any, Literal, NotRequired, Required, TypedDict~%~%")
    (format stream "class StarReference(TypedDict):~%    schema: str~%    id: str~%~%")
    (dolist (contract (getf manifest :types))
      (case (getf contract :kind)
        (:scalar
         (format stream "~A = ~A~%~%"
                 (pascal-name (getf contract :name))
                 (python-type-expression (getf contract :base))))
        (:enum
         (format stream "~A = Literal[~{~A~^, ~}]~%~%"
                 (pascal-name (getf contract :name))
                 (mapcar #'source-string (getf contract :values))))
        (:document
         (write-python-typed-dict
          stream
          (pascal-name (getf contract :name))
          (document-contract-fields manifest contract)))))
    (dolist (message (getf manifest :messages))
      (write-python-typed-dict
       stream
       (pascal-name (getf message :name))
       (getf message :fields)))
    (write-python-actor-contracts stream (getf manifest :actors))))

(defun write-typescript-interface (stream name fields &optional extends)
  (format stream "export interface ~A~@[ extends ~A~] {~%" name extends)
  (dolist (field fields)
    (format stream "  ~A~:[?~;~]: ~A;~%"
            (source-string (getf field :name))
            (getf field :required)
            (typescript-type-expression (getf field :type))))
  (format stream "}~%~%"))

(defun write-typescript-string-array (stream values)
  (write-char #\[ stream)
  (loop for value in values
        for first-p = t then nil
        do (unless first-p (write-string ", " stream))
           (write-string (source-string value) stream))
  (write-char #\] stream))

(defun write-typescript-actor-contracts (stream actors)
  (format stream "export const actorContracts = {~%")
  (dolist (actor actors)
    (format stream "  ~A: {~%" (source-string (getf actor :name)))
    (format stream "    runtime: ~A,~%"
            (source-string (identifier-string (getf actor :runtime))))
    (when (getf actor :protocol)
      (format stream "    protocol: ~A,~%" (source-string (getf actor :protocol))))
    (when (getf actor :endpoint)
      (format stream "    endpoint: ~A,~%" (source-string (getf actor :endpoint))))
    (write-string "    accepts: " stream)
    (write-typescript-string-array stream (getf actor :accepts))
    (format stream ",~%    produces: ")
    (write-typescript-string-array stream (getf actor :produces))
    (format stream ",~%  },~%"))
  (format stream "} as const;~%"))

(defun generate-typescript-bindings (manifest)
  (with-output-to-string (stream)
    (format stream "export interface StarReference {~%  schema: string;~%  id: string;~%}~%~%")
    (dolist (contract (getf manifest :types))
      (case (getf contract :kind)
        (:scalar
         (format stream "export type ~A = ~A;~%~%"
                 (pascal-name (getf contract :name))
                 (typescript-type-expression (getf contract :base))))
        (:enum
         (format stream "export type ~A = ~{~A~^ | ~};~%~%"
                 (pascal-name (getf contract :name))
                 (mapcar #'source-string (getf contract :values))))
        (:document
         (write-typescript-interface
          stream
          (pascal-name (getf contract :name))
          (getf contract :fields)
          (and (getf contract :extends)
               (pascal-name (getf contract :extends)))))))
    (dolist (message (getf manifest :messages))
      (write-typescript-interface
       stream
       (pascal-name (getf message :name))
       (getf message :fields)))
    (write-typescript-actor-contracts stream (getf manifest :actors))))
