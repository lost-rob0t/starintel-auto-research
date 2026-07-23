(in-package #:star-lang.core-surface.prototype)

(export '(advance-fake-transport-clock
          bind-fake-transport-port
          fake-transport-dead-letters
          fake-transport-inbound
          fake-transport-in-flight
          fake-transport-published
          fake-transport-settlements
          fake-transport-submit
          make-fake-transport
          make-transport-port
          transport-ack
          transport-delivery-envelope
          transport-delivery-redelivery-count
          transport-delivery-tag
          transport-now
          transport-publish
          transport-receive
          transport-reject
          transport-requeue))

(define-condition transport-port-error (star-lang-error) ())

(defstruct (transport-delivery (:constructor %make-transport-delivery))
  tag
  envelope
  (redelivery-count 0)
  (visible-at 0))

(defstruct (transport-port (:constructor %make-transport-port))
  name
  receive-fn
  publish-fn
  ack-fn
  requeue-fn
  reject-fn
  now-fn)

(defun make-transport-port (&key name receive publish ack requeue reject now)
  (dolist (entry (list (cons "receive" receive)
                       (cons "publish" publish)
                       (cons "ack" ack)
                       (cons "requeue" requeue)
                       (cons "reject" reject)
                       (cons "now" now)))
    (unless (functionp (cdr entry))
      (fail 'transport-port-error
            "Transport port ~A operation must be a function."
            (car entry))))
  (%make-transport-port
   :name (or name "transport")
   :receive-fn receive
   :publish-fn publish
   :ack-fn ack
   :requeue-fn requeue
   :reject-fn reject
   :now-fn now))

(defun transport-receive (port)
  (funcall (transport-port-receive-fn port)))

(defun transport-publish (port envelope)
  (funcall (transport-port-publish-fn port) envelope))

(defun transport-ack (port delivery)
  (funcall (transport-port-ack-fn port) delivery))

(defun transport-requeue (port delivery replacement-envelope delay-ms)
  (funcall (transport-port-requeue-fn port)
           delivery replacement-envelope delay-ms))

(defun transport-reject (port delivery reason)
  (funcall (transport-port-reject-fn port) delivery reason))

(defun transport-now (port)
  (funcall (transport-port-now-fn port)))

(defstruct (fake-transport (:constructor %make-fake-transport))
  (inbound '())
  (in-flight (make-hash-table :test #'equal))
  (published '())
  (settlements '())
  (dead-letters '())
  (sequence 0)
  (now 0)
  (publish-failures-remaining 0))

(defun make-fake-transport (&key (now 0) (publish-failures 0))
  (unless (and (integerp now) (>= now 0))
    (fail 'transport-port-error "Fake transport clock must be a nonnegative integer."))
  (unless (and (integerp publish-failures) (>= publish-failures 0))
    (fail 'transport-port-error
          "Fake transport publish failure count must be nonnegative."))
  (%make-fake-transport :now now
                        :publish-failures-remaining publish-failures))

(defun fake-transport-next-tag (transport)
  (incf (fake-transport-sequence transport))
  (format nil "delivery-~6,'0D" (fake-transport-sequence transport)))

(defun fake-transport-submit (transport envelope &key
                                                   (visible-at
                                                    (fake-transport-now transport))
                                                   (redelivery-count 0))
  (unless (and (integerp visible-at) (>= visible-at 0))
    (fail 'transport-port-error "Delivery visibility must be nonnegative."))
  (let ((delivery
          (%make-transport-delivery
           :tag (fake-transport-next-tag transport)
           :envelope (copy-tree envelope)
           :redelivery-count redelivery-count
           :visible-at visible-at)))
    (setf (fake-transport-inbound transport)
          (append (fake-transport-inbound transport) (list delivery)))
    delivery))

(defun advance-fake-transport-clock (transport now)
  (unless (and (integerp now) (>= now (fake-transport-now transport)))
    (fail 'transport-port-error
          "Fake transport clock cannot move backward."))
  (setf (fake-transport-now transport) now)
  now)

(defun fake-transport-visible-p (transport delivery)
  (<= (transport-delivery-visible-at delivery)
      (fake-transport-now transport)))

(defun fake-transport-receive-internal (transport)
  (let ((delivery
          (find-if (lambda (candidate)
                     (fake-transport-visible-p transport candidate))
                   (fake-transport-inbound transport))))
    (when delivery
      (setf (fake-transport-inbound transport)
            (delete delivery
                    (fake-transport-inbound transport)
                    :test #'eq
                    :count 1))
      (setf (gethash (transport-delivery-tag delivery)
                     (fake-transport-in-flight transport))
            delivery)
      delivery)))

(defun require-in-flight-delivery (transport delivery)
  (let ((stored
          (gethash (transport-delivery-tag delivery)
                   (fake-transport-in-flight transport))))
    (unless (eq stored delivery)
      (fail 'transport-port-error
            "Delivery ~A is not in flight."
            (transport-delivery-tag delivery)))
    stored))

(defun record-fake-settlement (transport delivery action &rest details)
  (setf (fake-transport-settlements transport)
        (append
         (fake-transport-settlements transport)
         (list (list* :delivery-tag (transport-delivery-tag delivery)
                      :action action
                      details)))))

(defun fake-transport-publish-internal (transport envelope)
  (when (> (fake-transport-publish-failures-remaining transport) 0)
    (decf (fake-transport-publish-failures-remaining transport))
    (fail 'transport-port-error "Injected fake transport publish failure."))
  (setf (fake-transport-published transport)
        (append (fake-transport-published transport)
                (list (copy-tree envelope))))
  envelope)

(defun fake-transport-ack-internal (transport delivery)
  (require-in-flight-delivery transport delivery)
  (remhash (transport-delivery-tag delivery)
           (fake-transport-in-flight transport))
  (record-fake-settlement transport delivery :ack)
  :ack)

(defun fake-transport-requeue-internal
    (transport delivery replacement-envelope delay-ms)
  (require-in-flight-delivery transport delivery)
  (unless (and (integerp delay-ms) (>= delay-ms 0))
    (fail 'transport-port-error "Requeue delay must be nonnegative."))
  (remhash (transport-delivery-tag delivery)
           (fake-transport-in-flight transport))
  (record-fake-settlement transport delivery :requeue :delay-ms delay-ms)
  (fake-transport-submit
   transport
   replacement-envelope
   :visible-at (+ (fake-transport-now transport) delay-ms)
   :redelivery-count (1+ (transport-delivery-redelivery-count delivery))))

(defun fake-transport-reject-internal (transport delivery reason)
  (require-in-flight-delivery transport delivery)
  (remhash (transport-delivery-tag delivery)
           (fake-transport-in-flight transport))
  (record-fake-settlement transport delivery :reject :reason reason)
  (setf (fake-transport-dead-letters transport)
        (append (fake-transport-dead-letters transport)
                (list (list :delivery delivery :reason reason))))
  :reject)

(defun bind-fake-transport-port (transport)
  (make-transport-port
   :name "fake-at-least-once"
   :receive (lambda () (fake-transport-receive-internal transport))
   :publish (lambda (envelope)
              (fake-transport-publish-internal transport envelope))
   :ack (lambda (delivery)
          (fake-transport-ack-internal transport delivery))
   :requeue (lambda (delivery replacement-envelope delay-ms)
              (fake-transport-requeue-internal
               transport delivery replacement-envelope delay-ms))
   :reject (lambda (delivery reason)
             (fake-transport-reject-internal transport delivery reason))
   :now (lambda () (fake-transport-now transport))))
