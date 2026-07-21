(define-actor document-normalizer
  (:receive normalize-document-handler)
  (:queue-size 512))

(define-rabbitmq-source raw-documents
  (:host "localhost")
  (:port 5672)
  (:vhost "/")
  (:queue "starintel.raw")
  (:channel 2)
  (:ack true)
  (:decoder 'rabbit-document-decoder))

(start-actor document-normalizer)
(load-documents raw-documents raw-documents-list (:limit 250))
(loop for document in raw-documents-list
      do (send (actor-ref 'document-normalizer) document))
