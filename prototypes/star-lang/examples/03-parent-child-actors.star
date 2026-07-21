(define-actor collection-supervisor
  (:receive collection-supervisor-handler)
  (:dispatcher :pinned))

(define-actor profile-worker
  (:receive profile-worker-handler)
  (:parent 'collection-supervisor)
  (:dispatcher :shared)
  (:queue-size 64))

(start-actor collection-supervisor)
(start-actor profile-worker)
(send (actor-ref 'profile-worker) target)
