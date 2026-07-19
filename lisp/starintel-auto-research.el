;;; starintel-auto-research.el --- Emacs-first Starintel research workflow -*- lexical-binding: t; -*-

;; Copyright (C) 2026 lost-rob0t
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "29.1") (org "9.6"))
;; Keywords: outlines, tools
;; Version: 0.1.0

;;; Commentary:

;; Org-roam, Org-ql, validation, bounded agent context, Git helpers, and graph
;; export for the Starintel auto-research repository.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'org)
(require 'org-element)
(require 'org-id)
(require 'seq)
(require 'subr-x)

(defgroup starintel-auto-research nil
  "Emacs-first Starintel research workflow."
  :group 'org)

(defcustom star/research-root nil
  "Repository root.
When nil, resolve from STARINTEL_RESEARCH_ROOT, the current file, or
`default-directory'."
  :type '(choice (const :tag "Auto-detect" nil) directory))

(defcustom star/research-context-max-bytes (* 256 1024)
  "Maximum size of a generated agent context bundle."
  :type 'integer)

(defcustom star/research-git-program "git"
  "Git executable used by workflow commands."
  :type 'string)

(defcustom star/research-desktop-command '("starintel-graph")
  "Command used to launch the desktop graph IDE."
  :type '(repeat string))

(defconst star/research-required-design-headings
  '("Design File System" "Footnotes" "Citations"))

(defconst star/research-directories
  '("roam/design"
    "roam/research"
    "roam/implement"
    "roam/indexes"
    ".starintel/context"
    "ui/web"
    "ui/desktop"))

(defvar star/research-prefix-map (make-sparse-keymap))
(defvar star/research-link-prefix-map (make-sparse-keymap))
(defvar star/research-query-prefix-map (make-sparse-keymap))
(defvar star/research-git-prefix-map (make-sparse-keymap))
(defvar star/research-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c s") star/research-prefix-map)
    map))

(defun star/research--discover-root ()
  "Return the repository root."
  (or star/research-root
      (getenv "STARINTEL_RESEARCH_ROOT")
      (when-let* ((file (or buffer-file-name default-directory)))
        (locate-dominating-file file ".git"))
      default-directory))

(defun star/research--root ()
  "Return the normalized repository root."
  (file-name-as-directory
   (file-truename (expand-file-name (star/research--discover-root)))))

(defun star/research--path (&rest parts)
  "Return PARTS below the repository root."
  (expand-file-name (string-join parts "/") (star/research--root)))

(defun star/research--roam-root ()
  "Return the Org-roam root."
  (star/research--path "roam"))

(defun star/research--org-files ()
  "Return every Org file in the repository Roam tree."
  (when (file-directory-p (star/research--roam-root))
    (directory-files-recursively (star/research--roam-root) "\\.org\\'")))

(defun star/research--slug (text)
  "Convert TEXT to a stable filename slug."
  (let ((slug (downcase (string-trim text))))
    (setq slug (replace-regexp-in-string "[^[:alnum:]]+" "-" slug))
    (replace-regexp-in-string "\\`-\\|-\\'" "" slug)))

(defun star/research--project-prefix (project)
  "Return the uppercase filename prefix for PROJECT."
  (upcase
   (replace-regexp-in-string
    "[^[:alnum:]]+" "-"
    (string-trim project))))

(defun star/research--next-number (directory prefix)
  "Return the next three-digit number in DIRECTORY for PREFIX."
  (let ((max-number -1)
        (regexp (format "\\`%s-\\([0-9]\\{3\\}\\)-"
                        (regexp-quote prefix))))
    (when (file-directory-p directory)
      (dolist (file (directory-files directory nil "\\.org\\'"))
        (when (string-match regexp file)
          (setq max-number
                (max max-number
                     (string-to-number (match-string 1 file)))))))
    (format "%03d" (1+ max-number))))

(defun star/research--timestamp ()
  "Return an inactive Org timestamp."
  (format-time-string "[%Y-%m-%d %a %H:%M]"))

(defun star/research--write-file (file content)
  "Write CONTENT to FILE and return FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file
    (insert content))
  file)

(defun star/research--document-content
    (identifier title description project kind)
  "Build an Org document for IDENTIFIER, TITLE, DESCRIPTION, PROJECT and KIND."
  (format
   (concat "#+title: %s %s\n"
           "#+description: %s\n"
           "#+filetags: :starintel:%s:\n"
           "#+todo: TODO RESEARCHING REVIEW BLOCKED | DONE REJECTED\n\n"
           ":PROPERTIES:\n"
           ":ID: %s\n"
           ":PROJECT: %s\n"
           ":KIND: %s\n"
           ":STATUS: TODO\n"
           ":CREATED: %s\n"
           ":LAST_REVIEWED:\n"
           ":SOURCE_COUNT: 0\n"
           ":REPOSITORIES:\n"
           ":DESIGN_FILES:\n"
           ":IMPLEMENTATION_ISSUES:\n"
           ":END:\n\n"
           "| Version | Date | Description of change | Did nsaspy approve it? |\n"
           "|---------+------+-----------------------+------------------------|\n"
           "| 0.1.0   | %s | Initial document      |                        |\n\n"
           "* TODO Objective\n\n"
           "* TODO Current Findings\n\n"
           "* TODO Design File System\n\n"
           "* TODO Open Questions\n\n"
           "* TODO Implementation Tasks\n\n"
           "* TODO Footnotes\n\n"
           "* TODO Citations\n")
   identifier
   title
   description
   (downcase (star/research--project-prefix project))
   (org-id-new)
   project
   kind
   (star/research--timestamp)
   (format-time-string "%Y-%m-%d")))

(defun star/research-setup ()
  "Create repository directories and configure Org-roam."
  (interactive)
  (dolist (directory star/research-directories)
    (make-directory (star/research--path directory) t))
  (setq org-roam-directory (file-truename (star/research--roam-root)))
  (setq org-id-locations-file
        (star/research--path ".starintel" "org-id-locations"))
  (when (require 'org-roam nil t)
    (setq org-roam-db-location
          (star/research--path ".starintel" "org-roam.db"))
    (star/research-install-capture-templates)
    (org-roam-db-autosync-mode 1))
  (message "Starintel research root: %s" (star/research--root)))

(defun star/research--new-document (area project title description)
  "Create a numbered document in AREA for PROJECT, TITLE and DESCRIPTION."
  (star/research-setup)
  (let* ((prefix (if (string= area "srfc")
                     "SRFC"
                   (star/research--project-prefix project)))
         (directory (if (string= area "srfc")
                        (star/research--path "roam" "design" "srfc")
                      (star/research--path "roam" area
                                           (star/research--slug project))))
         (number (star/research--next-number directory prefix))
         (identifier (format "%s-%s" prefix number))
         (file (expand-file-name
                (format "%s-%s.org" identifier (star/research--slug title))
                directory)))
    (star/research--write-file
     file
     (star/research--document-content
      identifier title description project (upcase area)))
    (when (require 'org-roam nil t)
      (org-roam-db-sync))
    (find-file file)
    file))

(defun star/research-new-design (project title description)
  "Create a numbered design file for PROJECT, TITLE and DESCRIPTION."
  (interactive
   (list (read-string "Project: ")
         (read-string "Title: ")
         (read-string "Description: ")))
  (star/research--new-document "design" project title description))

(defun star/research-new-research (project title description)
  "Create a numbered research tracker for PROJECT, TITLE and DESCRIPTION."
  (interactive
   (list (read-string "Project: ")
         (read-string "Research title: ")
         (read-string "Description: ")))
  (star/research--new-document "research" project title description))

(defun star/research-new-srfc (title description)
  "Create a numbered Starintel RFC for TITLE and DESCRIPTION."
  (interactive
   (list (read-string "SRFC title: ")
         (read-string "Description: ")))
  (star/research--new-document "srfc" "Starintel" title description))

(defun star/research-install-capture-templates ()
  "Install Starintel Org-roam capture templates without deleting user templates."
  (when (boundp 'org-roam-capture-templates)
    (dolist
        (template
         '(("s" "Starintel research" plain
            "%?"
            :target
            (file+head
             "research/inbox/${slug}.org"
             "#+title: ${title}\n#+description: Inbox research capture requiring triage.\n#+filetags: :starintel:research:\n")
            :unnarrowed t)
           ("d" "Starintel design note" plain
            "%?"
            :target
            (file+head
             "design/inbox/${slug}.org"
             "#+title: ${title}\n#+description: Inbox design note requiring conversion into a numbered design file.\n#+filetags: :starintel:design-inbox:\n")
            :unnarrowed t)
           ("i" "Starintel implementation note" plain
            "%?"
            :target
            (file+head
             "implement/inbox/${slug}.org"
             "#+title: ${title}\n#+description: Inbox implementation note requiring triage.\n#+filetags: :starintel:implement:\n")
            :unnarrowed t)))
      (unless (assoc (car template) org-roam-capture-templates)
        (setq org-roam-capture-templates
              (append org-roam-capture-templates (list template)))))))

(defun star/roam-find ()
  "Find a Starintel Org-roam node."
  (interactive)
  (star/research-setup)
  (call-interactively #'org-roam-node-find))

(defun star/roam-insert ()
  "Insert a link to a Starintel Org-roam node."
  (interactive)
  (star/research-setup)
  (call-interactively #'org-roam-node-insert))

(defun star/roam-capture ()
  "Capture a Starintel Org-roam node."
  (interactive)
  (star/research-setup)
  (call-interactively #'org-roam-capture))

(defun star/roam-sync ()
  "Synchronize the Starintel Org-roam database."
  (interactive)
  (star/research-setup)
  (org-roam-db-sync)
  (message "Starintel Org-roam database synchronized"))

(defun star/roam-buffer-toggle ()
  "Toggle the Org-roam backlinks buffer."
  (interactive)
  (star/research-setup)
  (call-interactively #'org-roam-buffer-toggle))

(defun star/research-link-file (file)
  "Insert a repository-relative Org link to FILE."
  (interactive "fFile: ")
  (let ((relative (file-relative-name (expand-file-name file)
                                      (or (and buffer-file-name
                                               (file-name-directory buffer-file-name))
                                          (star/research--root)))))
    (insert (format "[[file:%s][%s]]"
                    relative
                    (file-name-nondirectory
                     (directory-file-name file))))))

(defun star/research-link-directory (directory)
  "Insert a repository-relative Org link to DIRECTORY."
  (interactive "DDirectory: ")
  (star/research-link-file (directory-file-name directory)))

(defun star/research-open-asset-directory ()
  "Open the asset directory associated with the current Org file."
  (interactive)
  (unless buffer-file-name
    (user-error "Current buffer is not visiting a file"))
  (let ((directory
         (concat (file-name-sans-extension buffer-file-name) ".assets")))
    (make-directory directory t)
    (dired directory)))

(defun star/research--linked-local-files (file)
  "Return local files directly linked by Org FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (org-mode)
    (let (files)
      (org-element-map (org-element-parse-buffer) 'link
        (lambda (link)
          (when (string= "file" (org-element-property :type link))
            (let ((target
                   (expand-file-name
                    (org-link-unescape
                     (org-element-property :path link))
                    (file-name-directory file))))
              (when (file-regular-p target)
                (push (file-truename target) files))))))
      (delete-dups (nreverse files)))))

(defun star/research--project-index-for-file (file)
  "Return the nearest project index associated with FILE."
  (let* ((project (file-name-nondirectory
                   (directory-file-name
                    (file-name-directory file))))
         (candidates
          (directory-files
           (star/research--path "roam" "indexes")
           t
           (format "%s.*\\.org\\'" (regexp-quote project))
           t)))
    (car candidates)))

(defun star/research--append-context-file (source destination remaining)
  "Append SOURCE to DESTINATION without exceeding REMAINING bytes.
Return the new remaining byte budget."
  (let* ((content (with-temp-buffer
                    (insert-file-contents source)
                    (buffer-string)))
         (header (format "\n* Context File: %s\n\n"
                         (file-relative-name source
                                             (star/research--root))))
         (payload (concat header content "\n"))
         (bytes (string-bytes payload)))
    (if (> bytes remaining)
        remaining
      (with-temp-buffer
        (insert payload)
        (append-to-file (point-min) (point-max) destination))
      (- remaining bytes))))

(defun star/research-build-context-bundle (&optional file)
  "Build a bounded context bundle for FILE.
Only the active file, its direct local links, and its project index are added."
  (interactive)
  (star/research-setup)
  (let* ((source (file-truename
                  (or file buffer-file-name
                      (user-error "No active file"))))
         (linked (star/research--linked-local-files source))
         (index (star/research--project-index-for-file source))
         (files (delete-dups
                 (delq nil (append (list source index) linked))))
         (destination
          (star/research--path
           ".starintel" "context"
           (format "%s-%s.org"
                   (format-time-string "%Y%m%dT%H%M%S")
                   (star/research--slug
                    (file-name-base source)))))
         (remaining star/research-context-max-bytes))
    (star/research--write-file
     destination
     (format "#+title: Bounded Context for %s\n#+created: %s\n"
             (file-name-base source)
             (star/research--timestamp)))
    (dolist (candidate files)
      (setq remaining
            (star/research--append-context-file
             candidate destination remaining)))
    (find-file destination)
    (message "Context bundle: %s (%d bytes free)"
             destination remaining)
    destination))

(defun star/research--org-title-present-p ()
  "Return non-nil when the current buffer has a title keyword."
  (save-excursion
    (goto-char (point-min))
    (re-search-forward "^#\\+title:[[:space:]]+\\S-" nil t)))

(defun star/research--org-description-present-p ()
  "Return non-nil when the current buffer has a description keyword."
  (save-excursion
    (goto-char (point-min))
    (re-search-forward "^#\\+description:[[:space:]]+\\S-" nil t)))

(defun star/research--headings ()
  "Return all headings in the current Org buffer."
  (org-element-map (org-element-parse-buffer) 'headline
    (lambda (headline)
      (org-element-property :raw-value headline))))

(defun star/research-validate-file (file)
  "Return a list of validation errors for Org FILE."
  (let (errors)
    (with-temp-buffer
      (insert-file-contents file)
      (org-mode)
      (unless (star/research--org-title-present-p)
        (push "missing #+title" errors))
      (unless (star/research--org-description-present-p)
        (push "missing #+description" errors))
      (when (string-match-p "/roam/design/" (file-truename file))
        (unless
            (string-match-p
             "\\(?:[[:upper:]][[:upper:][:digit:]-]*\\|SRFC\\)-[0-9]\\{3\\}-.*\\.org\\'"
             (file-name-nondirectory file))
          (push "invalid numbered design filename" errors))
        (let ((headings (star/research--headings)))
          (dolist (required star/research-required-design-headings)
            (unless (member required headings)
              (push (format "missing heading: %s" required) errors))))
        (save-excursion
          (goto-char (point-min))
          (unless
              (re-search-forward
               "| Version | Date | Description of change | Did nsaspy approve it? |"
               nil t)
            (push "missing version table" errors)))))
    (nreverse errors)))

(defun star/research-validate ()
  "Validate every Org file and display a report."
  (interactive)
  (let ((buffer (get-buffer-create "*Starintel Validation*"))
        failures)
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (insert (format "Starintel validation: %s\n\n"
                        (star/research--timestamp)))
        (dolist (file (star/research--org-files))
          (let ((errors (star/research-validate-file file)))
            (when errors
              (push (cons file errors) failures)
              (insert (format "%s\n"
                              (file-relative-name
                               file (star/research--root))))
              (dolist (error errors)
                (insert (format "  - %s\n" error)))
              (insert "\n"))))
        (unless failures
          (insert "OK\n"))))
    (display-buffer buffer)
    (when failures
      (user-error "%d file(s) failed validation"
                  (length failures)))
    t))

(defun star/research-batch-validate ()
  "Batch entry point for repository validation."
  (condition-case error-data
      (progn
        (star/research-setup)
        (star/research-validate)
        (kill-emacs 0))
    (error
     (message "%s" (error-message-string error-data))
     (kill-emacs 1))))

(defun star/research--call-git (&rest arguments)
  "Run Git with ARGUMENTS in the repository and return the output buffer."
  (let ((default-directory (star/research--root))
        (buffer (get-buffer-create "*Starintel Git*")))
    (with-current-buffer buffer
      (erase-buffer))
    (let ((status
           (apply #'process-file
                  star/research-git-program
                  nil
                  buffer
                  t
                  arguments)))
      (unless (zerop status)
        (display-buffer buffer)
        (user-error "Git failed with status %d" status))
      buffer)))

(defun star/research-git-status ()
  "Display repository Git status."
  (interactive)
  (display-buffer
   (star/research--call-git "status" "--short" "--branch")))

(defun star/research-git-diff ()
  "Display the repository diff."
  (interactive)
  (display-buffer
   (star/research--call-git "diff" "--stat")))

(defun star/research-git-stage ()
  "Validate and stage workflow-owned repository paths."
  (interactive)
  (star/research-validate)
  (star/research--call-git
   "add"
   "lisp"
   "roam"
   "ui"
   "README.org"
   ".dir-locals.el")
  (star/research-git-status))

(defun star/research-git-commit (message)
  "Validate, stage, and commit workflow files with MESSAGE."
  (interactive "sCommit message: ")
  (when (string-empty-p (string-trim message))
    (user-error "Commit message cannot be empty"))
  (star/research-git-stage)
  (star/research--call-git "diff" "--cached" "--check")
  (star/research--call-git "commit" "-m" message)
  (star/research-git-status))

(defun star/research-promote-design (file)
  "Copy one design FILE into the implementation queue."
  (interactive
   (list
    (read-file-name
     "Design file: "
     (star/research--path "roam" "design")
     nil t nil
     (lambda (candidate)
       (or (file-directory-p candidate)
           (string-suffix-p ".org" candidate))))))
  (let* ((source (file-truename file))
         (root (file-truename
                (star/research--path "roam" "design")))
         (relative (file-relative-name source root))
         (destination
          (star/research--path "roam" "implement" relative)))
    (when (string-prefix-p "../" relative)
      (user-error "Design is outside roam/design"))
    (when (file-exists-p destination)
      (user-error "Implementation file already exists: %s"
                  destination))
    (make-directory (file-name-directory destination) t)
    (copy-file source destination)
    (find-file destination)
    (message "Promoted %s" relative)
    destination))

(defun star/research--require-org-ql ()
  "Load Org-ql or signal a useful error."
  (unless (require 'org-ql nil t)
    (user-error "Install org-ql to use this command")))

(defun star/research-open-todo-view ()
  "Open every active Starintel TODO."
  (interactive)
  (star/research--require-org-ql)
  (org-ql-search (star/research--org-files)
    '(and (todo) (not (done)))
    :title "Starintel active work"))

(defun star/research-open-blocked-view ()
  "Open every blocked Starintel task."
  (interactive)
  (star/research--require-org-ql)
  (org-ql-search (star/research--org-files)
    '(todo "BLOCKED")
    :title "Starintel blocked work"))

(defun star/research-open-project-view (project)
  "Open active work whose PROJECT property equals PROJECT."
  (interactive "sProject: ")
  (star/research--require-org-ql)
  (org-ql-search
      (star/research--org-files)
    `(and (property "PROJECT" ,project)
          (todo)
          (not (done)))
    :title (format "Starintel project: %s" project)))

(defun star/research-export-graph-json (&optional destination)
  "Export Org-roam nodes and links as JSON to DESTINATION."
  (interactive)
  (star/research-setup)
  (unless (require 'org-roam nil t)
    (user-error "Install org-roam to export the graph"))
  (org-roam-db-sync)
  (let* ((destination
          (or destination
              (star/research--path "ui" "web" "graph.json")))
         (nodes
          (mapcar
           (pcase-lambda (`(,id ,title ,file))
             `((id . ,id)
               (title . ,title)
               (file . ,(file-relative-name
                         file (star/research--root)))))
           (org-roam-db-query
            [:select [id title file] :from nodes])))
         (links
          (mapcar
           (pcase-lambda (`(,source ,dest ,type))
             `((source . ,source)
               (target . ,dest)
               (type . ,(format "%s" type))))
           (org-roam-db-query
            [:select [source dest type] :from links])))
         (json-encoding-pretty-print t))
    (make-directory (file-name-directory destination) t)
    (with-temp-file destination
      (insert
       (json-encode
        `((generated_at . ,(format-time-string "%FT%T%z"))
          (nodes . ,nodes)
          (links . ,links)))))
    (message "Graph exported to %s" destination)
    destination))

(defun star/research-web-ui-start ()
  "Export graph data and serve the web IDE with simple-httpd."
  (interactive)
  (star/research-export-graph-json)
  (unless (require 'simple-httpd nil t)
    (user-error "Install simple-httpd to serve the web UI"))
  (setq httpd-root (star/research--path "ui" "web"))
  (httpd-start)
  (browse-url (format "http://127.0.0.1:%s/" httpd-port)))

(defun star/research-desktop-graph-start ()
  "Export graph data and launch the desktop graph IDE."
  (interactive)
  (let ((graph (star/research-export-graph-json)))
    (unless star/research-desktop-command
      (user-error "`star/research-desktop-command' is empty"))
    (apply #'start-process
           "starintel-desktop-graph"
           "*Starintel Desktop Graph*"
           (car star/research-desktop-command)
           (append (cdr star/research-desktop-command)
                   (list graph)))))

(defun star/research-dashboard ()
  "Open the roadmap and active-work view."
  (interactive)
  (star/research-setup)
  (find-file
   (star/research--path
    "roam" "indexes" "STAR-INDEX-000-roadmap.org"))
  (when (require 'org-ql nil t)
    (star/research-open-todo-view)))

(defun star/research-run-cycle ()
  "Run the normal research-cycle entry sequence."
  (interactive)
  (star/research-setup)
  (when (require 'org-roam nil t)
    (org-roam-db-sync))
  (star/research-validate)
  (star/research-dashboard))

(define-minor-mode star/research-mode
  "Global Starintel research workflow mode."
  :global t
  :lighter " STAR"
  :keymap star/research-mode-map
  (when star/research-mode
    (star/research-setup)))

(define-key star/research-prefix-map (kbd "f") #'star/roam-find)
(define-key star/research-prefix-map (kbd "i") #'star/roam-insert)
(define-key star/research-prefix-map (kbd "c") #'star/roam-capture)
(define-key star/research-prefix-map (kbd "s") #'star/roam-sync)
(define-key star/research-prefix-map (kbd "b") #'star/roam-buffer-toggle)
(define-key star/research-prefix-map (kbd "d") #'star/research-new-design)
(define-key star/research-prefix-map (kbd "r") #'star/research-new-research)
(define-key star/research-prefix-map (kbd "R") #'star/research-new-srfc)
(define-key star/research-prefix-map (kbd "l") star/research-link-prefix-map)
(define-key star/research-link-prefix-map (kbd "f") #'star/research-link-file)
(define-key star/research-link-prefix-map (kbd "d") #'star/research-link-directory)
(define-key star/research-prefix-map (kbd "a") #'star/research-open-asset-directory)
(define-key star/research-prefix-map (kbd "x") #'star/research-build-context-bundle)
(define-key star/research-prefix-map (kbd "q") star/research-query-prefix-map)
(define-key star/research-query-prefix-map (kbd "t") #'star/research-open-todo-view)
(define-key star/research-query-prefix-map (kbd "b") #'star/research-open-blocked-view)
(define-key star/research-query-prefix-map (kbd "p") #'star/research-open-project-view)
(define-key star/research-prefix-map (kbd "v") #'star/research-validate)
(define-key star/research-prefix-map (kbd "p") #'star/research-promote-design)
(define-key star/research-prefix-map (kbd "g") star/research-git-prefix-map)
(define-key star/research-git-prefix-map (kbd "s") #'star/research-git-status)
(define-key star/research-git-prefix-map (kbd "d") #'star/research-git-diff)
(define-key star/research-git-prefix-map (kbd "a") #'star/research-git-stage)
(define-key star/research-git-prefix-map (kbd "c") #'star/research-git-commit)
(define-key star/research-prefix-map (kbd "e") #'star/research-export-graph-json)
(define-key star/research-prefix-map (kbd "w") #'star/research-web-ui-start)
(define-key star/research-prefix-map (kbd "D") #'star/research-desktop-graph-start)
(define-key star/research-prefix-map (kbd "o") #'star/research-dashboard)

(provide 'starintel-auto-research)

;;; starintel-auto-research.el ends here
