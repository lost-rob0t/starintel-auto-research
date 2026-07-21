(define-actor organization-enricher
  (:receive organization-enricher-handler)
  (:queue-size 128))

(start-actor organization-enricher)

(loop for relation in relations
      when (and (document-type-p relation 'relation)
                (equal (document-ref relation 'dest 'country)
                       "US"))
        do (send (actor-ref 'organization-enricher)
                 (document-ref relation 'dest)))
