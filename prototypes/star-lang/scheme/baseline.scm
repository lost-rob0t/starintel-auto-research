(use-modules (ice-9 format)
             (ice-9 match)
             (ice-9 regex)
             (ice-9 textual-ports)
             (srfi srfi-1)
             (srfi srfi-9))

(define star-error-tag 'star-lang-error)
(define (fail kind fmt . args)
  (throw star-error-tag kind (apply format #f fmt args)))

(define-record-type <schema>
  (make-schema name persistence fields)
  schema?
  (name schema-name)
  (persistence schema-persistence)
  (fields schema-fields))

(define-record-type <doc>
  (make-doc type persistence fields)
  doc?
  (type doc-type)
  (persistence doc-persistence)
  (fields doc-fields))

(define-record-type <actor>
  (make-actor name accepts produces behavior)
  actor?
  (name actor-name)
  (accepts actor-accepts)
  (produces actor-produces)
  (behavior actor-behavior))

(define-record-type <tool>
  (make-tool name input output behavior)
  tool?
  (name tool-name)
  (input tool-input)
  (output tool-output)
  (behavior tool-behavior))

(define-record-type <agent>
  (make-agent name accepts produces tools behavior)
  agent?
  (name agent-name)
  (accepts agent-accepts)
  (produces agent-produces)
  (tools agent-tools)
  (behavior agent-behavior))

(define-record-type <flow>
  (make-flow name source plan)
  flow?
  (name flow-name)
  (source flow-source)
  (plan flow-plan))

(define-record-type <runtime>
  (%make-runtime schemas actors tools agents pure flows persisted events)
  runtime?
  (schemas runtime-schemas set-runtime-schemas!)
  (actors runtime-actors set-runtime-actors!)
  (tools runtime-tools set-runtime-tools!)
  (agents runtime-agents set-runtime-agents!)
  (pure runtime-pure set-runtime-pure!)
  (flows runtime-flows set-runtime-flows!)
  (persisted runtime-persisted set-runtime-persisted!)
  (events runtime-events set-runtime-events!))

(define (make-runtime)
  (%make-runtime '() '() '() '() '() '() '() '()))

(define (put table key value)
  (acons key value (alist-delete key table eq?)))

(define (lookup table key kind)
  (let ((entry (assq key table)))
    (if entry (cdr entry) (fail 'definition "Unknown ~a ~a." kind key))))

(define (record! rt kind . payload)
  (set-runtime-events! rt (cons (cons kind payload) (runtime-events rt))))

(define (event-count rt kind)
  (count (lambda (event) (eq? (car event) kind)) (runtime-events rt)))

(define (register-schema! rt schema)
  (set-runtime-schemas! rt
    (put (runtime-schemas rt) (schema-name schema) schema)))

(define (register-actor! rt actor)
  (set-runtime-actors! rt
    (put (runtime-actors rt) (actor-name actor) actor)))

(define (register-tool! rt tool)
  (set-runtime-tools! rt
    (put (runtime-tools rt) (tool-name tool) tool)))

(define (register-agent! rt agent)
  (for-each (lambda (name) (lookup (runtime-tools rt) name "tool"))
            (agent-tools agent))
  (set-runtime-agents! rt
    (put (runtime-agents rt) (agent-name agent) agent)))

(define (register-pure! rt name proc)
  (set-runtime-pure! rt (put (runtime-pure rt) name proc)))

(define-syntax define-document
  (syntax-rules ()
    ((_ rt name persistence field ...)
     (register-schema! rt (make-schema 'name 'persistence (list 'field ...))))))

(define-syntax define-pure
  (syntax-rules ()
    ((_ rt name (arg) body ...)
     (register-pure! rt 'name (lambda (arg) body ...)))))

(define-syntax define-actor
  (syntax-rules ()
    ((_ rt name accepts produces (arg state) body ...)
     (register-actor! rt
       (make-actor 'name 'accepts 'produces (lambda (arg state) body ...))))))

(define-syntax define-tool
  (syntax-rules ()
    ((_ rt name input output (arg state) body ...)
     (register-tool! rt
       (make-tool 'name 'input 'output (lambda (arg state) body ...))))))

(define-syntax define-agent
  (syntax-rules ()
    ((_ rt name accepts produces (tool ...) (arg state) body ...)
     (register-agent! rt
       (make-agent 'name 'accepts 'produces '(tool ...)
                   (lambda (arg state) body ...))))))

(define-syntax define-dataflow
  (syntax-rules ()
    ((_ rt name stage ...)
     (register-flow! rt 'name '(stage ...)))))

(define (map-value? value)
  (and (list? value)
       (every (lambda (entry)
                (and (list? entry) (= (length entry) 2)))
              value)))

(define (map-ref value key)
  (let ((entry (assoc key value)))
    (if entry (cadr entry) (fail 'schema "Missing key ~a." key))))

(define (document-ref value . path)
  (fold (lambda (key current)
          (cond ((doc? current) (map-ref (doc-fields current) key))
                ((map-value? current) (map-ref current key))
                (else (fail 'schema "Cannot read key ~a." key))))
        value
        path))

(define (email? value)
  (and (string? value)
       (string-match "^[^@ ]+@[^@ ]+\\.[^@ ]+$" value)))

(define (type-valid? rt type value)
  (cond ((eq? type 'string) (string? value))
        ((eq? type 'boolean) (boolean? value))
        ((eq? type 'symbol) (symbol? value))
        ((eq? type 'email) (email? value))
        ((eq? type 'map) (map-value? value))
        ((and (pair? type) (eq? (car type) 'list-of))
         (and (list? value)
              (every (lambda (item) (type-valid? rt (cadr type) item)) value)))
        ((assq type (runtime-schemas rt))
         (and (doc? value) (eq? type (doc-type value))))
        (else #f)))

(define (validate-document rt value)
  (unless (doc? value) (fail 'schema "Expected document."))
  (let* ((contract (lookup (runtime-schemas rt) (doc-type value) "schema"))
         (specs (schema-fields contract)))
    (unless (eq? (schema-persistence contract) (doc-persistence value))
      (fail 'persistence "Wrong persistence for ~a." (doc-type value)))
    (for-each
      (lambda (field)
        (unless (find (lambda (spec) (eq? (car spec) (car field))) specs)
          (fail 'schema "Unknown field ~a." (car field))))
      (doc-fields value))
    (for-each
      (lambda (spec)
        (match spec
          ((name type required?)
           (let ((entry (assq name (doc-fields value))))
             (when (and required? (not entry))
               (fail 'schema "Missing field ~a." name))
             (when (and entry (not (type-valid? rt type (cadr entry))))
               (fail 'schema "Invalid field ~a." name))))))
      specs)
    value))

(define (make-document rt type persistence fields)
  (validate-document rt (make-doc type persistence fields)))

(define (persistent-document rt type . fields)
  (make-document rt type 'persistent fields))

(define (transient-document rt type . fields)
  (make-document rt type 'transient fields))

(define (persist! rt value)
  (validate-document rt value)
  (unless (eq? (doc-persistence value) 'persistent)
    (fail 'persistence "Transient ~a cannot persist." (doc-type value)))
  (set-runtime-persisted! rt (cons value (runtime-persisted rt)))
  (record! rt 'persisted (doc-type value))
  value)

(define (plist-ref values key)
  (match values
    (() (fail 'definition "Missing plan key ~a." key))
    ((head value . rest)
     (if (eq? head key) value (plist-ref rest key)))))

(define (target-kind rt name)
  (cond ((assq name (runtime-actors rt)) 'actor)
        ((assq name (runtime-agents rt)) 'agent)
        (else (fail 'definition "Unknown target ~a." name))))

(define (compile-stage rt stage)
  (match stage
    (('from type)
     (lookup (runtime-schemas rt) type "schema")
     (list 'op 'from 'type type))
    (('filter name)
     (lookup (runtime-pure rt) name "function")
     (list 'op 'filter 'function name))
    (('flat-map name)
     (lookup (runtime-pure rt) name "function")
     (list 'op 'flat-map 'function name))
    (('through name)
     (list 'op 'through 'target name 'kind (target-kind rt name)))
    (('parallel limit nested)
     (let ((plan (compile-stage rt nested)))
       (unless (and (integer? limit) (> limit 0)
                    (eq? (plist-ref plan 'kind) 'actor))
         (fail 'definition "Invalid parallel stage."))
       (list 'op 'parallel 'limit limit 'stage plan)))
    (('into 'persist) (list 'op 'into 'sink 'persist))
    (_ (fail 'definition "Invalid stage ~a." stage))))

(define (register-flow! rt name source)
  (set-runtime-flows! rt
    (put (runtime-flows rt) name
         (make-flow name source (map (lambda (stage) (compile-stage rt stage)) source)))))

(define (dataflow-plan rt name)
  (flow-plan (lookup (runtime-flows rt) name "flow")))

(define (invoke-actor rt name value)
  (let ((actor (lookup (runtime-actors rt) name "actor")))
    (unless (type-valid? rt (actor-accepts actor) value)
      (fail 'execution "Actor rejected input."))
    (record! rt 'actor-invoked name)
    (let ((result ((actor-behavior actor) value rt)))
      (unless (type-valid? rt (actor-produces actor) result)
        (fail 'execution "Actor returned invalid output."))
      (record! rt 'actor-result name)
      result)))

(define (call-tool rt agent-name tool-name input)
  (let ((agent (lookup (runtime-agents rt) agent-name "agent"))
        (tool (lookup (runtime-tools rt) tool-name "tool")))
    (unless (memq tool-name (agent-tools agent))
      (fail 'execution "Undeclared tool ~a." tool-name))
    (unless (type-valid? rt (tool-input tool) input)
      (fail 'execution "Tool rejected input."))
    (record! rt 'tool-invoked tool-name)
    (let ((result ((tool-behavior tool) input rt)))
      (unless (type-valid? rt (tool-output tool) result)
        (fail 'execution "Tool returned invalid output."))
      result)))

(define (invoke-agent rt name values)
  (let ((agent (lookup (runtime-agents rt) name "agent")))
    (unless (type-valid? rt (agent-accepts agent) values)
      (fail 'execution "Agent rejected input."))
    (let ((result ((agent-behavior agent) values rt)))
      (unless (type-valid? rt (agent-produces agent) result)
        (fail 'execution "Agent returned invalid output."))
      result)))

(define (execute-through rt plan values)
  (case (plist-ref plan 'kind)
    ((actor)
     (map (lambda (value)
            (invoke-actor rt (plist-ref plan 'target) value))
          values))
    ((agent)
     (list (invoke-agent rt (plist-ref plan 'target) values)))))

(define (execute-stage rt plan values)
  (case (plist-ref plan 'op)
    ((from) values)
    ((filter)
     (filter (lookup (runtime-pure rt) (plist-ref plan 'function) "function") values))
    ((flat-map)
     (let ((results
            (append-map
              (lookup (runtime-pure rt) (plist-ref plan 'function) "function")
              values)))
       (for-each (lambda (value)
                   (validate-document rt value)
                   (record! rt 'transient-emitted (doc-type value)))
                 results)
       results))
    ((through) (execute-through rt plan values))
    ((parallel)
     (record! rt 'parallel-stage (plist-ref plan 'limit))
     (execute-through rt (plist-ref plan 'stage) values))
    ((into) (map (lambda (value) (persist! rt value)) values))))

(define (run-dataflow rt name input)
  (fold (lambda (plan values) (execute-stage rt plan values))
        (list (validate-document rt input))
        (dataflow-plan rt name)))

(define (fixture-node? value)
  (or (null? value) (string? value) (integer? value) (symbol? value)
      (and (list? value) (every fixture-node? value))))

(define (forbidden-reader-syntax? text)
  (let loop ((index 0))
    (and (< index (string-length text))
         (or (memv (string-ref text index) '(#\# #\' #\` #\,))
             (loop (+ index 1))))))

(define (load-fixture path)
  (call-with-input-file path
    (lambda (port)
      (let ((text (get-string-all port)))
        (when (> (string-length text) 65536)
          (fail 'fixture "Fixture is too large."))
        (when (forbidden-reader-syntax? text)
          (fail 'fixture "Reader syntax is forbidden."))
        (let* ((input (open-input-string text))
               (value (read input)))
          (when (eof-object? value) (fail 'fixture "Empty fixture."))
          (unless (eof-object? (read input)) (fail 'fixture "Multiple forms."))
          (unless (fixture-node? value) (fail 'fixture "Forbidden fixture value."))
          value)))))

(define (fixture-ref fixture key) (map-ref fixture key))

(define (decode-value rt value)
  (cond ((eq? value 'true) #t)
        ((eq? value 'false) #f)
        ((and (map-value? value) (assq 'type value))
         (decode-document rt value))
        ((map-value? value)
         (map (lambda (entry)
                (list (car entry) (decode-value rt (cadr entry))))
              value))
        ((list? value) (map (lambda (item) (decode-value rt item)) value))
        (else value)))

(define (decode-document rt specification)
  (make-document rt
                 (fixture-ref specification 'type)
                 (fixture-ref specification 'persistence)
                 (decode-value rt (fixture-ref specification 'fields))))

(define (actor-status fixture email)
  (let ((entry (find (lambda (item) (string=? (car item) email))
                     (fixture-ref fixture 'actor-results))))
    (if entry (cadr entry) (fail 'fixture "No result for ~a." email))))

(define expected-plan
  '((op from type target)
    (op filter function enumeration-target?)
    (op flat-map function generate-email-candidates)
    (op parallel limit 4 stage (op through target email-testing-actor kind actor))
    (op filter function found-candidate?)
    (op through target review-agent kind agent)
    (op into sink persist)))

(define (build-runtime fixture)
  (let ((rt (make-runtime))
        (domains (fixture-ref fixture 'domains)))
    (define-document rt user persistent (username string #t))
    (define-document rt target persistent (options map #t) (data user #t))
    (define-document rt email-candidate transient
      (username string #t) (email email #t))
    (define-document rt tested-email-candidate transient
      (username string #t) (email email #t) (status symbol #t))
    (define-document rt final-review persistent
      (username string #t) (found-emails (list-of email) #t) (decision symbol #t))

    (define-pure rt enumeration-target? (target)
      (and (document-ref target 'options 'enumeration)
           (doc? (document-ref target 'data))))

    (define-pure rt generate-email-candidates (target)
      (let ((username (document-ref target 'data 'username)))
        (map (lambda (domain)
               (transient-document rt 'email-candidate
                 (list 'username username)
                 (list 'email (string-append username "@" domain))))
             domains)))

    (define-pure rt found-candidate? (candidate)
      (eq? (document-ref candidate 'status) 'found))

    (define-actor rt email-testing-actor email-candidate tested-email-candidate
      (candidate state)
      (transient-document state 'tested-email-candidate
        (list 'username (document-ref candidate 'username))
        (list 'email (document-ref candidate 'email))
        (list 'status (actor-status fixture (document-ref candidate 'email)))))

    (define-tool rt candidate-summary
      (list-of tested-email-candidate) (list-of email) (candidates state)
      (map (lambda (candidate) (document-ref candidate 'email)) candidates))

    (define-agent rt review-agent
      (list-of tested-email-candidate) final-review (candidate-summary) (candidates state)
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
    rt))

(define (run-example fixture-path)
  (let* ((fixture (load-fixture fixture-path))
         (rt (build-runtime fixture))
         (target (decode-document rt (fixture-ref fixture 'target)))
         (outputs (run-dataflow rt 'email-enumeration target)))
    (list rt outputs fixture)))

(define (now-seconds)
  (let ((time (gettimeofday)))
    (+ (car time) (/ (cdr time) 1000000.0))))

(define (benchmark-example fixture-path iterations)
  (let ((started (now-seconds)))
    (do ((remaining iterations (- remaining 1)))
        ((zero? remaining))
      (run-example fixture-path))
    (- (now-seconds) started)))
