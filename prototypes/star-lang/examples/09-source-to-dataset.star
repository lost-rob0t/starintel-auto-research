(define-couchdb-source case-documents
  (:server "http://localhost:5984")
  (:database "cases")
  (:decoder 'couch-document-decoder))

(load-documents case-documents documents
  (:limit 200)
  (:dataset "case-documents"))

(attach-dataset "current-case" documents)
