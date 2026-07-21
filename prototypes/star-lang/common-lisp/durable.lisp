(in-package #:star-lang.core)

(export '(checkpoint-store
          delete-run-checkpoint
          durable-journal
          journal-append-event
          journal-read-events
          make-memory-checkpoint-store
          make-memory-journal
          memory-checkpoint-store
          memory-journal
          read-run-checkpoint
          run-checkpoint
          run-checkpoint-event-sequence
          run-checkpoint-plan-hash
          run-checkpoint-run-id
          run-checkpoint-state
          run-plan-durable
          simulated-runtime-crash
          write-run-checkpoint))

(define-condition simulated-runtime-crash (star-lang-error) ())

(defclass durable-journal () ())

(defgeneric journal-append-event (journal event))
(defgeneric journal-read-events (journal run-id))

(defclass memory-journal (durable-journal)
  ((events-by-run
    :initform (make-hash-table :test #'equal)
    :reader memory-journal-events-by-run)))

(defun make-memory-journal ()
  (make-instance 'memory-journal))

(defmethod journal-append-event ((journal memory-journal) event)
  (let* ((run-id (run-event-run-id event))
         (events (gethash run-id (memory-journal-events-by-run journal)))
         (expected-sequence (1+ (length events))))
    (unless (= expected-sequence (run-event-sequence event))
      (fail 'replay-error :invalid-event-sequence nil
            "Run ~A expected event sequence ~D, received ~D."
            run-id expected-sequence (run-event-sequence event)))
    (setf (gethash run-id (memory-journal-events-by-run journal))
          (append events (list event)))
    event))

(defmethod journal-read-events ((journal memory-journal) run-id)
  (copy-list
   (or (gethash run-id (memory-journal-events-by-run journal)) '())))

(defclass checkpoint-store () ())

(defstruct run-checkpoint
  run-id
  plan-hash
  event-sequence
  state)

(defgeneric write-run-checkpoint (store checkpoint))
(defgeneric read-run-checkpoint (store run-id plan-hash))
(defgeneric delete-run-checkpoint (store run-id plan-hash))

(defclass memory-checkpoint-store (checkpoint-store)
  ((checkpoints
    :initform (make-hash-table :test #'equal)
    :reader memory-checkpoints)))

(defun make-memory-checkpoint-store ()
  (make-instance 'memory-checkpoint-store))

(defun checkpoint-key (run-id plan-hash)
  (cons run-id plan-hash))

(defmethod write-run-checkpoint ((store memory-checkpoint-store) checkpoint)
  (setf (gethash
         (checkpoint-key (run-checkpoint-run-id checkpoint)
                         (run-checkpoint-plan-hash checkpoint))
         (memory-checkpoints store))
        checkpoint)
  checkpoint)

(defmethod read-run-checkpoint ((store memory-checkpoint-store)
                                run-id plan-hash)
  (gethash (checkpoint-key run-id plan-hash) (memory-checkpoints store)))

(defmethod delete-run-checkpoint ((store memory-checkpoint-store)
                                  run-id plan-hash)
  (remhash (checkpoint-key run-id plan-hash) (memory-checkpoints store)))

(defparameter *durable-event-sink* nil)
(defparameter *durable-event-sequence-offset* 0)
(defparameter *durable-crash-predicate* nil)

(defun record-run-event (runtime type run-id plan node-id payload)
  (let ((event
          (make-run-event
           :sequence (+ *durable-event-sequence-offset*
                        1
                        (length (core-runtime-events runtime)))
           :type type
           :run-id run-id
           :plan-hash (analysis-plan-hash plan)
           :node-id node-id
           :payload payload)))
    (push event (core-runtime-events runtime))
    (when *durable-event-sink*
      (funcall *durable-event-sink* event))
    (when (and *durable-crash-predicate*
               (funcall *durable-crash-predicate* event))
      (fail 'simulated-runtime-crash
            :simulated-runtime-crash
            nil
            "Simulated crash after event ~D (~A)."
            (run-event-sequence event)
            (run-event-type event)))
    event))

(defun dispatch-live-capability (runtime capability input run-id plan node identifier)
  (incf (core-runtime-dispatch-count runtime))
  (let ((previous (core-runtime-current-capability runtime)))
    (unwind-protect
         (progn
           (setf (core-runtime-current-capability runtime) capability)
           (let ((result
                   (funcall (capability-definition-function capability)
                            input runtime)))
             (record-run-event
              runtime :command-result run-id plan (plan-node-id node)
              (list :command-id identifier
                    :result result
                    :replayed nil))
             result))
      (setf (core-runtime-current-capability runtime) previous))))

(defun invoke-effect-capability (runtime capability input run-id plan node mode)
  (let* ((identifier (command-id run-id plan node input))
         (recorded
           (gethash identifier (core-runtime-replay-results runtime))))
    (record-run-event
     runtime :command-created run-id plan (plan-node-id node)
     (list :command-id identifier
           :capability (capability-definition-name capability)
           :input-hash (sha256-string (canonical-value input))))
    (case mode
      (:replay
       (unless recorded
         (fail 'replay-error :missing-command-result
               (plan-node-source-span node)
               "Replay has no result for command ~A." identifier))
       (record-run-event
        runtime :command-result run-id plan (plan-node-id node)
        (list :command-id identifier :result recorded :replayed t))
       recorded)
      (:resume
       (if recorded
           (progn
             (record-run-event
              runtime :command-result run-id plan (plan-node-id node)
              (list :command-id identifier :result recorded :replayed t))
             recorded)
           (dispatch-live-capability
            runtime capability input run-id plan node identifier)))
      (:live
       (dispatch-live-capability
        runtime capability input run-id plan node identifier))
      (otherwise
       (fail 'execution-error :invalid-run-mode nil
             "Unknown run mode ~S." mode)))))

(defun run-plan (plan registry inputs &key
                                      (run-id "run-0001")
                                      history
                                      (mode :live))
  (unless (member mode '(:live :replay :resume))
    (fail 'execution-error :invalid-run-mode nil
          "Unknown run mode ~S." mode))
  (let ((runtime (make-core-runtime registry :history history)))
    (if (eq mode :resume)
        (record-run-event
         runtime :run-resumed run-id plan nil
         (list :prior-event-count (length history)))
        (progn
          (record-run-event
           runtime :run-created run-id plan nil
           (list :analysis (analysis-plan-name plan)
                 :version (analysis-plan-version plan)))
          (record-run-event runtime :run-started run-id plan nil nil)))
    (let ((outputs
            (execute-node-list runtime plan (analysis-plan-nodes plan)
                               inputs run-id mode)))
      (record-run-event
       runtime :run-completed run-id plan nil
       (list :output-count (length outputs)
             :output-hashes
             (mapcar #'core-document-content-hash outputs)))
      (values outputs runtime))))

(defun run-plan-durable (plan registry inputs journal
                         &key
                           (run-id "run-0001")
                           crash-predicate)
  (let* ((history (journal-read-events journal run-id))
         (mode (if history :resume :live))
         (*durable-event-sequence-offset* (length history))
         (*durable-event-sink*
           (lambda (event)
             (journal-append-event journal event)))
         (*durable-crash-predicate* crash-predicate))
    (run-plan plan registry inputs
              :run-id run-id
              :history history
              :mode mode)))
