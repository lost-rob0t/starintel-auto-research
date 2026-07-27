#lang racket/base

(require racket/file racket/list racket/match racket/port racket/string)
(provide (all-defined-out))

(struct exn:fail:star exn:fail (kind) #:transparent)
(struct doc (type persistence fields) #:transparent)
(struct runtime (schemas actors tools agents pure flows persisted events) #:mutable #:transparent)

(define (star-fail kind fmt . args)
  (raise (exn:fail:star (apply format fmt args)
                        (current-continuation-marks)
                        kind)))

(define (make-runtime)
  (runtime (make-hasheq) (make-hasheq) (make-hasheq) (make-hasheq)
           (make-hasheq) (make-hasheq) '() '()))

(define (event! rt kind . payload)
  (set-runtime-events! rt (cons (cons kind payload) (runtime-events rt))))

(define (event-count rt kind)
  (count (lambda (event) (eq? (car event) kind)) (runtime-events rt)))

(define (table-ref table key kind)
  (hash-ref table key
            (lambda () (star-fail 'definition "unknown ~a ~a" kind key))))

(define (register-schema! rt name persistence fields)
  (hash-set! (runtime-schemas rt) name (list persistence fields)))

(define (register-pure! rt name proc)
  (hash-set! (runtime-pure rt) name proc))

(define (register-actor! rt name accepts produces proc)
  (hash-set! (runtime-actors rt) name (list accepts produces proc)))

(define (register-tool! rt name input output proc)
  (hash-set! (runtime-tools rt) name (list input output proc)))

(define (register-agent! rt name accepts produces tools proc)
  (for ([tool tools]) (table-ref (runtime-tools rt) tool "tool"))
  (hash-set! (runtime-agents rt) name (list accepts produces tools proc)))

(define-syntax-rule (define-document rt name persistence field ...)
  (register-schema! rt 'name 'persistence (list 'field ...)))
(define-syntax-rule (define-pure rt name (arg) body ...)
  (register-pure! rt 'name (lambda (arg) body ...)))
(define-syntax-rule (define-actor rt name accepts produces (arg state) body ...)
  (register-actor! rt 'name 'accepts 'produces (lambda (arg state) body ...)))
(define-syntax-rule (define-tool rt name input output (arg state) body ...)
  (register-tool! rt 'name 'input 'output (lambda (arg state) body ...)))
(define-syntax-rule (define-agent rt name accepts produces (tool ...) (arg state) body ...)
  (register-agent! rt 'name 'accepts 'produces '(tool ...)
                   (lambda (arg state) body ...)))
(define-syntax-rule (define-dataflow rt name stage ...)
  (register-dataflow! rt 'name '(stage ...)))
(define-syntax-rule (define-star-program name builder)
  (define (name fixture) (builder fixture)))

(define (entry-value entries key [who "map"])
  (match (assoc key entries)
    [(list _ value) value]
    [_ (star-fail 'schema "~a has no key ~a" who key)]))

(define (document-ref value . path)
  (for/fold ([current value]) ([key path])
    (cond
      [(doc? current) (entry-value (doc-fields current) key (doc-type current))]
      [(list? current) (entry-value current key)]
      [else (star-fail 'schema "cannot read ~a from ~e" key current)])))

(define (email? value)
  (and (string? value)
       (regexp-match? #px"^[^@ ]+@[^@ ]+\\.[^@ ]+$" value)))

(define (type-valid? rt type value)
  (match type
    ['string (string? value)]
    ['symbol (symbol? value)]
    ['boolean (boolean? value)]
    ['email (email? value)]
    [(list 'list-of item) (and (list? value)
                               (andmap (lambda (v) (type-valid? rt item v)) value))]
    [name (and (symbol? name) (doc? value) (eq? (doc-type value) name))]
    [_ #f]))

(define (make-checked-document rt type persistence fields)
  (match-define (list expected field-specs)
    (table-ref (runtime-schemas rt) type "document schema"))
  (unless (eq? persistence expected)
    (star-fail 'persistence "~a must be ~a" type expected))
  (for ([field fields])
    (unless (assoc (car field) field-specs)
      (star-fail 'schema "unknown field ~a on ~a" (car field) type)))
  (for ([spec field-specs])
    (match-define (list name field-type required?) spec)
    (define found (assoc name fields))
    (when (and required? (not found))
      (star-fail 'schema "missing field ~a on ~a" name type))
    (when (and found (not (type-valid? rt field-type (cadr found))))
      (star-fail 'schema "invalid field ~a on ~a" name type)))
  (doc type persistence fields))

(define (persistent-document rt type . fields)
  (make-checked-document rt type 'persistent fields))
(define (transient-document rt type . fields)
  (make-checked-document rt type 'transient fields))

(define (persist! rt value)
  (unless (eq? (doc-persistence value) 'persistent)
    (star-fail 'persistence "transient ~a cannot be persisted" (doc-type value)))
  (set-runtime-persisted! rt (cons value (runtime-persisted rt)))
  (event! rt 'persisted (doc-type value))
  value)

(define (target-kind rt name)
  (cond [(hash-has-key? (runtime-actors rt) name) 'actor]
        [(hash-has-key? (runtime-agents rt) name) 'agent]
        [else (star-fail 'definition "unknown target ~a" name)]))

(define (compile-stage rt stage)
  (match stage
    [(list 'from type)
     (table-ref (runtime-schemas rt) type "document schema")
     (list 'op 'from 'type type)]
    [(list 'filter name)
     (table-ref (runtime-pure rt) name "pure function")
     (list 'op 'filter 'function name)]
    [(list 'flat-map name)
     (table-ref (runtime-pure rt) name "pure function")
     (list 'op 'flat-map 'function name)]
    [(list 'through name)
     (list 'op 'through 'target name 'kind (target-kind rt name))]
    [(list 'parallel limit nested)
     (unless (exact-positive-integer? limit)
       (star-fail 'definition "parallel limit must be positive"))
     (list 'op 'parallel 'limit limit 'stage (compile-stage rt nested))]
    [(list 'into 'persist) (list 'op 'into 'sink 'persist)]
    [_ (star-fail 'definition "unknown stage ~e" stage)]))

(define (register-dataflow! rt name source)
  (hash-set! (runtime-flows rt) name
             (map (lambda (stage) (compile-stage rt stage)) source)))
(define (dataflow-plan rt name) (table-ref (runtime-flows rt) name "dataflow"))
(define (plist-ref plan key)
  (let loop ([items plan])
    (cond [(null? items) (star-fail 'execution "plan has no ~a" key)]
          [(eq? (car items) key) (cadr items)]
          [else (loop (cddr items))])))

(define (invoke-actor rt name value)
  (match-define (list accepts produces proc)
    (table-ref (runtime-actors rt) name "actor"))
  (unless (type-valid? rt accepts value) (star-fail 'execution "actor input"))
  (event! rt 'actor-invoked name)
  (define result (proc value rt))
  (unless (type-valid? rt produces result) (star-fail 'execution "actor output"))
  (event! rt 'actor-result name)
  result)

(define (call-tool rt agent-name tool-name input)
  (match-define (list _ _ tools _) (table-ref (runtime-agents rt) agent-name "agent"))
  (unless (member tool-name tools) (star-fail 'execution "undeclared tool ~a" tool-name))
  (match-define (list input-type output-type proc)
    (table-ref (runtime-tools rt) tool-name "tool"))
  (unless (type-valid? rt input-type input) (star-fail 'execution "tool input"))
  (event! rt 'tool-invoked tool-name)
  (define result (proc input rt))
  (unless (type-valid? rt output-type result) (star-fail 'execution "tool output"))
  result)

(define (invoke-agent rt name values)
  (match-define (list accepts produces _ proc)
    (table-ref (runtime-agents rt) name "agent"))
  (unless (type-valid? rt accepts values) (star-fail 'execution "agent input"))
  (define result (proc values rt))
  (unless (type-valid? rt produces result) (star-fail 'execution "agent output"))
  result)

(define (execute-through rt plan values)
  (define name (plist-ref plan 'target))
  (case (plist-ref plan 'kind)
    [(actor) (map (lambda (v) (invoke-actor rt name v)) values)]
    [(agent) (list (invoke-agent rt name values))]))

(define (execute-stage rt plan values)
  (case (plist-ref plan 'op)
    [(from) values]
    [(filter)
     (filter (table-ref (runtime-pure rt) (plist-ref plan 'function) "pure") values)]
    [(flat-map)
     (define out
       (append-map (table-ref (runtime-pure rt) (plist-ref plan 'function) "pure") values))
     (for ([v out]) (event! rt 'transient-emitted (doc-type v)))
     out]
    [(through) (execute-through rt plan values)]
    [(parallel)
     (event! rt 'parallel-stage (plist-ref plan 'limit))
     (execute-through rt (plist-ref plan 'stage) values)]
    [(into) (map (lambda (v) (persist! rt v)) values)]))

(define (run-dataflow rt name input)
  (for/fold ([values (list input)]) ([stage (dataflow-plan rt name)])
    (execute-stage rt stage values)))

(define forbidden-reader #px"[#'`,]")
(define (load-fixture path)
  (define bytes (file->bytes path))
  (when (> (bytes-length bytes) 65536) (star-fail 'fixture "fixture too large"))
  (define text (bytes->string/utf-8 bytes))
  (when (regexp-match? forbidden-reader text)
    (star-fail 'fixture "reader syntax is forbidden"))
  (define in (open-input-string text))
  (define value (read in))
  (when (eof-object? value) (star-fail 'fixture "empty fixture"))
  (unless (eof-object? (read in)) (star-fail 'fixture "multiple forms"))
  value)

(define (fixture-value fixture key) (entry-value fixture key "fixture"))
(define (actor-status fixture email)
  (entry-value (fixture-value fixture 'actor-results) email "actor-results"))

(define expected-plan
  '((op from type target)
    (op filter function enumeration-target?)
    (op flat-map function generate-email-candidates)
    (op parallel limit 4 stage (op through target email-testing-actor kind actor))
    (op filter function found-candidate?)
    (op through target review-agent kind agent)
    (op into sink persist)))

(define (build-example-runtime fixture)
  (define rt (make-runtime))
  (define domains (fixture-value fixture 'domains))
  (define-document rt user persistent (username string #t))
  (define-document rt target persistent (options boolean #t) (data user #t))
  (define-document rt email-candidate transient (username string #t) (email email #t))
  (define-document rt tested-email-candidate transient
    (username string #t) (email email #t) (status symbol #t))
  (define-document rt final-review persistent
    (username string #t) (found-emails (list-of email) #t) (decision symbol #t))
  (define-pure rt enumeration-target? (target)
    (and (document-ref target 'options)
         (doc? (document-ref target 'data))))
  (define-pure rt generate-email-candidates (target)
    (define username (document-ref target 'data 'username))
    (for/list ([domain domains])
      (transient-document rt 'email-candidate
                          (list 'username username)
                          (list 'email (string-append username "@" domain)))))
  (define-pure rt found-candidate? (candidate)
    (eq? (document-ref candidate 'status) 'found))
  (define-actor rt email-testing-actor email-candidate tested-email-candidate
    (candidate state)
    (transient-document state 'tested-email-candidate
                        (list 'username (document-ref candidate 'username))
                        (list 'email (document-ref candidate 'email))
                        (list 'status (actor-status fixture
                                                   (document-ref candidate 'email)))))
  (define-tool rt candidate-summary (list-of tested-email-candidate) (list-of email)
    (candidates state)
    (map (lambda (candidate) (document-ref candidate 'email)) candidates))
  (define-agent rt review-agent (list-of tested-email-candidate) final-review
    (candidate-summary) (candidates state)
    (persistent-document state 'final-review
                         (list 'username (document-ref (car candidates) 'username))
                         (list 'found-emails
                               (call-tool state 'review-agent 'candidate-summary candidates))
                         (list 'decision 'review-required)))
  (define-dataflow rt email-enumeration
    (from target)
    (filter enumeration-target?)
    (flat-map generate-email-candidates)
    (parallel 4 (through email-testing-actor))
    (filter found-candidate?)
    (through review-agent)
    (into persist))
  rt)

(define (run-example fixture-path)
  (define fixture (load-fixture fixture-path))
  (define rt (build-example-runtime fixture))
  (define target-spec (fixture-value fixture 'target))
  (define target-fields (fixture-value target-spec 'fields))
  (define options (entry-value target-fields 'options "target fields"))
  (define user-spec (entry-value target-fields 'data "target fields"))
  (define user-fields (fixture-value user-spec 'fields))
  (define user
    (persistent-document rt 'user
                         (list 'username
                               (entry-value user-fields 'username "user fields"))))
  (define target
    (persistent-document rt 'target
                         (list 'options
                               (eq? (entry-value options 'enumeration "options") 'true))
                         (list 'data user)))
  (values rt (run-dataflow rt 'email-enumeration target) fixture))

(define (benchmark-example fixture-path iterations)
  (define started (current-inexact-milliseconds))
  (for ([_ (in-range iterations)])
    (call-with-values (lambda () (run-example fixture-path))
                      (lambda values (void))))
  (/ (- (current-inexact-milliseconds) started) 1000.0))
