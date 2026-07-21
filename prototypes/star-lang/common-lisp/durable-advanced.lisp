(in-package #:star-lang.core)

(export '(chained-memory-journal
          command-dispatch-failed
          command-dispatch-failed-attempt
          command-dispatch-failed-capability
          command-dispatch-failed-cause
          command-dispatch-failed-command-id
          command-dispatch-failed-input
          journal-entry
          journal-entry-event
          journal-entry-hash
          journal-entry-previous-hash
          journal-read-entries
          make-chained-memory-journal
          make-run-checkpoint
          verify-journal-integrity))

(define-condition command-dispatch-failed (execution-error)
  ((command-id
    :initarg :command-id
    :reader command-dispatch-failed-command-id)
   (capability
    :initarg :capability
    :reader command-dispatch-failed-capability)
   (input
    :initarg :input
    :reader command-dispatch-failed-input)
   (cause
    :initarg :cause
    :reader command-dispatch-failed-cause)
   (attempt
    :initarg :attempt
    :reader command-dispatch-failed-attempt)))

(defparameter *command-retry-limit* 8)

(defun signal-command-dispatch-failed (identifier capability input cause attempt)
  (error 'command-dispatch-failed
         :code :command-dispatch-failed
         :span nil
         :message
         (format nil "Capability ~A failed for command ~A on attempt ~D: ~A"
                 (capability-definition-name capability)
                 identifier
                 attempt
                 cause)
         :command-id identifier
         :capability (capability-definition-name capability)
         :input input
         :cause cause
         :attempt attempt))

(defun record-command-result (runtime run-id plan node identifier result replayed)
  (record-run-event
   runtime :command-result run-id plan (plan-node-id node)
   (list :command-id identifier
         :result result
         :replayed replayed))
  result)

(defun dispatch-live-capability (runtime capability input run-id plan node identifier)
  (labels
      ((attempt-dispatch (attempt)
         (when (> attempt *command-retry-limit*)
           (fail 'execution-error :command-retry-limit-exceeded
                 (plan-node-source-span node)
                 "Command ~A exceeded retry limit ~D."
                 identifier *command-retry-limit*))
         (incf (core-runtime-dispatch-count runtime))
         (record-run-event
          runtime :command-attempted run-id plan (plan-node-id node)
          (list :command-id identifier :attempt attempt))
         (let ((previous (core-runtime-current-capability runtime)))
           (unwind-protect
                (handler-case
                    (progn
                      (setf (core-runtime-current-capability runtime) capability)
                      (record-command-result
                       runtime run-id plan node identifier
                       (funcall (capability-definition-function capability)
                                input runtime)
                       nil))
                  (error (cause)
                    (record-run-event
                     runtime :command-failed run-id plan (plan-node-id node)
                     (list :command-id identifier
                           :attempt attempt
                           :condition-type (type-of cause)
                           :message (princ-to-string cause)))
                    (restart-case
                        (signal-command-dispatch-failed
                         identifier capability input cause attempt)
                      (retry-command ()
                        :report "Retry the failed command."
                        (record-run-event
                         runtime :restart-selected run-id plan
                         (plan-node-id node)
                         (list :command-id identifier
                               :restart :retry-command
                               :attempt attempt))
                        (attempt-dispatch (1+ attempt)))
                      (use-command-value (value)
                        :report "Supply a replacement command result."
                        :interactive
                        (lambda ()
                          (format *query-io* "Replacement result: ")
                          (list (read *query-io*)))
                        (record-run-event
                         runtime :restart-selected run-id plan
                         (plan-node-id node)
                         (list :command-id identifier
                               :restart :use-command-value
                               :attempt attempt))
                        (record-command-result
                         runtime run-id plan node identifier value nil))
                      (skip-command ()
                        :report "Skip this command and return NIL."
                        (record-run-event
                         runtime :restart-selected run-id plan
                         (plan-node-id node)
                         (list :command-id identifier
                               :restart :skip-command
                               :attempt attempt))
                        (record-command-result
                         runtime run-id plan node identifier nil nil))
                      (abort-run ()
                        :report "Abort the current Star-Lang run."
                        (error cause)))))
             (setf (core-runtime-current-capability runtime) previous)))))
    (attempt-dispatch 1)))

