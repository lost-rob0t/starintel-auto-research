(define-message relation-message
  (:schema 'relation))

(define-supervisor collection-supervisor
  (:strategy :one-for-one)
  (:max-restarts 3)
  (:on-exhausted :escalate))

(define-actor relation-worker
  (:receive relation-worker-handler)
  (:accepts (list 'relation-message))
  (:supervisor 'collection-supervisor)
  (:restart :permanent)
  (:queue-size 128))

(start-actor relation-worker)

(loop for relation in relations
      when (document-type-p relation 'relation)
      do (send (actor-ref 'relation-worker) relation))
