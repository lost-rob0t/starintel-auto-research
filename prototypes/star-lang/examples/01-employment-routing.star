(define-actor name-to-email
  (:name "name-to-email")
  (:receive name-to-email-handler)
  (:dispatcher :shared)
  (:queue-size 128))

(start-actor name-to-email)

(attach-dataset "flock" *documents*)

(loop for relation in *documents*
      when (and (document-type-p relation 'relation)
                (equal (document-ref relation 'predicate)
                       "employed")
                (equal (document-ref relation 'dest 'org)
                       employer))
        do (send (actor-ref 'name-to-email)
                 (document-ref relation 'source)))
