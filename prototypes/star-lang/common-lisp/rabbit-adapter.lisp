(in-package #:star-lang.core)

(export '(cl-rabbit-source-adapter
          make-cl-rabbit-source-adapter))

(defclass cl-rabbit-source-adapter (star-lang-source-adapter) ())

(defun make-cl-rabbit-source-adapter ()
  (make-instance 'cl-rabbit-source-adapter))

(defun rabbit-decode-body (body decoder runtime)
  (let ((text (babel:octets-to-string body :encoding :utf-8)))
    (if decoder
        (let ((value (funcall decoder text runtime)))
          (if (listp value) value (list value)))
        (list text))))

(defmethod source-adapter-read ((adapter cl-rabbit-source-adapter)
                                spec runtime &key limit)
  (declare (ignore adapter))
  (unless (and limit (integerp limit) (> limit 0))
    (fail 'execution-error :rabbitmq-limit-required nil
          "RabbitMQ source ~A requires a positive (:LIMIT ...)."
          (source-spec-name spec)))
  (let* ((host (source-option-value spec "host" runtime "localhost"))
         (port (source-option-value spec "port" runtime 5672))
         (vhost (source-option-value spec "vhost" runtime "/"))
         (username (source-option-value spec "username" runtime "guest"))
         (password (source-option-value spec "password" runtime "guest"))
         (queue (source-option-value spec "queue" runtime nil))
         (channel (source-option-value spec "channel" runtime 1))
         (acknowledge (source-option-value spec "ack" runtime t))
         (declare-queue (source-option-value spec "declare" runtime nil))
         (exchange (source-option-value spec "exchange" runtime nil))
         (routing-key (source-option-value spec "routing-key" runtime ""))
         (decoder (source-decoder spec runtime)))
    (unless queue
      (fail 'execution-error :rabbitmq-queue-required nil
            "RabbitMQ source ~A requires (:QUEUE ...)."
            (source-spec-name spec)))
    (cl-rabbit:with-connection (connection)
      (let ((socket (cl-rabbit:tcp-socket-new connection)))
        (cl-rabbit:socket-open socket host port)
        (cl-rabbit:login-sasl-plain connection vhost username password)
        (cl-rabbit:with-channel (connection channel)
          (when declare-queue
            (cl-rabbit:queue-declare connection channel :queue queue))
          (when exchange
            (cl-rabbit:queue-bind connection channel
                                  :queue queue
                                  :exchange exchange
                                  :routing-key routing-key))
          (cl-rabbit:basic-consume connection channel queue)
          (loop repeat limit
                for envelope = (cl-rabbit:consume-message connection)
                for message = (cl-rabbit:envelope/message envelope)
                append
                (prog1
                    (rabbit-decode-body
                     (cl-rabbit:message/body message)
                     decoder
                     runtime)
                  (when acknowledge
                    (cl-rabbit:basic-ack
                     connection
                     channel
                     (cl-rabbit:envelope/delivery-tag envelope))))))))))
