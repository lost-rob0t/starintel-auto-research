(in-package #:star-lang.core-surface.prototype)

(defparameter +bbp-journal-restart-path+
  #p"bbp-journal-restart.sexp")

(defun journal-restart-write-marker (pathname value)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-line value stream)
    (finish-output stream)))

(defun journal-restart-read-marker (pathname)
  (with-open-file (stream pathname :direction :input)
    (or (read-line stream nil nil)
        (error "Marker ~A is empty." pathname))))

(defun journal-restart-wait-until
    (predicate label &key (attempts 400) (sleep-seconds 0.05))
  (loop repeat attempts
        when (funcall predicate)
          return t
        do (sleep sleep-seconds)
        finally (error "Timed out waiting for ~A." label)))

(defun journal-restart-await-terminal (runtime label)
  (let ((envelopes '()))
    (journal-restart-wait-until
     (lambda ()
       (setf envelopes
             (append envelopes
                     (drain-bbp-main-results runtime)))
       (some
        (lambda (envelope)
          (member (getf envelope :kind)
                  '(:reply :error)
                  :test #'eq))
        envelopes))
     label)
    envelopes))

(defun journal-restart-envelope (envelopes kind)
  (or (find kind envelopes
            :key (lambda (envelope) (getf envelope :kind)))
      (error "Expected ~S envelope, received ~S."
             kind envelopes)))

(defun journal-restart-submit-deferred (runtime command label)
  (unless (eq :deferred
              (submit-bbp-main-command runtime command))
    (error "~A did not defer to the BBP worker." label))
  (journal-restart-await-terminal runtime label))

(defun journal-restart-register-command ()
  (make-bbp-register-program-command
   :message-id "journal-restart-register"
   :program-id "program:journal-restart"
   :name "Journal Restart"
   :scope '("example.com")))

(defun journal-restart-tool-command ()
  (make-bbp-run-tool-command
   :message-id "journal-restart-tool"
   :program-id "program:journal-restart"
   :run-id "run:journal-restart:1"
   :tool 'subfinder
   :target "api.example.com"))
