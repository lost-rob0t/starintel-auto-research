(asdf:defsystem "star-lang"
  :description "Common Lisp compiler, verifier, supervised actors, tooling, and durable Star-Lang execution."
  :version "0.9.0"
  :author "StarIntel"
  :license "UNLICENSED"
  :serial t
  :components
  ((:file "prototype")
   (:file "core")
   (:file "canonical")
   (:file "durable")
   (:file "durable-advanced")
   (:file "durable-advanced-fixes")
   (:file "file-journal")
   (:file "surface-syntax")
   (:file "surface-runtime")
   (:file "surface-fixes")
   (:file "source-support")
   (:file "surface-analysis")
   (:file "actor-protocols")
   (:file "actor-protocol-fixes")
   (:file "cli"))
  :in-order-to
  ((asdf:test-op (asdf:test-op "star-lang/tests"))))

(asdf:defsystem "star-lang/tests"
  :description "Star-Lang compiler, actor, verifier, tooling, recovery, journal, surface, and adapter tests."
  :depends-on ("star-lang")
  :serial t
  :components
  ((:file "core-tests")
   (:file "surface-tests")
   (:file "adapter-stubs")
   (:file "sento-adapter")
   (:file "couch-adapter")
   (:file "rabbit-adapter")
   (:file "adapter-contract-tests")
   (:file "durable-tests")
   (:file "durable-advanced-tests")
   (:file "durable-advanced-test-fixes")
   (:file "surface-analysis-tests")
   (:file "cli-tests")
   (:file "actor-protocol-tests")
   (:file "file-journal-tests"))
  :perform
  (asdf:test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :star-lang.core.tests :run-persistence-tests)))

(asdf:defsystem "star-lang/cli"
  :description "Build the Star-Lang command-line compiler and verifier."
  :depends-on ("star-lang")
  :build-operation "program-op"
  :build-pathname "star-lang"
  :entry-point "star-lang.cli:main")

(asdf:defsystem "star-lang/sento"
  :description "Star-Lang actor adapter for the cl-gserver Sento runtime."
  :depends-on ("star-lang" "sento")
  :serial t
  :components
  ((:file "sento-adapter")))

(asdf:defsystem "star-lang/cl-couch"
  :description "Star-Lang CouchDB document source adapter using Cl-Couch."
  :depends-on ("star-lang" "cl-couchdb-client")
  :serial t
  :components
  ((:file "couch-adapter")))

(asdf:defsystem "star-lang/cl-rabbit"
  :description "Star-Lang RabbitMQ document source adapter using cl-rabbit."
  :depends-on ("star-lang" "cl-rabbit")
  :serial t
  :components
  ((:file "rabbit-adapter")))

(asdf:defsystem "star-lang/all-adapters"
  :description "Load all production Star-Lang adapters."
  :depends-on ("star-lang/sento"
               "star-lang/cl-couch"
               "star-lang/cl-rabbit"))
