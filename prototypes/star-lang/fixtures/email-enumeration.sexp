((fixture-version 1)
 (workflow email-enumeration)
 (domains ("gmail.com" "outlook.com" "proton.me"))
 (target
  ((type target)
   (persistence persistent)
   (fields
    ((options ((enumeration true)))
     (data
      ((type user)
       (persistence persistent)
       (fields ((username "ada")))))))))
 (actor-results
  (("ada@gmail.com" found)
   ("ada@outlook.com" not-found)
   ("ada@proton.me" found)))
 (expected
  ((candidate-count 3)
   (found-emails ("ada@gmail.com" "ada@proton.me"))
   (persisted-document-types (final-review))
   (persisted-document-count 1))))
