(define-actor document-auditor
  (:name "document-auditor")
  (:receive audit-document-handler)
  (:state nil)
  (:dispatcher :shared)
  (:queue-size 256))

(start-actor document-auditor)
(send (actor-ref 'document-auditor) document)
