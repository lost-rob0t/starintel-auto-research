(asdf:defsystem "star-lang"
  :description "Common Lisp compiler and deterministic reference runtime for Star-Lang."
  :version "0.2.1"
  :author "StarIntel"
  :license "UNLICENSED"
  :serial t
  :components
  ((:file "prototype")
   (:file "core")
   (:file "canonical"))
  :in-order-to
  ((asdf:test-op (asdf:test-op "star-lang/tests"))))

(asdf:defsystem "star-lang/tests"
  :description "Star-Lang Common Lisp tests."
  :depends-on ("star-lang")
  :serial t
  :components
  ((:file "core-tests"))
  :perform
  (asdf:test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :star-lang.core.tests :run-tests)))
