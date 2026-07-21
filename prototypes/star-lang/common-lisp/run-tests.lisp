(require :asdf)

(let* ((directory (uiop:pathname-directory-pathname *load-truename*))
       (system-file (merge-pathnames "star-lang.asd" directory)))
  (asdf:load-asd system-file)
  (asdf:test-system "star-lang"))
