(attach-dataset "people" people)
(attach-dataset "relations" relations)
(attach-dataset "organizations" organizations)

(set all-documents
     (list (dataset "people")
           (dataset "relations")
           (dataset "organizations")))
