#lang racket/base

(require racket/base
         "../embedded/runtime.rkt"
         (for-syntax racket/base))

(provide
 (except-out (all-from-out racket/base) #%module-begin)
 (all-from-out "../embedded/runtime.rkt")
 (rename-out [star-module-begin #%module-begin]))

(define-syntax (star-module-begin stx)
  (syntax-case stx ()
    [(_ form ...)
     #'(#%plain-module-begin
        (define star-lang-language-version 1)
        form ...)]))
