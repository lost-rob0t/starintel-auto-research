(loop for relation in relations
      when (equal (document-ref relation 'predicate) "alias")
      append (list (document-ref relation 'source)
                   (document-ref relation 'dest)))
