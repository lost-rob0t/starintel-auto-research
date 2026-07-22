(load (merge-pathnames "compiler-ir-prototype.lisp" *load-truename*))

(unless (star-lang.compiler-ir.prototype:run-tests)
  (error "Star-Lang normalized IR tests failed."))
