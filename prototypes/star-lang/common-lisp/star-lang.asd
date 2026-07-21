(asdf:defsystem "star-lang"
  :description "Common Lisp compiler and deterministic durable runtime for Star-Lang."
  :version "0.4.0"
  :author "StarIntel"
  :license "UNLICENSED"
  :serial t
  :components
  ((:file "prototype")
   (:file "core")
   (:file "canonical")
   (:file "durable")
   (:file "surface-syntax")
   (:file "surface-runtime")
   (:file "surface-fixes")
   (:file "source-support"))
  :in-order-to
  ((asdf:test-op (asdf:test-op "star-lang/tests"))))

(asdf:defsystem "star-lang/tests"
  :description "Star-Lang compiler, durable runtime, surface, and adapter contract tests."
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
   (:file "durable-tests"))
  :perform
  (asdf:test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :star-lang.core.tests :run-advanced-tests)))

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
