;;; pages-metadata.el --- Git-backed Pages dates and RSS -*- lexical-binding: t; -*-

(require 'seq)
(require 'subr-x)

(defconst starintel-pages-public-origin "https://auto-research.starintel.actor")
(defconst starintel-pages-rss-limit 100)
(defvar starintel-pages--git-modified-cache (make-hash-table :test #'equal))

(defun starintel-pages--normalize-iso-time (value)
  (when (and value (not (string-empty-p value)))
    (condition-case nil
        (format-time-string "%Y-%m-%dT%H:%M:%SZ" (date-to-time value) t)
      (error nil))))

(defun starintel-pages--git-modified-time (relative source-file)
  (or (gethash relative starintel-pages--git-modified-cache)
      (let* ((default-directory (starintel-pages--repo-root))
             (repo-path (concat starintel-pages-source-directory "/" relative))
             (git-value
              (with-temp-buffer
                (when (zerop
                       (process-file "git" nil t nil
                                     "log" "-1" "--format=%cI" "--" repo-path))
                  (string-trim (buffer-string)))))
             (modified
              (or (starintel-pages--normalize-iso-time git-value)
                  (format-time-string
                   "%Y-%m-%dT%H:%M:%SZ"
                   (file-attribute-modification-time
                    (file-attributes source-file))
                   t))))
        (puthash relative modified starintel-pages--git-modified-cache)
        modified)))

(defun starintel-pages--record-for-node (node)
  (let* ((file (org-roam-node-file node))
         (relative (starintel-pages--relative-source-path file))
         (source-file (expand-file-name relative
                                        (starintel-pages--source-root)))
         (modified (starintel-pages--git-modified-time relative source-file))
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

(defun starintel-pages--xml-escape (value)
  (let ((text (format "%s" (or value ""))))
    (setq text (replace-regexp-in-string "&" "&amp;" text t t))
    (setq text (replace-regexp-in-string "<" "&lt;" text t t))
    (setq text (replace-regexp-in-string ">" "&gt;" text t t))
    (setq text (replace-regexp-in-string "\"" "&quot;" text t t))
    (replace-regexp-in-string "'" "&apos;" text t t)))

(defun starintel-pages--rss-date (iso-time)
  (let ((system-time-locale "C"))
    (format-time-string "%a, %d %b %Y %H:%M:%S GMT"
                        (date-to-time iso-time)
                        t)))

(defun starintel-pages--absolute-url (href)
  (concat starintel-pages-public-origin "/"
          (starintel-pages--url-path href)))

(defun starintel-pages--rss-item (record)
  (let* ((title (plist-get record :title))
         (description (or (plist-get record :description) title))
         (link (starintel-pages--absolute-url (plist-get record :href)))
         (id (plist-get record :id))
         (modified (plist-get record :modified)))
    (concat
     "<item>"
     "<title>" (starintel-pages--xml-escape title) "</title>"
     "<link>" (starintel-pages--xml-escape link) "</link>"
     "<guid isPermaLink=\"false\">" (starintel-pages--xml-escape id) "</guid>"
     "<pubDate>" (starintel-pages--rss-date modified) "</pubDate>"
     "<description>" (starintel-pages--xml-escape description) "</description>"
     "</item>")))

(defun starintel-pages--write-rss ()
  (let* ((recent
          (seq-take
           (sort (copy-sequence starintel-pages--records)
                 (lambda (left right)
                   (string> (plist-get left :modified)
                            (plist-get right :modified))))
           starintel-pages-rss-limit))
         (feed-url (concat starintel-pages-public-origin "/feed.xml"))
         (home-url (concat starintel-pages-public-origin "/"))
         (latest (and recent (plist-get (car recent) :modified)))
         (body
          (concat
           "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
           "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\"><channel>"
           "<title>" (starintel-pages--xml-escape starintel-pages-site-title) "</title>"
           "<link>" home-url "</link>"
           "<description>StarIntel Auto Research updates</description>"
           "<language>en-us</language>"
           "<atom:link href=\"" feed-url "\" rel=\"self\" type=\"application/rss+xml\"/>"
           (when latest
             (concat "<lastBuildDate>" (starintel-pages--rss-date latest) "</lastBuildDate>"))
           (mapconcat #'starintel-pages--rss-item recent "")
           "</channel></rss>\n")))
    (starintel-pages--write-file
     (expand-file-name "feed.xml" starintel-pages--output-directory)
     body)))

(defun starintel-pages--inject-rss-discovery ()
  (let ((tag
         (format
          "<link rel=\"alternate\" type=\"application/rss+xml\" title=\"%s RSS\" href=\"%s/feed.xml\">"
          (starintel-pages--xml-escape starintel-pages-site-title)
          starintel-pages-public-origin)))
    (dolist (path (directory-files-recursively
                   starintel-pages--output-directory "\\.html\\'"))
      (let ((document (with-temp-buffer
                        (insert-file-contents path)
                        (buffer-string))))
        (unless (string-match-p "application/rss+xml" document)
          (setq document
                (starintel-pages--insert-before
                 "</head>" (concat tag "\n") document))
          (with-temp-file path
            (insert document)))))))

(defun starintel-pages--publish-metadata (&rest _args)
  (starintel-pages--write-rss)
  (starintel-pages--inject-rss-discovery))

(advice-add 'starintel-pages-build :after #'starintel-pages--publish-metadata)

(provide 'starintel-pages-metadata)
;;; pages-metadata.el ends here
