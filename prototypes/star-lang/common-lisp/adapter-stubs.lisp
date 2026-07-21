(in-package #:cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (flet ((ensure-package-with-exports (name exports)
           (let ((package (or (find-package name)
                              (make-package name :use '(:cl)))))
             (dolist (export-name exports)
               (export (intern export-name package) package))
             package)))
    (ensure-package-with-exports
     :asys '("MAKE-ACTOR-SYSTEM"))
    (ensure-package-with-exports
     :ac '("ACTOR-OF" "STOP" "SHUTDOWN"))
    (ensure-package-with-exports
     :act '("TELL"))
    (ensure-package-with-exports
     :couchdb-client '("COUCH-REQUEST*"))
    (ensure-package-with-exports
     :babel '("OCTETS-TO-STRING"))
    (ensure-package-with-exports
     :cl-rabbit
     '("WITH-CONNECTION"
       "TCP-SOCKET-NEW"
       "SOCKET-OPEN"
       "LOGIN-SASL-PLAIN"
       "WITH-CHANNEL"
       "QUEUE-DECLARE"
       "QUEUE-BIND"
       "BASIC-CONSUME"
       "CONSUME-MESSAGE"
       "ENVELOPE/MESSAGE"
       "MESSAGE/BODY"
       "BASIC-ACK"
       "ENVELOPE/DELIVERY-TAG"))))

(in-package #:cl-user)

(defparameter *star-lang-sento-stub-calls* '())
(defparameter *star-lang-couch-stub-response* nil)
(defparameter *star-lang-couch-stub-calls* '())
(defparameter *star-lang-rabbit-stub-bodies* '())
(defparameter *star-lang-rabbit-stub-calls* '())
(defparameter *star-lang-rabbit-delivery-tag* 0)

(defun reset-star-lang-adapter-stubs ()
  (setf *star-lang-sento-stub-calls* '()
        *star-lang-couch-stub-response* nil
        *star-lang-couch-stub-calls* '()
        *star-lang-rabbit-stub-bodies* '()
        *star-lang-rabbit-stub-calls* '()
        *star-lang-rabbit-delivery-tag* 0))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (setf
   (symbol-function (find-symbol "MAKE-ACTOR-SYSTEM" :asys))
   (lambda (&optional config)
     (push (list :make-actor-system config) *star-lang-sento-stub-calls*)
     (list :actor-system config))

   (symbol-function (find-symbol "ACTOR-OF" :ac))
   (lambda (context &rest arguments &key name receive state dispatcher queue-size
                    &allow-other-keys)
     (declare (ignore state dispatcher queue-size))
     (let ((actor (list :actor name :context context :receive receive)))
       (push (list :actor-of context arguments) *star-lang-sento-stub-calls*)
       actor))

   (symbol-function (find-symbol "TELL" :act))
   (lambda (actor message &optional sender)
     (declare (ignore sender))
     (push (list :tell actor message) *star-lang-sento-stub-calls*)
     (funcall (getf actor :receive) message))

   (symbol-function (find-symbol "STOP" :ac))
   (lambda (context actor &key wait)
     (push (list :stop context actor wait) *star-lang-sento-stub-calls*)
     t)

   (symbol-function (find-symbol "SHUTDOWN" :ac))
   (lambda (context &key wait)
     (push (list :shutdown context wait) *star-lang-sento-stub-calls*)
     t)

   (symbol-function (find-symbol "COUCH-REQUEST*" :couchdb-client))
   (lambda (method server path &optional keys content-type content)
     (push (list :couch-request method server path keys content-type content)
           *star-lang-couch-stub-calls*)
     *star-lang-couch-stub-response*)

   (symbol-function (find-symbol "OCTETS-TO-STRING" :babel))
   (lambda (octets &key encoding)
     (declare (ignore encoding))
     (coerce (map 'list #'code-char octets) 'string))

   (symbol-function (find-symbol "TCP-SOCKET-NEW" :cl-rabbit))
   (lambda (connection)
     (push (list :tcp-socket-new connection) *star-lang-rabbit-stub-calls*)
     (list :socket connection))

   (symbol-function (find-symbol "SOCKET-OPEN" :cl-rabbit))
   (lambda (socket host port)
     (push (list :socket-open socket host port) *star-lang-rabbit-stub-calls*)
     t)

   (symbol-function (find-symbol "LOGIN-SASL-PLAIN" :cl-rabbit))
   (lambda (connection vhost username password)
     (push (list :login connection vhost username password)
           *star-lang-rabbit-stub-calls*)
     t)

   (symbol-function (find-symbol "QUEUE-DECLARE" :cl-rabbit))
   (lambda (connection channel &key queue)
     (push (list :queue-declare connection channel queue)
           *star-lang-rabbit-stub-calls*)
     queue)

   (symbol-function (find-symbol "QUEUE-BIND" :cl-rabbit))
   (lambda (connection channel &key queue exchange routing-key)
     (push (list :queue-bind connection channel queue exchange routing-key)
           *star-lang-rabbit-stub-calls*)
     t)

   (symbol-function (find-symbol "BASIC-CONSUME" :cl-rabbit))
   (lambda (connection channel queue)
     (push (list :basic-consume connection channel queue)
           *star-lang-rabbit-stub-calls*)
     t)

   (symbol-function (find-symbol "CONSUME-MESSAGE" :cl-rabbit))
   (lambda (connection)
     (declare (ignore connection))
     (let ((body (pop *star-lang-rabbit-stub-bodies*)))
       (incf *star-lang-rabbit-delivery-tag*)
       (list :message (list :body body)
             :delivery-tag *star-lang-rabbit-delivery-tag*)))

   (symbol-function (find-symbol "ENVELOPE/MESSAGE" :cl-rabbit))
   (lambda (envelope)
     (getf envelope :message))

   (symbol-function (find-symbol "MESSAGE/BODY" :cl-rabbit))
   (lambda (message)
     (getf message :body))

   (symbol-function (find-symbol "BASIC-ACK" :cl-rabbit))
   (lambda (connection channel delivery-tag)
     (push (list :basic-ack connection channel delivery-tag)
           *star-lang-rabbit-stub-calls*)
     t)

   (symbol-function (find-symbol "ENVELOPE/DELIVERY-TAG" :cl-rabbit))
   (lambda (envelope)
     (getf envelope :delivery-tag)))

  (setf
   (macro-function (find-symbol "WITH-CONNECTION" :cl-rabbit))
   (lambda (form environment)
     (declare (ignore environment))
     (destructuring-bind (operator (variable) &body body) form
       (declare (ignore operator))
       `(let ((,variable (list :connection)))
          ,@body)))

   (macro-function (find-symbol "WITH-CHANNEL" :cl-rabbit))
   (lambda (form environment)
     (declare (ignore environment))
     (destructuring-bind (operator (connection channel) &body body) form
       (declare (ignore operator connection channel))
       `(progn ,@body)))))
