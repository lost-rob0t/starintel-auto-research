(define-couchdb-source flock-couch
  (:server "http://localhost:5984")
  (:database "flock")
  (:path (list "flock" "_all_docs"))
  (:keys (list :include_docs true))
  (:decoder 'couch-document-decoder))

(load-documents flock-couch *documents*
  (:limit 500)
  (:dataset "flock"))
