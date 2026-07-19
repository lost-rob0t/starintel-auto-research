;;; second-brain.el --- Starintel Org-roam workspace -*- lexical-binding: t; -*-

(require 'org-roam)
(require 'starintel-pages)

(defun starintel-second-brain-root (&optional start)
  (let ((root (locate-dominating-file
               (or start default-directory)
               "AGENTS.md")))
    (unless root
      (error "Cannot locate the Starintel repository root"))
    (file-name-as-directory (file-truename root))))

(defun starintel-second-brain-configure (&optional root autosync)
  "Configure Org-roam for this repository.
When AUTOSYNC is non-nil, enable `org-roam-db-autosync-mode'."
  (interactive (list nil t))
  (let* ((root (or root (starintel-second-brain-root)))
         (cache (expand-file-name ".cache" root)))
    (make-directory cache t)
    (setq org-directory (expand-file-name "roam" root)
          org-roam-directory (file-truename org-directory)
          org-roam-db-location (expand-file-name "org-roam.db" cache)
          org-id-locations-file (expand-file-name "org-id-locations" cache)
          org-roam-completion-everywhere t
          org-roam-capture-templates
          '(("n" "Inbox note" plain "%?"
             :target
             (file+head
              "inbox/%<%Y%m%d%H%M%S>-${slug}.org"
              ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+title: ${title}\n#+description: \n#+filetags: :starintel:inbox:\n#+created: %U\n\n")
             :unnarrowed t)
            ("r" "Research note" plain "%?"
             :target
             (file+head
              "research/inbox/%<%Y%m%d%H%M%S>-${slug}.org"
              ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+title: ${title}\n#+description: \n#+filetags: :starintel:research:draft:\n#+status: DRAFT\n#+created: %U\n\n* Findings\n\n* Sources\n\n* Footnotes and Glossary\n")
             :unnarrowed t)
            ("i" "Index note" plain "%?"
             :target
             (file+head
              "indexes/inbox/%<%Y%m%d%H%M%S>-${slug}.org"
              ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+title: ${title}\n#+description: \n#+filetags: :starintel:index:\n#+created: %U\n\n")
             :unnarrowed t)))
    (when autosync
      (org-roam-db-autosync-mode 1))
    root))

(defun star/roam ()
  "Open an Org-roam node in the repository second brain."
  (interactive)
  (starintel-second-brain-configure nil t)
  (call-interactively #'org-roam-node-find))

(defun star/roam-capture ()
  "Capture a repository Org-roam node."
  (interactive)
  (starintel-second-brain-configure nil t)
  (call-interactively #'org-roam-capture))

(defun star/roam-sync ()
  "Normalize file nodes and rebuild the repository Org-roam database."
  (interactive)
  (let ((root (starintel-second-brain-configure nil nil)))
    (starintel-pages-normalize-source root)
    (org-roam-db-sync)
    (message "Starintel Org-roam database synchronized")))

(defun star/pages-open ()
  "Open the generated site index."
  (interactive)
  (browse-url-of-file
   (expand-file-name "_site/index.html"
                     (starintel-second-brain-root))))

(provide 'starintel-second-brain)
;;; second-brain.el ends here
