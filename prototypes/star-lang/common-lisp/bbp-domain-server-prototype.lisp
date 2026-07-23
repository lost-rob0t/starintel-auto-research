(in-package #:star-lang.core-surface.prototype)

(export '(bbp-domain-actor-contract
          bbp-domain-definition
          bbp-domain-tools
          bbp-invoke-command
          bbp-program-run-count
          bbp-program-scope
          compile-bbp-domain-program
          make-bbp-domain-engine
          make-bbp-register-program-command
          make-bbp-run-tool-command))

(defparameter *bbp-domain-prototype-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*))

(define-condition bbp-domain-error (domain-server-core-error) ())
(define-condition bbp-scope-error (bbp-domain-error) ())

(defparameter +bbp-register-program-message+
  "org.starintel/bbp@1/register-program")
(defparameter +bbp-program-registered-message+
  "org.starintel/bbp@1/program-registered")
(defparameter +bbp-run-tool-message+
  "org.starintel/bbp@1/run-tool")
(defparameter +bbp-tool-run-completed-message+
  "org.starintel/bbp@1/tool-run-completed")
(defparameter +bbp-get-program-state-message+
  "org.starintel/bbp@1/get-program-state")
(defparameter +bbp-program-state-message+
  "org.starintel/bbp@1/program-state")

(defstruct (bbp-program-state
            (:constructor make-bbp-program-state
                (&key program-id name scope)))
  program-id
  name
  (scope '())
  (runs '()))

(defun bbp-program-scope (engine program-id)
  (let ((state (domain-server-engine-instance-state engine program-id)))
    (and state (copy-list (bbp-program-state-scope state)))))

(defun bbp-program-run-count (engine program-id)
  (let ((state (domain-server-engine-instance-state engine program-id)))
    (if state (length (bbp-program-state-runs state)) 0)))

(defun bbp-domain-tools (library)
  (mapcar
   (lambda (form) (compile-domain-tool form library))
   '((tool subfinder
       (:executable "subfinder"
        :argv ("-silent" "-d" :target)
        :input domain-name
        :produces tool-run-completed
        :timeout-ms 300000
        :capabilities (network dns)))
     (tool httpx
       (:executable "httpx"
        :argv ("-silent" "-json" "-u" :target)
        :input domain-name
        :produces tool-run-completed
        :timeout-ms 300000
        :capabilities (network http)))
     (tool katana
       (:executable "katana"
        :argv ("-silent" "-jsonl" "-u" :target)
        :input domain-name
        :produces tool-run-completed
        :timeout-ms 600000
        :capabilities (network http crawl)))
     (tool nmap
       (:executable "nmap"
        :argv ("-sV" "-oX" "-" :target)
        :input domain-name
        :produces tool-run-completed
        :timeout-ms 900000
        :capabilities (network active-scan))))))

(defun bbp-domain-definition (library tools)
  (compile-domain-server
   '(domain-server bbp
     (:key-type program-id
      :owns (program target tool-run tool-observation)
      :accepts (register-program run-tool get-program-state)
      :tools (subfinder httpx katana nmap)
      :restart permanent
      :mailbox (bounded 1024)
      :dispatcher bbp-tools
      :capabilities (run-tools emit-documents remote-export)))
   library
   tools))

(defun bbp-domain-actor-contract (library)
  (compile-actor
   '(actor bbp-domain
     (:runtime external
      :protocol sento-remoting-v1
      :endpoint "sento://dynamic/user/bbp-domain"
      :accepts (register-program run-tool get-program-state)
      :produces (program-registered tool-run-completed program-state)
      :restart permanent
      :mailbox (bounded 1024)
      :capabilities (remote-domain tool-execution)))
   library))

(defun compile-bbp-domain-program ()
  (let* ((fixture
           (merge-pathnames "../fixtures/bbp-domain.star"
                            *bbp-domain-prototype-directory*))
         (library (compile-core-library (load-star-form fixture)))
         (tools (bbp-domain-tools library))
         (domain (bbp-domain-definition library tools))
         (actor (bbp-domain-actor-contract library))
         (manifest
           (emit-domain-program-manifest
            library (list actor) tools (list domain))))
    (values library tools domain actor manifest)))

