(define-rabbitmq-source production-documents
  (:host rabbitmq-host)
  (:port rabbitmq-port)
  (:vhost rabbitmq-vhost)
  (:username rabbitmq-username)
  (:password rabbitmq-password)
  (:queue "starintel.documents")
  (:channel 1)
  (:ack true)
  (:decoder 'rabbit-document-decoder))

(load-documents production-documents documents
  (:limit 500)
  (:dataset "production-documents"))
