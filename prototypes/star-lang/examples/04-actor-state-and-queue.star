(define-actor bounded-enricher
  (:name "bounded-enricher")
  (:receive enrichment-handler)
  (:state initial-state)
  (:dispatcher :pinned)
  (:queue-size 32))

(start-actor bounded-enricher)
(loop for document in documents
      do (send (actor-ref 'bounded-enricher) document))
