(define-actor relation-indexer
  (:receive relation-indexer-handler)
  (:dispatcher :shared)
  (:queue-size 1024))

(define-couchdb-source relation-documents
  (:server "http://localhost:5984")
  (:database "relations")
  (:decoder 'couch-document-decoder))

(start-actor relation-indexer)
(load-documents relation-documents relations (:limit 1000))
(loop for relation in relations
      do (send (actor-ref 'relation-indexer) relation))
