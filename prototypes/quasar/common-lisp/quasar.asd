(asdf:defsystem "quasar/core"
  :description "Renderer-independent graph core for the Quasar prototype."
  :author "lost-rob0t"
  :license "MIT"
  :version "0.0.1"
  :serial t
  :components ((:file "packages")
               (:file "core/graph-model")
               (:file "core/cytoscape-json"))
  :in-order-to ((test-op (test-op "quasar/tests"))))

(asdf:defsystem "quasar/ui-clog"
  :description "CLOG and Cytoscape prototype user interface for Quasar."
  :author "lost-rob0t"
  :license "MIT"
  :version "0.0.1"
  :depends-on ("quasar/core" "clog")
  :serial t
  :components ((:file "ui/clog-application")))

(asdf:defsystem "quasar/tests"
  :description "Dependency-light tests for the Quasar prototype core."
  :author "lost-rob0t"
  :license "MIT"
  :version "0.0.1"
  :depends-on ("quasar/core")
  :serial t
  :components ((:file "tests/core-tests"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :quasar.tests :run-core-tests)))
