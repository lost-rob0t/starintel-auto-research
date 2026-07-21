(in-package #:star-lang.core)

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
                    (when (typep cause 'simulated-runtime-crash)
                      (error cause))
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
