(define-couchdb-source employed-relations
  (:server "http://localhost:5984")
  (:path (list "flock" "_design" "relations" "_view" "by-predicate"))
  (:keys (list :key "employed" :include_docs true))
  (:decoder 'couch-view-row-decoder))

(load-documents employed-relations relations
  (:limit 1000)
  (:dataset "employed-relations"))
