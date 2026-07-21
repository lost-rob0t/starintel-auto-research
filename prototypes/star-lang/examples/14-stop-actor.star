(define-actor temporary-worker
  (:receive temporary-worker-handler)
  (:queue-size 16))

(start-actor temporary-worker)
(send (actor-ref 'temporary-worker) job)
(stop-actor temporary-worker)
