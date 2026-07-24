(load (merge-pathnames "document-runtime.lisp" *load-truename*))

(in-package #:star-lang.document-runtime)

(defun assert-true (value label)
  (unless value
    (fail-runtime 'document-runtime-error "Assertion failed: ~A." label)))

(defun assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail-runtime 'document-runtime-error
                  "~A expected ~S, received ~S."
                  label expected actual)))

(defun condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun valid-ulid-p (value)
  (and (stringp value)
       (= (length value) 26)
       (every (lambda (character)
                (find character +crockford-base32+))
              value)))

(defun valid-uuidv4-p (value)
  (and (stringp value)
       (= (length value) 36)
       (every (lambda (index) (char= (char value index) #\-))
              '(8 13 18 23))
       (char= (char value 14) #\4)
       (find (char value 19) "89ab")
       (every (lambda (character)
                (or (digit-char-p character)
                    (find character "abcdef-")))
              value)))

(defun declaration-count (graph kind)
  (loop for node in (star-lang.loader:loaded-graph-libraries graph)
        sum (count kind
                   (getf (star-lang.loader:library-node-compiled node)
                         :declarations)
                   :key (lambda (declaration) (getf declaration :kind))
                   :test #'eq)))

(defun test-id-api ()
  (let ((ulid-a (make-ulid :timestamp-ms 1700000000000))
        (ulid-b (make-ulid :timestamp-ms 1700000000000))
        (uuid (make-uuidv4)))
    (assert-true (valid-ulid-p ulid-a) "ULID syntax")
    (assert-true (valid-ulid-p ulid-b) "second ULID syntax")
    (assert-true (not (string= ulid-a ulid-b)) "ULID random component")
    (assert-true (valid-uuidv4-p uuid) "UUIDv4 syntax")
    (assert-equal "5deaee1c1332199e5b5bc7c5e4f7f0c2"
                  (make-digest-id :md5 "hello")
                  "canonical MD5")
    (assert-equal
     "5aa762ae383fbb727af3c7a36d4940a5b8c40a989452d2304fc958ff3f354e7a"
     (make-digest-id :sha256 "hello")
     "canonical SHA-256")
    (assert-true (valid-ulid-p (generate-id :ulid)) "generic ULID API")
    (assert-true (valid-uuidv4-p (generate-id :uuidv4))
                 "generic UUIDv4 API")
    (assert-equal (make-digest-id :md5 '(('b . 2) ('a . 1)))
                  (make-digest-id :md5 '(("a" . 1) ("b" . 2)))
                  "canonical map digest ordering")))

(defun test-contracts-and-construction (graph)
  (assert-true (>= (declaration-count graph :document) 25)
               "ported Star-CL document count")
  (let* ((person-contract (compile-document-contract graph "person"))
         (org-contract (compile-document-contract graph "org"))
         (event-contract (compile-document-contract graph "runtime-event"))
         (artifact-contract (compile-document-contract graph "artifact")))
    (assert-equal :ULID
                  (id-policy-kind
                   (document-contract-id-policy person-contract))
                  "person ULID policy")
    (assert-equal :MD5
                  (id-policy-algorithm
                   (document-contract-id-policy org-contract))
                  "legacy organization MD5 policy")
    (assert-equal :UUIDV4
                  (id-policy-kind
                   (document-contract-id-policy event-contract))
                  "runtime event UUIDv4 policy")
    (assert-equal :SHA256
                  (id-policy-algorithm
                   (document-contract-id-policy artifact-contract))
                  "artifact SHA-256 policy"))
  (let* ((person
           (create-document
            graph "person"
            '(("fname" . "Ada")
              ("lname" . "Lovelace"))
            :dataset "people"))
         (org-values
           '(("name" . "Analytical Engines Ltd")
             ("reg" . "AE-1843")
             ("country" . "GB")))
         (org-a (create-document graph "org" org-values :dataset "orgs"))
         (org-b (create-document graph "org" (reverse org-values)
                                 :dataset "orgs"))
         (event
           (create-document
            graph "runtime-event"
            `(("event-type" . "created")
              ("occurred-at" . ,(unix-now)))
            :dataset "runtime"))
         (artifact
           (create-document
            graph "artifact"
            '(("name" . "scan.json")
              ("content-hash" . "sha256:abc")
              ("source-url" . "https://example.test/scan.json"))
            :dataset "artifacts")))
    (assert-true (valid-ulid-p (document-value person "id"))
                 "created person ULID")
    (assert-equal (document-value org-a "id")
                  (document-value org-b "id")
                  "stable legacy organization ID")
    (assert-true (= (length (document-value org-a "id")) 32)
                 "organization MD5 length")
    (assert-true (valid-uuidv4-p (document-value event "id"))
                 "created runtime event UUIDv4")
    (assert-true (= (length (document-value artifact "id")) 64)
                 "artifact SHA-256 length")
    (assert-equal "people" (document-value person "dataset")
                  "dataset metadata")
    (assert-equal "org.starintel/star-cl@1/person"
                  (document-value person "dtype")
                  "qualified dtype metadata")
    (assert-equal "1.0.0" (document-value person "schema-version")
                  "schema version metadata")
    (assert-true (integerp (document-value person "created-at"))
                 "created timestamp")
    (assert-true (integerp (document-value person "updated-at"))
                 "updated timestamp")
    (values person org-a)))

(defun test-encoding-and-relations (graph person org)
  (let* ((encoded (encode-document person :key-style :camel :couchdb t))
         (decoded (decode-document graph "person" encoded))
         (relation
           (relate-documents graph person org
                             :predicate "member-of"
                             :note "Compatibility relation")))
    (assert-equal (document-value person "id")
                  (cdr (assoc "_id" encoded :test #'string=))
                  "CouchDB ID encoding")
    (assert-true (assoc "createdAt" encoded :test #'string=)
                 "camel-case metadata key")
    (assert-equal (document-value person "id")
                  (document-value decoded "id")
                  "decode preserves ID")
    (assert-equal "Ada" (document-value decoded "fname")
                  "decode preserves fields")
    (assert-equal (document-value person "id")
                  (document-value relation "source")
                  "relation source")
    (assert-equal (document-value org "id")
                  (document-value relation "target")
                  "relation target")
    (assert-equal "member-of" (document-value relation "predicate")
                  "relation predicate")))

(defun test-validation (graph)
  (assert-true
   (condition-signaled-p
    'invalid-document-error
    (lambda ()
      (create-document graph "host" '(("hostname" . "missing-ip"))
                       :dataset "hosts")))
   "required field rejection")
  (assert-true
   (condition-signaled-p
    'invalid-document-error
    (lambda ()
      (create-document graph "person" '(("unknown-field" . 1))
                       :dataset "people")))
   "unknown field rejection")
  (assert-true
   (condition-signaled-p
    'invalid-document-error
    (lambda ()
      (create-document graph "port" '(("port" . "443"))
                       :dataset "ports")))
   "typed field rejection"))

(defun run-tests (&optional fixture-path)
  (let* ((fixture
           (or fixture-path
               (merge-pathnames "../fixtures/star-cl.star" *load-truename*)))
         (graph
           (star-lang.loader:load-star-file
            fixture
            :cache-directory
            (merge-pathnames
             (format nil "star-lang-document-runtime-tests-~36R/"
                     (random most-positive-fixnum))
             (uiop:temporary-directory)))))
    (test-id-api)
    (multiple-value-bind (person org)
        (test-contracts-and-construction graph)
      (test-encoding-and-relations graph person org))
    (test-validation graph)
    (format t "Star-Lang document runtime and ID API tests passed.~%")
    t))

(unless (run-tests)
  (error "Star-Lang document runtime tests failed."))
