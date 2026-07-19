;;; pages.el --- Org-roam publishing for Starintel -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'json)
(require 'org)
(require 'org-element)
(require 'org-id)
(require 'ox-html)
(require 'org-roam)
(require 'seq)
(require 'subr-x)
(require 'url-util)

(defgroup starintel-pages nil
  "Publish the Starintel Org-roam graph as a static site."
  :group 'org)

(defcustom starintel-pages-site-title "Starintel Second Brain"
  "Title shown in the generated site."
  :type 'string)

(defcustom starintel-pages-source-directory "roam"
  "Org-roam directory relative to the repository root."
  :type 'string)

(defcustom starintel-pages-output-directory "_site"
  "Generated site directory relative to the repository root."
  :type 'string)

(defcustom starintel-pages-build-directory ".cache/pages"
  "Temporary build directory relative to the repository root."
  :type 'string)

(defvar starintel-pages-root nil)
(defvar starintel-pages--stage-directory nil)
(defvar starintel-pages--output-directory nil)
(defvar starintel-pages--path-to-id nil)
(defvar starintel-pages--path-to-title nil)
(defvar starintel-pages--file-node-table nil)
(defvar starintel-pages--records nil)

(defun starintel-pages--repo-root (&optional start)
  (or starintel-pages-root
      (let ((root (locate-dominating-file
                   (or start default-directory)
                   "AGENTS.md")))
        (unless root
          (error "Cannot locate repository root from %s"
                 (or start default-directory)))
        (file-name-as-directory (file-truename root)))))

(defun starintel-pages--source-root ()
  (expand-file-name starintel-pages-source-directory
                    (starintel-pages--repo-root)))

(defun starintel-pages--build-root ()
  (expand-file-name starintel-pages-build-directory
                    (starintel-pages--repo-root)))

(defun starintel-pages--site-root ()
  (expand-file-name starintel-pages-output-directory
                    (starintel-pages--repo-root)))

(defun starintel-pages--normalize-path (path)
  (file-truename (expand-file-name path)))

(defun starintel-pages--org-files (directory)
  (sort (directory-files-recursively directory "\\.org\\'")
        #'string<))

(defun starintel-pages--relative-source-path (file)
  (file-relative-name file starintel-pages--stage-directory))

(defun starintel-pages--stable-id (relative-path)
  (format "starintel-%s"
          (substring (secure-hash 'sha256 relative-path) 0 32)))

(defun starintel-pages--keyword (file keyword)
  (with-temp-buffer
    (insert-file-contents file)
    (org-mode)
    (let* ((values (cdr (assoc-string
                         (upcase keyword)
                         (org-collect-keywords
                          (list (upcase keyword)))
                         t)))
           (value (car values)))
      (and value (string-trim value)))))

(defun starintel-pages--file-id-in-buffer ()
  (save-excursion
    (goto-char (point-min))
    (let ((limit (or (save-excursion
                       (re-search-forward "^\\*+ " nil t))
                     (point-max))))
      (when (re-search-forward
             "^:ID:[ \t]+\\([^ \t\n]+\\)[ \t]*$"
             limit t)
        (match-string-no-properties 1)))))

(defun starintel-pages--ensure-file-id (file relative-path)
  (with-current-buffer (find-file-noselect file)
    (let ((id (starintel-pages--file-id-in-buffer)))
      (unless id
        (setq id (starintel-pages--stable-id relative-path))
        (goto-char (point-min))
        (insert ":PROPERTIES:\n:ID:       " id "\n:END:\n"))
      (save-buffer)
      id)))

(defun starintel-pages--ensure-heading-custom-ids (file)
  (with-current-buffer (find-file-noselect file)
    (org-with-wide-buffer
     (org-map-entries
      (lambda ()
        (let ((id (org-entry-get nil "ID"))
              (custom-id (org-entry-get nil "CUSTOM_ID")))
          (when (and id (not custom-id))
            (org-entry-put nil "CUSTOM_ID" id))))
      nil 'file))
    (save-buffer)))

(defun starintel-pages--link-replacements (file)
  (with-current-buffer (find-file-noselect file)
    (org-with-wide-buffer
     (let (replacements)
       (org-element-map (org-element-parse-buffer) 'link
         (lambda (link)
           (when (and (string= (org-element-property :type link) "file")
                      (not (org-element-property :search-option link)))
             (let* ((path (org-element-property :path link))
                    (target (expand-file-name
                             path
                             (file-name-directory file)))
                    (target-key (and (file-exists-p target)
                                     (starintel-pages--normalize-path target)))
                    (id (and target-key
                             (gethash target-key
                                      starintel-pages--path-to-id))))
               (when id
                 (let* ((begin (org-element-property :begin link))
                        (end (- (org-element-property :end link)
                                (or (org-element-property :post-blank link) 0)))
                        (content-begin
                         (org-element-property :contents-begin link))
                        (content-end
                         (org-element-property :contents-end link))
                        (description
                         (if (and content-begin content-end)
                             (buffer-substring-no-properties
                              content-begin content-end)
                           (gethash target-key
                                    starintel-pages--path-to-title))))
                   (push (list begin end
                               (format "[[id:%s][%s]]"
                                       id
                                       (or description id)))
                         replacements)))))))
       (sort replacements
             (lambda (left right) (> (car left) (car right))))))))

(defun starintel-pages--rewrite-file-links (file)
  (let ((replacements (starintel-pages--link-replacements file)))
    (when replacements
      (with-current-buffer (find-file-noselect file)
        (dolist (replacement replacements)
          (goto-char (nth 0 replacement))
          (delete-region (nth 0 replacement) (nth 1 replacement))
          (insert (nth 2 replacement)))
        (save-buffer)))))

(defun starintel-pages--prepare-stage ()
  (let* ((build-root (starintel-pages--build-root))
         (source-root (starintel-pages--source-root)))
    (setq starintel-pages--stage-directory
          (expand-file-name "roam" build-root)
          starintel-pages--output-directory
          (starintel-pages--site-root)
          starintel-pages--path-to-id (make-hash-table :test #'equal)
          starintel-pages--path-to-title (make-hash-table :test #'equal))
    (when (file-directory-p build-root)
      (delete-directory build-root t))
    (when (file-directory-p starintel-pages--output-directory)
      (delete-directory starintel-pages--output-directory t))
    (make-directory build-root t)
    (make-directory starintel-pages--output-directory t)
    (copy-directory source-root starintel-pages--stage-directory t t t)
    (let ((files (starintel-pages--org-files
                  starintel-pages--stage-directory)))
      (dolist (file files)
        (let* ((relative (starintel-pages--relative-source-path file))
               (key (starintel-pages--normalize-path file))
               (title (or (starintel-pages--keyword file "TITLE")
                          (file-name-base file)))
               (id (starintel-pages--ensure-file-id file relative)))
          (puthash key id starintel-pages--path-to-id)
          (puthash key title starintel-pages--path-to-title)))
      (dolist (file files)
        (starintel-pages--ensure-heading-custom-ids file)
        (starintel-pages--rewrite-file-links file))
      files)))

(defun starintel-pages--configure-org-roam (files)
  (let ((build-root (starintel-pages--build-root)))
    (setq org-roam-directory
          (file-truename starintel-pages--stage-directory)
          org-roam-db-location
          (expand-file-name "org-roam.db" build-root)
          org-id-locations-file
          (expand-file-name "org-id-locations" build-root)
          org-roam-db-update-on-save nil)
    (org-id-update-id-locations files)
    (org-roam-db-sync)
    (setq starintel-pages--file-node-table
          (make-hash-table :test #'equal))
    (dolist (node (org-roam-node-list))
      (when (zerop (or (org-roam-node-level node) 0))
        (puthash (starintel-pages--normalize-path
                  (org-roam-node-file node))
                 node
                 starintel-pages--file-node-table)))))

(defun starintel-pages--node-file-node (node)
  (gethash (starintel-pages--normalize-path
            (org-roam-node-file node))
           starintel-pages--file-node-table))

(defun starintel-pages--note-output-file (file)
  (expand-file-name
   (concat (file-name-sans-extension
            (file-relative-name file
                                starintel-pages--stage-directory))
           ".html")
   (expand-file-name "notes" starintel-pages--output-directory)))

(defun starintel-pages--url-path (path)
  (mapconcat
   (lambda (component)
     (if (member component '("." ".." ""))
         component
       (url-hexify-string component)))
   (split-string (replace-regexp-in-string "\\\\" "/" path) "/")
   "/"))

(defun starintel-pages--href-between (from-output to-output &optional anchor)
  (let ((relative (file-relative-name
                   to-output
                   (file-name-directory from-output))))
    (concat (starintel-pages--url-path relative)
            (when anchor
              (concat "#" (url-hexify-string anchor))))))

(defun starintel-pages--node-output-href (node current-output)
  (let* ((target-output
          (starintel-pages--note-output-file
           (org-roam-node-file node)))
         (anchor (when (> (or (org-roam-node-level node) 0) 0)
                   (org-roam-node-id node))))
    (starintel-pages--href-between
     current-output target-output anchor)))

(defun starintel-pages--node-label (node)
  (let* ((file-node (starintel-pages--node-file-node node))
         (file-title (and file-node (org-roam-node-title file-node)))
         (node-title (org-roam-node-title node)))
    (if (and file-title
             (> (or (org-roam-node-level node) 0) 0)
             (not (string= file-title node-title)))
        (format "%s › %s" file-title node-title)
      (or node-title file-title (org-roam-node-id node)))))

(defun starintel-pages--export-id-link (path description backend info)
  (when (eq backend 'html)
    (let ((node (org-roam-node-from-id path)))
      (unless node
        (error "Unresolved Org-roam id link: %s" path))
      (let* ((current-file (plist-get info :input-file))
             (current-output
              (starintel-pages--note-output-file current-file))
             (href (starintel-pages--node-output-href
                    node current-output))
             (label (or description
                        (org-html-encode-plain-text
                         (starintel-pages--node-label node)))))
        (format "<a href=\"%s\">%s</a>" href label)))))

(defun starintel-pages--root-href (current-output target)
  (starintel-pages--href-between
   current-output
   (expand-file-name target starintel-pages--output-directory)))

(defun starintel-pages--header-html (current-output)
  (format
   (concat "<header class=\"site-header\">"
           "<a class=\"site-title\" href=\"%s\">%s</a>"
           "<nav><a href=\"%s\">Index</a>"
           "<a href=\"%s\">Search</a>"
           "<a href=\"%s\">Graph</a></nav>"
           "</header>")
   (starintel-pages--root-href current-output "index.html")
   (org-html-encode-plain-text starintel-pages-site-title)
   (starintel-pages--root-href current-output "index.html")
   (starintel-pages--root-href current-output "search.html")
   (starintel-pages--root-href current-output "graph.html")))

(defun starintel-pages--backlinks (node)
  (let ((seen (make-hash-table :test #'equal))
        rows)
    (dolist (backlink (org-roam-backlinks-get node))
      (let* ((source (org-roam-backlink-source-node backlink))
             (key (org-roam-node-id source)))
        (unless (gethash key seen)
          (puthash key t seen)
          (push source rows))))
    (sort rows
          (lambda (left right)
            (string-lessp (starintel-pages--node-label left)
                          (starintel-pages--node-label right))))))

(defun starintel-pages--backlinks-html (file current-output)
  (let* ((node (gethash (starintel-pages--normalize-path file)
                        starintel-pages--file-node-table))
         (backlinks (and node (starintel-pages--backlinks node))))
    (concat
     "<aside class=\"backlinks\"><h2>Backlinks</h2>"
     (if backlinks
         (concat
          "<ul>"
          (mapconcat
           (lambda (source)
             (format "<li><a href=\"%s\">%s</a></li>"
                     (starintel-pages--node-output-href
                      source current-output)
                     (org-html-encode-plain-text
                      (starintel-pages--node-label source))))
           backlinks "")
          "</ul>")
       "<p>No pages link here yet.</p>")
     "</aside>")))

(defun starintel-pages--insert-before (needle insertion text)
  (if-let ((position (string-match needle text)))
      (concat (substring text 0 position)
              insertion
              (substring text position))
    text))

(defun starintel-pages--insert-after (regexp insertion text)
  (if (string-match regexp text)
      (concat (substring text 0 (match-end 0))
              insertion
              (substring text (match-end 0)))
    text))

(defun starintel-pages--final-output-filter (output backend info)
  (if (not (eq backend 'html))
      output
    (let* ((input (plist-get info :input-file))
           (current-output (starintel-pages--note-output-file input))
           (css (starintel-pages--root-href
                 current-output "assets/site.css"))
           (script (starintel-pages--root-href
                    current-output "assets/site.js"))
           (head (format
                  (concat "<meta name=\"viewport\" "
                          "content=\"width=device-width,initial-scale=1\">"
                          "<link rel=\"stylesheet\" href=\"%s\">"
                          "<script defer src=\"%s\"></script>")
                  css script))
           (header (starintel-pages--header-html current-output))
           (backlinks (starintel-pages--backlinks-html
                       input current-output)))
      (setq output
            (starintel-pages--insert-before
             "</head>" head output))
      (setq output
            (starintel-pages--insert-after
             "<body[^>]*>" header output))
      (starintel-pages--insert-before
       "</body>" backlinks output))))

(defun starintel-pages--export-file (file)
  (let ((output (starintel-pages--note-output-file file)))
    (make-directory (file-name-directory output) t)
    (with-current-buffer (find-file-noselect file)
      (let ((enable-local-eval nil)
            (enable-local-variables nil)
            (org-confirm-babel-evaluate t)
            (org-export-use-babel nil)
            (org-export-with-broken-links 'mark)
            (org-html-doctype "html5")
            (org-html-html5-fancy t)
            (org-html-head-include-default-style nil)
            (org-html-head-include-scripts nil)
            (org-html-htmlize-output-type 'css)
            (org-html-link-org-files-as-html t)
            (org-html-preamble nil)
            (org-html-postamble nil)
            (org-export-filter-final-output-functions
             '(starintel-pages--final-output-filter)))
        (org-export-to-file
         'html output nil nil nil nil
         '(:with-author nil
           :with-creator nil
           :with-date t
           :with-email nil
           :with-toc t
           :section-numbers nil))))
    output))

(defun starintel-pages--description (file)
  (or (starintel-pages--keyword file "DESCRIPTION") ""))

(defun starintel-pages--tags (node file)
  (or (org-roam-node-tags node)
      (let ((raw (starintel-pages--keyword file "FILETAGS")))
        (and raw
             (split-string (string-trim raw ":" ":") ":" t)))))

(defun starintel-pages--search-text (file)
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (while (re-search-forward
            "^\\(?:#\\+[^\n]*\\|:[A-Z_]+:.*\\|[|][-+|]+\\)$"
            nil t)
      (replace-match ""))
    (goto-char (point-min))
    (while (re-search-forward
            "\\[\\[[^]]+\\]\\[\\([^]]+\\)\\]\\]"
            nil t)
      (replace-match "\\1"))
    (let ((text (replace-regexp-in-string
                 "[ \t\n\r]+" " " (buffer-string))))
      (string-trim
       (substring text 0 (min 2400 (length text)))))))

(defun starintel-pages--record-for-node (node)
  (let* ((file (org-roam-node-file node))
         (relative (starintel-pages--relative-source-path file))
         (source-file (expand-file-name relative
                                        (starintel-pages--source-root)))
         (attributes (file-attributes source-file))
         (modified (format-time-string
                    "%Y-%m-%dT%H:%M:%SZ"
                    (file-attribute-modification-time attributes)
                    t))
         (kind (car (split-string relative "/" t)))
         (href (concat "notes/"
                       (file-name-sans-extension
                        (replace-regexp-in-string "\\\\" "/" relative))
                       ".html")))
    (list :id (org-roam-node-id node)
          :title (org-roam-node-title node)
          :description (starintel-pages--description file)
          :file file
          :relative relative
          :href href
          :kind (or kind "notes")
          :tags (or (starintel-pages--tags node file) '())
          :modified modified
          :text (starintel-pages--search-text file))))

(defun starintel-pages--collect-records ()
  (setq starintel-pages--records
        (sort
         (mapcar #'starintel-pages--record-for-node
                 (let (nodes)
                   (maphash (lambda (_file node) (push node nodes))
                            starintel-pages--file-node-table)
                   nodes))
         (lambda (left right)
           (string-lessp (plist-get left :title)
                         (plist-get right :title))))))

(defun starintel-pages--html-page (title body &optional script-data)
  (concat
   "<!doctype html><html lang=\"en\"><head>"
   "<meta charset=\"utf-8\">"
   "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
   "<title>" (org-html-encode-plain-text title) "</title>"
   "<link rel=\"stylesheet\" href=\"assets/site.css\">"
   "<script defer src=\"assets/site.js\"></script>"
   script-data
   "</head><body>"
   (starintel-pages--header-html
    (expand-file-name "index.html" starintel-pages--output-directory))
   "<main class=\"site-main\">" body "</main>"
   "</body></html>"))

(defun starintel-pages--write-file (path content)
  (make-directory (file-name-directory path) t)
  (with-temp-file path (insert content)))

(defun starintel-pages--record-link (record)
  (format
   (concat "<li class=\"note-row\"><a href=\"%s\">%s</a>"
           "<span>%s</span></li>")
   (starintel-pages--url-path (plist-get record :href))
   (org-html-encode-plain-text (plist-get record :title))
   (org-html-encode-plain-text (plist-get record :modified))))

(defun starintel-pages--group-records ()
  (let ((groups (make-hash-table :test #'equal)))
    (dolist (record starintel-pages--records)
      (push record (gethash (plist-get record :kind) groups)))
    groups))

(defun starintel-pages--index-body ()
  (let* ((groups (starintel-pages--group-records))
         (recent (seq-take
                  (sort (copy-sequence starintel-pages--records)
                        (lambda (left right)
                          (string> (plist-get left :modified)
                                   (plist-get right :modified))))
                  25))
         (sections '("design" "research" "implement" "indexes")))
    (concat
     "<section class=\"hero\"><p class=\"eyebrow\">Org-roam knowledge graph</p>"
     "<h1>Starintel Second Brain</h1>"
     "<p>Research, designs, implementation records, and project indexes exported directly from the repository's Org-roam graph.</p>"
     "<div class=\"metrics\">"
     (mapconcat
      (lambda (section)
        (format
         "<div><strong>%d</strong><span>%s</span></div>"
         (length (gethash section groups))
         (capitalize section)))
      sections "")
     "</div></section>"
     "<section><h2>Recently updated</h2><ol class=\"note-list\">"
     (mapconcat #'starintel-pages--record-link recent "")
     "</ol></section>"
     (mapconcat
      (lambda (section)
        (let ((records (sort (copy-sequence (gethash section groups))
                             (lambda (left right)
                               (string-lessp (plist-get left :title)
                                             (plist-get right :title))))))
          (when records
            (concat "<section><h2>" (capitalize section) "</h2>"
                    "<ul class=\"note-list\">"
                    (mapconcat #'starintel-pages--record-link records "")
                    "</ul></section>"))))
      sections ""))))

(defun starintel-pages--write-index-pages ()
  (starintel-pages--write-file
   (expand-file-name "index.html" starintel-pages--output-directory)
   (starintel-pages--html-page
    starintel-pages-site-title
    (starintel-pages--index-body)))
  (starintel-pages--write-file
   (expand-file-name "search.html" starintel-pages--output-directory)
   (starintel-pages--html-page
    "Search — Starintel Second Brain"
    (concat
     "<section><p class=\"eyebrow\">Full graph search</p><h1>Search</h1>"
     "<label for=\"search-input\">Search titles, tags, descriptions, and page text</label>"
     "<input id=\"search-input\" type=\"search\" autocomplete=\"off\" autofocus>"
     "<p id=\"search-status\" aria-live=\"polite\"></p>"
     "<ol id=\"search-results\" class=\"search-results\"></ol></section>")))
  (starintel-pages--write-file
   (expand-file-name "graph.html" starintel-pages--output-directory)
   (starintel-pages--html-page
    "Graph — Starintel Second Brain"
    (concat
     "<section><p class=\"eyebrow\">Org-roam network</p><h1>Graph</h1>"
     "<p>Drag nodes to inspect the research network. Select a node to open its page.</p>"
     "<canvas id=\"graph-canvas\" width=\"1200\" height=\"760\" aria-label=\"Interactive Org-roam graph\"></canvas>"
     "<p id=\"graph-status\" aria-live=\"polite\"></p></section>")))
  (starintel-pages--write-file
   (expand-file-name "404.html" starintel-pages--output-directory)
   (starintel-pages--html-page
    "Not found — Starintel Second Brain"
    "<section><h1>Page not found</h1><p>The requested node does not exist in this build.</p></section>")))

(defun starintel-pages--json-record (record)
  `((id . ,(plist-get record :id))
    (title . ,(plist-get record :title))
    (description . ,(plist-get record :description))
    (url . ,(plist-get record :href))
    (kind . ,(plist-get record :kind))
    (tags . ,(vconcat (plist-get record :tags)))
    (modified . ,(plist-get record :modified))
    (text . ,(plist-get record :text))))

(defun starintel-pages--graph-links ()
  (let ((seen (make-hash-table :test #'equal))
        links)
    (maphash
     (lambda (_file target-node)
       (dolist (backlink (org-roam-backlinks-get target-node))
         (let* ((source-node
                 (starintel-pages--node-file-node
                  (org-roam-backlink-source-node backlink)))
                (source-id (and source-node
                                (org-roam-node-id source-node)))
                (target-id (org-roam-node-id target-node))
                (key (and source-id
                          (format "%s->%s" source-id target-id))))
           (when (and key
                      (not (string= source-id target-id))
                      (not (gethash key seen)))
             (puthash key t seen)
             (push `((source . ,source-id)
                     (target . ,target-id))
                   links)))))
     starintel-pages--file-node-table)
    (nreverse links)))

(defun starintel-pages--write-json ()
  (let ((json-encoding-pretty-print t))
    (starintel-pages--write-file
     (expand-file-name "search-index.json"
                       starintel-pages--output-directory)
     (json-encode
      (vconcat (mapcar #'starintel-pages--json-record
                       starintel-pages--records))))
    (starintel-pages--write-file
     (expand-file-name "graph.json"
                       starintel-pages--output-directory)
     (json-encode
      `((nodes . ,(vconcat
                   (mapcar #'starintel-pages--json-record
                           starintel-pages--records)))
        (links . ,(vconcat (starintel-pages--graph-links))))))))

(defun starintel-pages--hidden-relative-path-p (relative)
  (seq-some (lambda (component)
              (string-prefix-p "." component))
            (split-string relative "/" t)))

(defun starintel-pages--copy-roam-assets ()
  (let ((target-root
         (expand-file-name "notes" starintel-pages--output-directory)))
    (dolist (file (directory-files-recursively
                   starintel-pages--stage-directory "."))
      (let ((relative (starintel-pages--relative-source-path file)))
        (when (and (file-regular-p file)
                   (not (string-match-p "\\.org\\'" file))
                   (not (starintel-pages--hidden-relative-path-p relative)))
          (let ((target (expand-file-name relative target-root)))
            (make-directory (file-name-directory target) t)
            (copy-file file target t t t)))))))

(defun starintel-pages--copy-site-assets ()
  (let* ((source (expand-file-name
                  "pages/static"
                  (starintel-pages--repo-root)))
         (target (expand-file-name
                  "assets"
                  starintel-pages--output-directory)))
    (copy-directory source target t t t)
    (starintel-pages--write-file
     (expand-file-name ".nojekyll"
                       starintel-pages--output-directory)
     "")))

(defun starintel-pages-build (&optional root)
  "Build the complete Org-roam site beneath `_site'."
  (interactive)
  (let* ((starintel-pages-root
          (file-name-as-directory
           (file-truename (or root (starintel-pages--repo-root)))))
         (files (starintel-pages--prepare-stage)))
    (starintel-pages--configure-org-roam files)
    (org-link-set-parameters
     "id" :export #'starintel-pages--export-id-link)
    (starintel-pages--collect-records)
    (dolist (file files)
      (starintel-pages--export-file file))
    (starintel-pages--copy-roam-assets)
    (starintel-pages--copy-site-assets)
    (starintel-pages--write-json)
    (starintel-pages--write-index-pages)
    (message "Published %d Org-roam pages to %s"
             (length files)
             starintel-pages--output-directory)
    starintel-pages--output-directory))

(defun starintel-pages-normalize-source (&optional root)
  "Add stable file IDs and convert local Org file links to ID links."
  (interactive)
  (let* ((starintel-pages-root
          (file-name-as-directory
           (file-truename (or root (starintel-pages--repo-root)))))
         (source (starintel-pages--source-root))
         (starintel-pages--stage-directory source)
         (starintel-pages--path-to-id (make-hash-table :test #'equal))
         (starintel-pages--path-to-title (make-hash-table :test #'equal))
         (files (starintel-pages--org-files source)))
    (dolist (file files)
      (let* ((relative (file-relative-name file source))
             (key (starintel-pages--normalize-path file))
             (title (or (starintel-pages--keyword file "TITLE")
                        (file-name-base file)))
             (id (starintel-pages--ensure-file-id file relative)))
        (puthash key id starintel-pages--path-to-id)
        (puthash key title starintel-pages--path-to-title)))
    (dolist (file files)
      (starintel-pages--ensure-heading-custom-ids file)
      (starintel-pages--rewrite-file-links file))
    (message "Normalized %d Org-roam files" (length files))))

(defalias 'star/pages-build #'starintel-pages-build)
(defalias 'star/roam-normalize #'starintel-pages-normalize-source)

(provide 'starintel-pages)
;;; pages.el ends here
