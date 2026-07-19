;;; starintel-auto-research-test.el --- Tests -*- lexical-binding: t; -*-

(require 'ert)

(add-to-list
 'load-path
 (expand-file-name
  "../lisp/starintel"
  (file-name-directory (or load-file-name buffer-file-name))))

(require 'starintel-auto-research)

(ert-deftest star/research-slug-normalizes-text ()
  (should
   (equal (star/research--slug "  StarIntel: Web UI  ")
          "starintel-web-ui")))

(ert-deftest star/research-next-number-scans-existing-files ()
  (let ((directory (make-temp-file "star-research-number-" t)))
    (unwind-protect
        (progn
          (write-region "" nil
                        (expand-file-name "STAR-000-first.org" directory))
          (write-region "" nil
                        (expand-file-name "STAR-004-fifth.org" directory))
          (write-region "" nil
                        (expand-file-name "OTHER-999-ignore.org" directory))
          (should
           (equal (star/research--next-number directory "STAR")
                  "005")))
      (delete-directory directory t))))

(ert-deftest star/research-validates-numbered-design ()
  (let* ((root (make-temp-file "star-research-valid-" t))
         (directory (expand-file-name "roam/design/star" root))
         (file (expand-file-name "STAR-000-valid.org" directory)))
    (unwind-protect
        (progn
          (make-directory directory t)
          (with-temp-file file
            (insert
             "#+title: STAR-000 Valid\n"
             "#+description: Valid design.\n\n"
             "| Version | Date | Description of change | Did nsaspy approve it? |\n\n"
             "* TODO Design File System\n"
             "* TODO Footnotes\n"
             "* TODO Citations\n"))
          (should-not (star/research-validate-file file)))
      (delete-directory root t))))

(ert-deftest star/research-context-bundle-is-bounded ()
  (let* ((root (make-temp-file "star-research-context-" t))
         (star/research-root root)
         (star/research-context-max-bytes 512)
         (source-directory (expand-file-name "roam/research/star" root))
         (source (expand-file-name "STAR-000-source.org" source-directory)))
    (unwind-protect
        (progn
          (make-directory source-directory t)
          (with-temp-file source
            (insert "#+title: Source\n#+description: Test.\n\n")
            (insert (make-string 4096 ?x)))
          (let ((bundle (star/research-build-context-bundle source)))
            (should (file-exists-p bundle))
            (should
             (<= (file-attribute-size (file-attributes bundle))
                 star/research-context-max-bytes))))
      (mapc
       (lambda (buffer)
         (when-let ((file (buffer-file-name buffer)))
           (when (string-prefix-p (file-truename root)
                                  (file-truename file))
             (kill-buffer buffer))))
       (buffer-list))
      (delete-directory root t))))

(provide 'starintel-auto-research-test)

;;; starintel-auto-research-test.el ends here
