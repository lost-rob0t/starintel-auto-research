(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "core-semantics-prototype.lisp" *load-truename*))
(load (merge-pathnames "canonical-json-prototype.lisp" *load-truename*))
(load (merge-pathnames "binding-generator-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun wire-condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun wire-assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun wire-assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S." label expected actual)))

(defun write-text-file (pathname content)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string content stream)))

(defun build-fec-wire-fixture (fixture)
  (let* ((library (compile-core-library (load-star-form fixture)))
         (native
           (compile-actor
            '(actor amendment-resolver
              (:runtime native
               :accepts (resolve-amendments)
               :produces (filing)
               :handler resolve-amendments-handler
               :restart transient
               :mailbox (bounded 256)))
            library))
         (external
           (compile-actor
            '(actor fec-importer
              (:runtime external
               :protocol star-message-v1
               :endpoint "rabbitmq:star.fec.ingest"
               :accepts (ingest-page)
               :produces (candidate committee filing)
               :restart permanent
               :mailbox (bounded 1024)))
            library)))
    (values library (emit-core-manifest library (list native external)))))

(defun test-canonical-manifest-json (manifest)
  (let ((first (canonical-manifest-json manifest))
        (second (canonical-manifest-json manifest)))
    (wire-assert-equal first second "canonical manifest is deterministic")
    (wire-assert-true (search "\"wire_version\":1" first)
                      "manifest carries wire version")
    (wire-assert-true (search "\"org.starintel/fec@1/candidate-id\"" first)
                      "manifest carries qualified type names")
    first))

(defun test-canonical-envelope-json (manifest)
  (let* ((envelope
           (make-wire-envelope
            :message-type "org.starintel/fec@1/ingest-page"
            :message-id "01JTEST"
            :actor "fec-importer"
            :dataset "fec-2026"
            :payload '(("endpoint" . "/candidates/search/")
                       ("page" . 1)
                       ("results" . ())
                       ("retrieved-at" . "2026-07-22T20:00:00Z"))))
         (json (canonical-envelope-json manifest envelope))
         (expected
           "{\"actor\":\"fec-importer\",\"dataset\":\"fec-2026\",\"message_id\":\"01JTEST\",\"message_type\":\"org.starintel/fec@1/ingest-page\",\"payload\":{\"endpoint\":\"/candidates/search/\",\"page\":1,\"results\":[],\"retrieved-at\":\"2026-07-22T20:00:00Z\"},\"star_version\":1}"))
    (wire-assert-equal expected json "canonical envelope ordering and types")
    json))

(defun test-wire-type-validation (manifest)
  (wire-assert-true
   (validate-wire-value manifest "org.starintel/fec@1/fec-money" "12.34")
   "decimal strings preserve precision")
  (wire-assert-true
   (wire-condition-signaled-p
    'invalid-envelope-error
    (lambda ()
      (validate-wire-value manifest "org.starintel/fec@1/fec-money" 12)))
   "numeric decimal wire value rejected")
  (wire-assert-true
   (wire-condition-signaled-p
    'invalid-envelope-error
    (lambda ()
      (validate-wire-value manifest "org.starintel/fec@1/fec-money" "12.345")))
   "decimal values exceeding declared scale rejected")
  (wire-assert-true
   (wire-condition-signaled-p
    'invalid-envelope-error
    (lambda ()
      (validate-wire-value manifest "org.starintel/fec@1/fec-money" ".50")))
   "canonical decimal requires a leading digit")
  (wire-assert-true
   (wire-condition-signaled-p
    'invalid-envelope-error
    (lambda ()
      (validate-wire-value manifest "org.starintel/fec@1/file-number" 0)))
   "scalar minimum enforced")
  (wire-assert-true
   (wire-condition-signaled-p
    'invalid-envelope-error
    (lambda ()
      (validate-wire-value manifest "org.starintel/fec@1/office" "governor")))
   "invalid enum wire value rejected"))

(defun test-reference-validation (manifest)
  (wire-assert-true
   (validate-wire-value
    manifest "reference"
    '(("schema" . "org.starintel/fec@1/candidate")
      ("id" . "H2OH03116")))
   "reference requires schema and id")
  (wire-assert-true
   (wire-condition-signaled-p
    'invalid-envelope-error
    (lambda ()
      (validate-wire-value
       manifest "reference"
       '(("schema" . "org.starintel/fec@1/candidate")))))
   "incomplete reference rejected"))

(defun test-inherited-document-validation (manifest)
  (let ((candidate
          '(("name" . "Example Candidate")
            ("raw" . ())
            ("candidate-id" . "H2OH03116")
            ("office" . "house")
            ("election-years" . (2026)))))
    (wire-assert-true
     (validate-wire-value manifest "org.starintel/fec@1/candidate" candidate)
     "document validation includes inherited fields")
    (wire-assert-true
     (wire-condition-signaled-p
      'invalid-envelope-error
      (lambda ()
        (validate-wire-value
         manifest "org.starintel/fec@1/candidate"
         '(("raw" . ())
           ("candidate-id" . "H2OH03116")
           ("office" . "house")
           ("election-years" . (2026))))))
     "missing inherited required field rejected")))

(defun test-python-bindings (manifest)
  (let ((source (generate-python-bindings manifest)))
    (wire-assert-true (search "CandidateId = str" source)
                      "Python scalar alias generated")
    (wire-assert-true (search "FecMoney = str" source)
                      "Python decimal maps to precision-safe string")
    (wire-assert-true (search "\"candidate-id\": Required[CandidateId]" source)
                      "Python preserves source field names")
    (wire-assert-true (search "\"name\": Required[str]" source)
                      "Python candidate binding includes inherited fields")
    (wire-assert-true (search "ACTOR_CONTRACTS" source)
                      "Python actor contracts generated")
    source))

(defun test-typescript-bindings (manifest)
  (let ((source (generate-typescript-bindings manifest)))
    (wire-assert-true (search "export type CandidateId = string;" source)
                      "TypeScript scalar alias generated")
    (wire-assert-true (search "export type FecMoney = string;" source)
                      "TypeScript decimal maps to precision-safe string")
    (wire-assert-true (search "export interface Candidate extends Entity" source)
                      "TypeScript document inheritance generated")
    (wire-assert-true (search "\"candidate-id\": CandidateId;" source)
                      "TypeScript preserves source field names")
    (wire-assert-true (search "export const actorContracts" source)
                      "TypeScript actor contracts generated")
    source))

(defun run-canonical-json-binding-tests ()
  (let ((fixture (merge-pathnames "../fixtures/fec-core.star" *load-truename*)))
    (multiple-value-bind (library manifest)
        (build-fec-wire-fixture fixture)
      (declare (ignore library))
      (let ((manifest-json (test-canonical-manifest-json manifest))
            (envelope-json (test-canonical-envelope-json manifest))
            (python-source (test-python-bindings manifest))
            (typescript-source (test-typescript-bindings manifest)))
        (test-wire-type-validation manifest)
        (test-reference-validation manifest)
        (test-inherited-document-validation manifest)
        (write-text-file "star-lang-fec-manifest.json" manifest-json)
        (write-text-file "star-lang-fec-envelope.json" envelope-json)
        (write-text-file "star_lang_fec.py" python-source)
        (write-text-file "star_lang_fec.ts" typescript-source)))
    (format t "Star-Lang canonical JSON and binding generator tests passed.~%")
    t))

(unless (run-canonical-json-binding-tests)
  (error "Star-Lang canonical JSON and binding generator tests failed."))
