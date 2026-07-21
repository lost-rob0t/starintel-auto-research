(define-supervisor enrichment-supervisor
  (:strategy :one-for-one)
  (:max-restarts 5)
  (:on-exhausted :stop))

(define-actor enrichment-worker
  (:receive enrichment-handler)
  (:supervisor 'enrichment-supervisor)
  (:restart :transient)
  (:dispatcher :pinned)
  (:queue-size 256))

(start-actor enrichment-worker)

(loop for document in documents
      do (send (actor-ref 'enrichment-worker) document))
