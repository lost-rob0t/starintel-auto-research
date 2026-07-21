(set people (dataset "flock"))

(loop for person in people
      when (document-type-p person 'person)
      collect (document-ref person 'email))
