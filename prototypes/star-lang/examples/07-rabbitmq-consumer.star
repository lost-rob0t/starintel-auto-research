(define-rabbitmq-source flock-queue
  (:host "localhost")
  (:port 5672)
  (:vhost "/")
  (:username "guest")
  (:password "guest")
  (:queue "flock.documents")
  (:channel 1)
  (:ack true)
  (:decoder 'rabbit-document-decoder))

(load-documents flock-queue *documents*
  (:limit 100)
  (:dataset "flock-events"))
