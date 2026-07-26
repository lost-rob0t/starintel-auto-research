#lang starintel

(provide run-star-example
         star-program)

(define-star-program star-program
  (lambda (fixture)
    (build-example-runtime fixture)))

(define (run-star-example fixture-path)
  (run-example fixture-path))
