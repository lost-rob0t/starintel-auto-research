(in-package #:star-lang.core-surface.prototype)

(export '(make-file-runtime-journal-port
          make-memory-runtime-journal-port
          make-runtime-journal-port
          runtime-journal-append
          runtime-journal-port-p
          runtime-journal-replay))

(define-condition runtime-journal-error (star-lang-core-error) ())

(defstruct (runtime-journal-port
            (:constructor %make-runtime-journal-port))
  append-fn
  replay-fn)

(defun make-runtime-journal-port (&key append replay)
  (unless (functionp append)
    (fail 'runtime-journal-error
          "Runtime journal append operation must be a function."))
  (unless (functionp replay)
    (fail 'runtime-journal-error
          "Runtime journal replay operation must be a function."))
  (%make-runtime-journal-port
   :append-fn append
   :replay-fn replay))

(defun runtime-journal-event-kind-p (kind)
  (member kind '(:pending :route-result :remote-result) :test #'eq))

(defun validate-runtime-journal-result (event)
  (unless (plist-has-key-p event :result)
    (fail 'runtime-journal-error
          "Settled runtime journal event requires a dispatch result."))
  (let ((result (getf event :result)))
    (ensure-plist
     result
     "runtime journal dispatch result"
     'runtime-journal-error)
    (unless (member (getf result :outcome)
                    '(:complete :retry :fail)
                    :test #'eq)
      (fail 'runtime-journal-error
            "Runtime journal result requires complete, retry, or fail outcome."))
    result))

(defun validate-runtime-journal-event (event)
  (ensure-plist event "runtime journal event" 'runtime-journal-error)
  (let ((kind (getf event :kind))
        (sequence (getf event :dispatcher-sequence))
        (now (getf event :dispatcher-now))
        (command (getf event :command)))
    (unless (runtime-journal-event-kind-p kind)
      (fail 'runtime-journal-error
            "Unknown runtime journal event kind ~S." kind))
    (unless (and (integerp sequence) (>= sequence 0))
      (fail 'runtime-journal-error
            "Runtime journal dispatcher sequence must be a nonnegative integer."))
    (required-nonempty-string now "runtime journal dispatcher clock")
    (validate-lifecycle-envelope nil command :validate-payload nil)
    (unless (eq (getf command :kind) :command)
      (fail 'runtime-journal-error
            "Runtime journal command must be a lifecycle command envelope."))
    (if (eq kind :pending)
        (when (plist-has-key-p event :result)
          (fail 'runtime-journal-error
                "Pending runtime journal event may not carry a result."))
        (validate-runtime-journal-result event))
    event))

(defun validate-runtime-journal-order (events)
  (loop with previous-sequence = nil
        with previous-now = nil
        for event in events
        for sequence = (getf event :dispatcher-sequence)
        for now = (getf event :dispatcher-now)
        do
           (when (and previous-sequence
                      (< sequence previous-sequence))
             (fail 'runtime-journal-error
                   "Runtime journal dispatcher sequence moved backward from ~D to ~D."
                   previous-sequence sequence))
           (when (and previous-now (string< now previous-now))
             (fail 'runtime-journal-error
                   "Runtime journal dispatcher clock moved backward from ~A to ~A."
                   previous-now now))
           (setf previous-sequence sequence
                 previous-now now))
  events)

(defun runtime-journal-append (port event)
  (unless (runtime-journal-port-p port)
    (fail 'runtime-journal-error
          "Runtime journal append requires a journal port."))
  (validate-runtime-journal-event event)
  (handler-case
      (funcall (runtime-journal-port-append-fn port) (copy-tree event))
    (runtime-journal-error (condition)
      (error condition))
    (error (condition)
      (fail 'runtime-journal-error
            "Runtime journal append failed: ~A"
            condition))))

(defun runtime-journal-replay (port)
  (unless (runtime-journal-port-p port)
    (fail 'runtime-journal-error
          "Runtime journal replay requires a journal port."))
  (handler-case
      (let ((events (funcall (runtime-journal-port-replay-fn port))))
        (unless (listp events)
          (fail 'runtime-journal-error
                "Runtime journal replay must return a list."))
        (let ((validated
                (mapcar
                 (lambda (event)
                   (validate-runtime-journal-event event)
                   (copy-tree event))
                 events)))
          (validate-runtime-journal-order validated)
          validated))
    (runtime-journal-error (condition)
      (error condition))
    (error (condition)
      (fail 'runtime-journal-error
            "Runtime journal replay failed: ~A"
            condition))))

(defun make-memory-runtime-journal-port ()
  (let ((events '()))
    (make-runtime-journal-port
     :append
     (lambda (event)
       (setf events (append events (list (copy-tree event))))
       :appended)
     :replay
     (lambda ()
       (copy-tree events)))))

(defun make-file-runtime-journal-port (pathname)
  (let ((path (pathname pathname)))
    (make-runtime-journal-port
     :append
     (lambda (event)
       (ensure-directories-exist path)
       (with-open-file
           (stream path
                   :direction :output
                   :if-exists :append
                   :if-does-not-exist :create)
         (with-standard-io-syntax
           (let ((*print-readably* t)
                 (*print-pretty* nil)
                 (*print-circle* nil))
             (write event :stream stream)
             (terpri stream)
             (finish-output stream))))
       :appended)
     :replay
     (lambda ()
       (if (probe-file path)
           (with-open-file (stream path :direction :input)
             (with-standard-io-syntax
               (let ((*read-eval* nil)
                     (eof (gensym "EOF")))
                 (loop for event = (read stream nil eof)
                       until (eq event eof)
                       collect event))))
           '())))))
