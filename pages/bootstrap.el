;;; bootstrap.el --- Batch dependency bootstrap for Starintel Pages -*- lexical-binding: t; -*-

(let* ((pages-directory
        (file-name-directory (or load-file-name buffer-file-name)))
       (root (file-name-directory (directory-file-name pages-directory)))
       (cache (expand-file-name ".cache/emacs" root))
       (lisp-directory (expand-file-name "lisp/starintel" root)))
  (setq package-user-dir (expand-file-name "elpa" cache))
  (require 'package)
  (setq package-archives
        '(("gnu" . "https://elpa.gnu.org/packages/")
          ("nongnu" . "https://elpa.nongnu.org/nongnu/")
          ("melpa" . "https://melpa.org/packages/")))
  (package-initialize)
  (unless (and (package-installed-p 'org-roam '(2 3 1))
               (package-installed-p 'htmlize))
    (package-refresh-contents)
    (unless (package-installed-p 'org-roam '(2 3 1))
      (package-install 'org-roam))
    (unless (package-installed-p 'htmlize)
      (package-install 'htmlize)))
  (add-to-list 'load-path lisp-directory)
  (load (expand-file-name "second-brain.el" lisp-directory) nil nil t)
  (load (expand-file-name "pages-metadata.el" lisp-directory) nil nil t)

  ;; Org-roam may omit a valid file-level ID from its node table while
  ;; `org-id' still resolves it. Keep Pages strict about genuinely broken
  ;; links, but export valid file or heading IDs through the authoritative
  ;; Org ID location index when the node lookup misses.
  (defun starintel-pages--export-id-link (path description backend info)
    (when (eq backend 'html)
      (let* ((node (org-roam-node-from-id path))
             (current-file (plist-get info :input-file))
             (current-output
              (starintel-pages--note-output-file current-file)))
        (if node
            (let ((href (starintel-pages--node-output-href
                         node current-output))
                  (label (or description
                             (org-html-encode-plain-text
                              (starintel-pages--node-label node)))))
              (format "<a href=\"%s\">%s</a>" href label))
          (let ((marker (org-id-find path 'marker)))
            (unless marker
              (error "Unresolved Org ID link: %s" path))
            (unwind-protect
                (let* ((target-buffer (marker-buffer marker))
                       (target-file (buffer-file-name target-buffer))
                       (heading-p
                        (with-current-buffer target-buffer
                          (save-excursion
                            (goto-char marker)
                            (org-at-heading-p))))
                       (target-output
                        (starintel-pages--note-output-file target-file))
                       (href
                        (starintel-pages--href-between
                         current-output target-output
                         (and heading-p path)))
                       (fallback-label
                        (with-current-buffer target-buffer
                          (save-excursion
                            (goto-char marker)
                            (if heading-p
                                (org-get-heading t t t t)
                              (or (starintel-pages--keyword
                                   target-file "TITLE")
                                  path)))))
                       (label
                        (or description
                            (org-html-encode-plain-text fallback-label))))
                  (format "<a href=\"%s\">%s</a>" href label))
              (set-marker marker nil)))))))

  (starintel-second-brain-configure root nil)
  (starintel-pages-build root))

;;; bootstrap.el ends here
