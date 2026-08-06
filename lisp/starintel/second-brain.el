;;; second-brain.el --- Starintel Org-roam workspace -*- lexical-binding: t; -*-

(require 'org-roam)

(unless (featurep 'starintel-pages)
  (load (expand-file-name
         "pages.el"
         (file-name-directory (or load-file-name buffer-file-name)))
        nil nil t))

(defun starintel-second-brain-root (&optional start)
  (let ((root (locate-dominating-file
               (or start default-directory)
               "AGENTS.md")))
    (unless root
      (error "Cannot locate the Starintel repository root"))
    (file-name-as-directory (file-truename root))))

(defconst starintel-second-brain-research-approval-template
  "* Approval Table\n\n| Approval area | Required authority | State | Evidence required | Evidence reference |\n|---------------+--------------------+-------+-------------------+--------------------|\n| Research basis | Research reviewer | PENDING | Current primary-source verification | |\n| Architecture | Project maintainer | PENDING | Resolved design implications and contradictions | |\n| Security | Security reviewer | PENDING | Authorization, disclosure, and secret-handling review | |\n| Operations | Operator | PENDING | Operational policy, budgets, monitoring, and rollback review | |\n| Implementation | Repository maintainer | NOT STARTED | Passing implementation, CI, and publication checks | |\n\n")

(defconst starintel-second-brain-index-approval-template
  "* Approval Table\n\n| Approval area | Required authority | State | Evidence required | Evidence reference |\n|---------------+--------------------+-------+-------------------+--------------------|\n| Scope and coverage | Project maintainer | PENDING | Canonical direct-child inventory and research-gap review | |\n| Durable links | Org-roam reviewer | PENDING | Unique IDs and resolved canonical links | |\n| Supersession | Project maintainer | PENDING | Replacements and implementation order verified | |\n| Publication | Repository maintainer | NOT STARTED | Passing synchronization, generation, and link validation | |\n\n")

(defun starintel-second-brain-research-head ()
  "Return the canonical header and structure for a new research node."
  (concat
   ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n"
   "#+title: ${title}\n"
   "#+description: \n"
   "#+status: DRAFT\n"
   "#+filetags: :starintel:research:draft:\n"
   "#+created: %U\n\n"
   starintel-second-brain-research-approval-template
   "* Findings\n\n"
   "* Sources\n\n"
   "* Footnotes and Glossary\n\n"
   "* Changelog\n\n"
   "| Date | Change | Author or actor | Evidence |\n"
   "|------+--------+-----------------+----------|\n"
   "| %<%Y-%m-%d> | Created research node | Org-roam capture | Initial capture |\n"))

(defun starintel-second-brain-index-head ()
  "Return the canonical header and structure for a new index node."
  (concat
   ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n"
   "#+title: ${title}\n"
   "#+description: \n"
   "#+status: DRAFT\n"
   "#+filetags: :starintel:index:\n"
   "#+created: %U\n\n"
   starintel-second-brain-index-approval-template
   "* Scope\n\n"
   "* Canonical Documents\n\n"
   "* Research Gaps\n\n"
   "* Footnotes and Glossary\n\n"
   "* Changelog\n\n"
   "| Date | Change | Author or actor | Evidence |\n"
   "|------+--------+-----------------+----------|\n"
   "| %<%Y-%m-%d> | Created index node | Org-roam capture | Initial capture |\n"))

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
          starintel-pages-site-title
          "Starintel Second Brain — Entirely built and managed by AI agents"
          org-roam-capture-templates
          `(("n" "Inbox note" plain "%?"
             :target
             (file+head
              "inbox/%<%Y%m%d%H%M%S>-${slug}.org"
              ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+title: ${title}\n#+description: \n#+filetags: :starintel:inbox:\n#+created: %U\n\n")
             :unnarrowed t)
            ("r" "Research note" plain "%?"
             :target
             (file+head
              "research/inbox/%<%Y%m%d%H%M%S>-${slug}.org"
              ,(starintel-second-brain-research-head))
             :unnarrowed t)
            ("i" "Index note" plain "%?"
             :target
             (file+head
              "indexes/inbox/%<%Y%m%d%H%M%S>-${slug}.org"
              ,(starintel-second-brain-index-head))
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
(provide 'second-brain)
;;; second-brain.el ends here