(defun bbp-payload-entry (payload key)
  (cond
    ((and (listp payload) (every #'consp payload))
     (assoc (identifier-string key) payload :test #'string=))
    ((listp payload)
     (let ((keyword (intern (string-upcase (identifier-string key)) :keyword)))
       (and (plist-has-key-p payload keyword)
            (cons (identifier-string key) (getf payload keyword)))))
    (t nil)))

(defun bbp-payload-value (payload key)
  (cdr (bbp-payload-entry payload key)))

(defun required-bbp-payload (payload key context)
  (let ((entry (bbp-payload-entry payload key)))
    (unless entry
      (fail 'bbp-domain-error
            "~A requires payload field ~A."
            context (identifier-string key)))
    (cdr entry)))

(defun normalize-bbp-scope-entry (value)
  (unless (and (stringp value) (> (length value) 0))
    (fail 'bbp-scope-error "BBP scope entries must be nonempty strings."))
  (let* ((lower (string-downcase value))
         (without-wildcard
           (if (and (> (length lower) 2)
                    (string= "*." lower :end2 2))
               (subseq lower 2)
               lower)))
    (string-right-trim "." without-wildcard)))

(defun bbp-target-host (target)
  (let* ((lower (string-downcase target))
         (scheme (search "://" lower))
         (start (if scheme (+ scheme 3) 0))
         (slash (position #\/ lower :start start))
         (authority (subseq lower start (or slash (length lower))))
         (colon (position #\: authority)))
    (string-right-trim
     "."
     (if colon (subseq authority 0 colon) authority))))

(defun bbp-target-in-scope-p (target scope)
  (let ((host (bbp-target-host target)))
    (some
     (lambda (entry)
       (let ((root (normalize-bbp-scope-entry entry)))
         (or (string= host root)
             (and (> (length host) (length root))
                  (string= root host
                           :start2 (- (length host) (length root)))
                  (char= #\. (char host
                                  (1- (- (length host)
                                        (length root)))))))))
     scope)))

(defun bbp-tool-by-name (engine value)
  (let* ((name (identifier-string value))
         (tool (gethash name (domain-server-engine-tools engine))))
    (or tool
        (fail 'bbp-domain-error "Unknown BBP tool ~A." name))))

(defun bbp-register-program-handler (instance payload engine)
  (declare (ignore engine))
  (let* ((program-id
           (required-bbp-payload payload :program-id "register-program"))
         (name (required-bbp-payload payload :name "register-program"))
         (scope (required-bbp-payload payload :scope "register-program")))
    (unless (string= program-id (domain-server-instance-key instance))
      (fail 'bbp-domain-error
            "Program payload key ~A does not match domain key ~A."
            program-id (domain-server-instance-key instance)))
    (unless (and (stringp name)
                 (listp scope)
                 scope
                 (every #'stringp scope))
      (fail 'bbp-domain-error
            "register-program requires a name and nonempty string scope list."))
    (setf (domain-server-instance-state instance)
          (make-bbp-program-state
           :program-id program-id
           :name name
           :scope (mapcar #'normalize-bbp-scope-entry scope)))
    (list (cons "program-id" program-id)
          (cons "scope" (bbp-program-state-scope
                          (domain-server-instance-state instance))))))

(defun require-bbp-program-state (instance)
  (or (domain-server-instance-state instance)
      (fail 'bbp-domain-error
            "BBP program ~A is not registered."
            (domain-server-instance-key instance))))

(defun bbp-run-tool-handler (instance payload engine)
  (let* ((state (require-bbp-program-state instance))
         (program-id
           (required-bbp-payload payload :program-id "run-tool"))
         (run-id (required-bbp-payload payload :run-id "run-tool"))
         (tool-value (required-bbp-payload payload :tool "run-tool"))
         (target (required-bbp-payload payload :target "run-tool"))
         (tool (bbp-tool-by-name engine tool-value)))
    (unless (and (stringp program-id)
                 (stringp run-id)
                 (stringp target))
      (fail 'bbp-domain-error
            "run-tool requires string program-id, run-id, and target."))
    (unless (string= program-id (bbp-program-state-program-id state))
      (fail 'bbp-domain-error
            "run-tool program ~A does not match domain key ~A."
            program-id (domain-server-instance-key instance)))
    (unless (bbp-target-in-scope-p target (bbp-program-state-scope state))
      (fail 'bbp-scope-error
            "Target ~A is outside BBP program ~A scope."
            target program-id))
    (let* ((request
             (list (cons "program-id" program-id)
                   (cons "run-id" run-id)
                   (cons "target" target)))
           (result
             (run-domain-tool
              (domain-server-engine-tool-runner engine)
              tool
              request))
           (payload-result
             (list (cons "program-id" program-id)
                   (cons "run-id" run-id)
                   (cons "tool" (getf tool :name))
                   (cons "target" target)
                   (cons "argv" (getf result :argv))
                   (cons "exit-code" (getf result :exit-code))
                   (cons "stdout" (getf result :stdout))
                   (cons "stderr" (getf result :stderr)))))
      (push payload-result (bbp-program-state-runs state))
      payload-result)))

(defun bbp-program-state-handler (instance payload engine)
  (declare (ignore payload engine))
  (let ((state (require-bbp-program-state instance)))
    (list (cons "program-id" (bbp-program-state-program-id state))
          (cons "scope" (copy-list (bbp-program-state-scope state)))
          (cons "runs" (length (bbp-program-state-runs state))))))

(defun make-bbp-domain-engine (definition tools tool-runner)
  (make-domain-server-engine
   :definition definition
   :tools tools
   :tool-runner tool-runner
   :initializer (lambda (key engine)
                  (declare (ignore key engine))
                  nil)
   :handlers
   (list (cons +bbp-register-program-message+
               #'bbp-register-program-handler)
         (cons +bbp-run-tool-message+
               #'bbp-run-tool-handler)
         (cons +bbp-get-program-state-message+
               #'bbp-program-state-handler))))

(defun bbp-result-message-type (input-message-type)
  (cond
    ((string= input-message-type +bbp-register-program-message+)
     +bbp-program-registered-message+)
    ((string= input-message-type +bbp-run-tool-message+)
     +bbp-tool-run-completed-message+)
    ((string= input-message-type +bbp-get-program-state-message+)
     +bbp-program-state-message+)
    (t
     (fail 'bbp-domain-error
           "No BBP result message for ~A."
           input-message-type))))

(defun bbp-command-program-id (command)
  (let ((program-id
          (required-bbp-payload
           (getf command :payload) :program-id "BBP command")))
    (unless (stringp program-id)
      (fail 'bbp-domain-error "BBP command program-id must be a string."))
    program-id))

(defun bbp-invoke-command (engine command)
  (handler-case
      (let* ((message-type (getf command :message-type))
             (program-id (bbp-command-program-id command))
             (payload
               (invoke-domain-operation
                engine program-id message-type (getf command :payload))))
        (complete-dispatch
         :message-type (bbp-result-message-type message-type)
         :payload payload))
    (bbp-scope-error (condition)
      (fail-dispatch
       :code "star.bbp.out-of-scope"
       :message (princ-to-string condition)
       :retryable nil))
    ((or bbp-domain-error domain-tool-error domain-server-core-error) (condition)
      (fail-dispatch
       :code "star.bbp.domain-error"
       :message (princ-to-string condition)
       :retryable nil))
    (error (condition)
      (fail-dispatch
       :code "star.bbp.unexpected-error"
       :message (princ-to-string condition)
       :retryable nil))))

(defun make-bbp-register-program-command
    (&key message-id program-id name scope
          (sender "bbp-client")
          (idempotency-key nil))
  (make-command-envelope
   :message-id message-id
   :message-type +bbp-register-program-message+
   :actor "bbp-domain"
   :sender sender
   :idempotency-key
   (or idempotency-key
       (format nil "bbp:register:~A" program-id))
   :payload
   (list (cons "program-id" program-id)
         (cons "name" name)
         (cons "scope" scope))))

(defun make-bbp-run-tool-command
    (&key message-id program-id run-id tool target
          (sender "bbp-client")
          (idempotency-key nil))
  (make-command-envelope
   :message-id message-id
   :message-type +bbp-run-tool-message+
   :actor "bbp-domain"
   :sender sender
   :idempotency-key
   (or idempotency-key
       (format nil "bbp:tool:~A:~A" program-id run-id))
   :payload
   (list (cons "program-id" program-id)
         (cons "run-id" run-id)
         (cons "tool" (identifier-string tool))
         (cons "target" target)
         (cons "options" '()))))