(defun invoke-effect-capability (runtime capability input run-id plan node mode)
  (let ((identifier (command-id run-id plan node input)))
    (multiple-value-bind (recorded present-p)
        (gethash identifier (core-runtime-replay-results runtime))
      (record-run-event
       runtime :command-created run-id plan (plan-node-id node)
       (list :command-id identifier
             :capability (capability-definition-name capability)
             :input-hash (sha256-string (canonical-value input))))
      (case mode
        (:replay
         (unless present-p
           (fail 'replay-error :missing-command-result
                 (plan-node-source-span node)
                 "Replay has no result for command ~A." identifier))
         (record-command-result
          runtime run-id plan node identifier recorded t))
        (:resume
         (if present-p
             (record-command-result
              runtime run-id plan node identifier recorded t)
             (dispatch-live-capability
              runtime capability input run-id plan node identifier)))
        (:live
         (dispatch-live-capability
          runtime capability input run-id plan node identifier))
        (otherwise
         (fail 'execution-error :invalid-run-mode nil
               "Unknown run mode ~S." mode))))))

(defstruct journal-entry
  event
  previous-hash
  hash)

(defclass chained-memory-journal (durable-journal)
  ((entries-by-run
    :initform (make-hash-table :test #'equal)
    :reader chained-journal-entries-by-run)))

(defun make-chained-memory-journal ()
  (make-instance 'chained-memory-journal))

(defun journal-genesis-hash ()
  (make-string 64 :initial-element #\0))

(defun journal-entry-digest (previous-hash event)
  (sha256-string
   (canonical-value
    (list previous-hash (event-signature event)))))

(defmethod journal-append-event ((journal chained-memory-journal) event)
  (let* ((run-id (run-event-run-id event))
         (entries
           (gethash run-id (chained-journal-entries-by-run journal)))
         (expected-sequence (1+ (length entries))))
    (unless (= expected-sequence (run-event-sequence event))
      (fail 'replay-error :invalid-event-sequence nil
            "Run ~A expected event sequence ~D, received ~D."
            run-id expected-sequence (run-event-sequence event)))
    (let* ((previous-hash
             (if entries
                 (journal-entry-hash (car (last entries)))
                 (journal-genesis-hash)))
           (entry
             (make-journal-entry
              :event event
              :previous-hash previous-hash
              :hash (journal-entry-digest previous-hash event))))
      (setf (gethash run-id (chained-journal-entries-by-run journal))
            (append entries (list entry)))
      event)))

(defmethod journal-read-events ((journal chained-memory-journal) run-id)
  (mapcar #'journal-entry-event
          (journal-read-entries journal run-id)))

(defun journal-read-entries (journal run-id)
  (copy-list
   (or (gethash run-id (chained-journal-entries-by-run journal)) '())))

(defun verify-journal-integrity (journal run-id)
  (let ((expected-previous (journal-genesis-hash))
        (expected-sequence 1))
    (dolist (entry (journal-read-entries journal run-id) t)
      (let ((event (journal-entry-event entry)))
        (unless (= expected-sequence (run-event-sequence event))
          (fail 'replay-error :journal-integrity-failure nil
                "Run ~A has event sequence ~D where ~D was expected."
                run-id (run-event-sequence event) expected-sequence))
        (unless (string= expected-previous
                         (journal-entry-previous-hash entry))
          (fail 'replay-error :journal-integrity-failure nil
                "Run ~A has a broken previous-hash link at event ~D."
                run-id expected-sequence))
        (let ((expected-hash
                (journal-entry-digest expected-previous event)))
          (unless (string= expected-hash (journal-entry-hash entry))
            (fail 'replay-error :journal-integrity-failure nil
                  "Run ~A has a corrupt event hash at event ~D."
                  run-id expected-sequence))
          (setf expected-previous expected-hash)))
      (incf expected-sequence))))
