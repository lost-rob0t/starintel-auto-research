(load (merge-pathnames "star-lang-api.lisp" *load-truename*))

(in-package #:cl-user)

(defun constructor-test-fail (control &rest arguments)
  (error (apply #'format nil control arguments)))

(defun assert-true (value label)
  (unless value
    (constructor-test-fail "Assertion failed: ~A." label)))

(defun assert-equal (expected actual label)
  (unless (equal expected actual)
    (constructor-test-fail "~A expected ~S, received ~S."
                           label expected actual)))

(defun condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun package-function (package-name function-name)
  (let* ((package (or (find-package package-name)
                      (constructor-test-fail "Missing package ~A." package-name)))
         (symbol (find-symbol (string-upcase function-name) package)))
    (unless (and symbol (fboundp symbol))
      (constructor-test-fail "Missing generated function ~A::~A."
                             package-name function-name))
    (symbol-function symbol)))

(defun run-constructor-tests (&optional fixture-path)
  (let* ((fixture
           (or fixture-path
               (merge-pathnames "../fixtures/star-cl-constructors.star"
                                *load-truename*)))
         (package-name "STARINTEL.COMPAT.TEST")
         (cache
           (merge-pathnames
            (format nil "star-lang-constructor-tests-~36R/"
                    (random most-positive-fixnum))
            (uiop:temporary-directory)))
         (graph
           (star-lang.api:load-star-runtime
            fixture
            :cache-directory cache
            :constructor-package package-name)))
    (assert-equal "org.starintel/star-cl-constructors@1"
                  (star-lang.loader:library-node-name
                   (star-lang.loader:loaded-graph-root graph))
                  "Lisp runtime loader root")
    (assert-true
     (eq graph
         (star-lang.constructor-runtime:package-constructor-graph package-name))
     "installed graph identity")

    (let* ((new-person (package-function package-name "new-person"))
           (person
             (funcall new-person
                      "people" "Ada" "Lovelace" "person"
                      :bio "Mathematician"))
           (new-org (package-function package-name "new-org"))
           (org
             (funcall new-org
                      "organizations" "Analytical Engines" "company"
                      :reg "AE-1843" :country "GB"))
           (new-domain (package-function package-name "new-domain"))
           (domain (funcall new-domain "domains"))
           (new-email* (package-function package-name "new-email*"))
           (email (funcall new-email* "emails" "ada@example.org"))
           (new-target (package-function package-name "new-target"))
           (target
             (funcall new-target "targets" "example.org" "dns-actor"
                      :delay 30 :recurring t))
           (new-target-without-options
             (package-function package-name "new-target-without-options"))
           (plain-target
             (funcall new-target-without-options
                      "targets" "example.net" "http-actor"))
           (new-relation (package-function package-name "new-relation"))
           (relation
             (funcall new-relation
                      "relations"
                      (star-lang.document-runtime:document-value person "id")
                      (star-lang.document-runtime:document-value org "id")
                      :predicate "member-of"
                      :note "Legacy constructor"))
           (new-breach (package-function package-name "new-breach"))
           (breach (funcall new-breach "breaches" :name "Example Breach")))
      (assert-equal "Ada"
                    (star-lang.document-runtime:document-value person "fname")
                    "new-person fname")
      (assert-equal "Lovelace"
                    (star-lang.document-runtime:document-value person "lname")
                    "new-person lname")
      (assert-equal "person"
                    (star-lang.document-runtime:document-value person "etype")
                    "new-person etype")
      (assert-equal "Mathematician"
                    (star-lang.document-runtime:document-value person "bio")
                    "new-person rest keywords")
      (assert-equal "Analytical Engines"
                    (star-lang.document-runtime:document-value org "name")
                    "new-org positional name")
      (assert-equal "company"
                    (star-lang.document-runtime:document-value org "etype")
                    "new-org positional etype")
      (assert-equal "domains"
                    (star-lang.document-runtime:document-value domain "dataset")
                    "sparse legacy constructor")
      (assert-equal "ada"
                    (star-lang.document-runtime:document-value email "user")
                    "new-email* local part")
      (assert-equal "example.org"
                    (star-lang.document-runtime:document-value email "domain")
                    "new-email* domain part")
      (assert-equal 30
                    (star-lang.document-runtime:document-value target "delay")
                    "new-target delay")
      (assert-equal t
                    (star-lang.document-runtime:document-value target "recurring")
                    "new-target recurring")
      (assert-equal 0
                    (star-lang.document-runtime:document-value plain-target "delay")
                    "new-target-without-options delay")
      (assert-equal nil
                    (star-lang.document-runtime:document-value
                     plain-target "options")
                    "new-target-without-options options")
      (assert-equal "member-of"
                    (star-lang.document-runtime:document-value
                     relation "predicate")
                    "new-relation predicate")
      (assert-equal "Legacy constructor"
                    (star-lang.document-runtime:document-value relation "note")
                    "new-relation note")
      (assert-equal "Example Breach"
                    (star-lang.document-runtime:document-value breach "name")
                    "generated default constructor")
      (assert-true
       (condition-signaled-p
        'star-lang.constructor-runtime:constructor-runtime-error
        (lambda ()
          (funcall new-relation
                   "relations" "source" "target"
                   :predicate "not-in-the-old-allowlist")))
       "legacy relation predicate validation"))

    (let ((source (with-output-to-string (stream)
                    (star-lang.api:generate-constructor-source
                     graph stream :package package-name))))
      (assert-true (search "NEW-PERSON" source :test #'char-equal)
                   "generated constructor source")
      (assert-true (search "NEW-EMAIL*" source :test #'char-equal)
                   "generated special constructor source"))

    (format t "Star-Lang generated constructor tests passed.~%")
    t))

(unless (run-constructor-tests)
  (error "Star-Lang generated constructor tests failed."))
