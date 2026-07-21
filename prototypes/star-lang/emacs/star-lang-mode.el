;;; star-lang-mode.el --- Star-Lang editing and Flymake support -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'compile)
(require 'flymake)
(require 'lisp-mode)

(defgroup star-lang nil
  "Editing and tooling for Star-Lang."
  :group 'languages)

(defcustom star-lang-executable "star-lang"
  "Path to the Star-Lang command-line executable."
  :type 'string
  :group 'star-lang)

(defcustom star-lang-production-policy nil
  "Use production policy for compile and lint commands."
  :type 'boolean
  :group 'star-lang)

(defconst star-lang--top-level-forms
  '("analysis" "sequence" "from" "filter" "map" "flat-map"
    "through" "parallel" "branch" "then" "else" "checkpoint"
    "into" "attach-dataset" "define-actor" "start-actor"
    "stop-actor" "define-couchdb-source" "define-rabbitmq-source"
    "load-documents" "define-message" "define-supervisor" "set"
    "loop" "send" "emit"))

(defconst star-lang--clause-forms
  '("for" "in" "when" "unless" "do" "collect" "append" "and"
    "or" "not" "equal" "document-ref" "document-type-p"
    "actor-ref" "dataset" "list" "length"))

(defconst star-lang-font-lock-keywords
  `((,(regexp-opt star-lang--top-level-forms 'symbols)
     . font-lock-keyword-face)
    (,(regexp-opt star-lang--clause-forms 'symbols)
     . font-lock-builtin-face)
    ("\\_<:\\(?:accepts\\|ack\\|channel\\|database\\|dataset\\|decoder\\|declare\\|dispatcher\\|effects\\|exchange\\|host\\|keys\\|limit\\|max-restarts\\|name\\|on-exhausted\\|parent\\|password\\|path\\|port\\|queue\\|queue-size\\|receive\\|restart\\|routing-key\\|schema\\|server\\|state\\|strategy\\|username\\|version\\|vhost\\)\\_>"
     . font-lock-constant-face)))

(defvar star-lang-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map lisp-mode-map)
    (define-key map (kbd "C-c C-c") #'star-lang-compile-buffer)
    (define-key map (kbd "C-c C-l") #'star-lang-lint-buffer)
    (define-key map (kbd "C-c C-e") #'star-lang-explain-buffer)
    (define-key map (kbd "C-c C-g") #'star-lang-graph-buffer)
    map))

(defun star-lang--policy-arguments ()
  (when star-lang-production-policy
    '("--production")))

(defun star-lang--buffer-file ()
  (or buffer-file-name
      (user-error "The Star-Lang buffer is not visiting a file")))

(defun star-lang--shell-command (command file)
  (mapconcat
   #'shell-quote-argument
   (append (list star-lang-executable command file)
           (star-lang--policy-arguments))
   " "))

(defun star-lang--compilation-command (command)
  (let* ((file (star-lang--buffer-file))
         (default-directory
          (or (locate-dominating-file file ".git")
              default-directory)))
    (save-buffer)
    (compilation-start
     (star-lang--shell-command command file)
     'compilation-mode
     (lambda (_) (format "*Star-Lang %s*" command)))))

(defun star-lang-compile-buffer ()
  "Compile the current Star-Lang file."
  (interactive)
  (star-lang--compilation-command "compile"))

(defun star-lang-lint-buffer ()
  "Lint the current Star-Lang file."
  (interactive)
  (star-lang--compilation-command "lint"))

(defun star-lang-explain-buffer ()
  "Explain the compiled plan for the current Star-Lang file."
  (interactive)
  (star-lang--compilation-command "explain"))

(defun star-lang-graph-buffer ()
  "Write the current plan graph to a dedicated buffer."
  (interactive)
  (let* ((file (star-lang--buffer-file))
         (buffer (get-buffer-create "*Star-Lang Graph*"))
         (arguments
          (append (list "graph" file)
                  (star-lang--policy-arguments))))
    (save-buffer)
    (with-current-buffer buffer
      (erase-buffer)
      (let ((status
              (apply #'call-process
                     star-lang-executable nil buffer nil arguments)))
        (unless (zerop status)
          (error "Star-Lang graph command failed with status %s" status)))
      (goto-char (point-min))
      (when (fboundp 'graphviz-dot-mode)
        (graphviz-dot-mode)))
    (pop-to-buffer buffer)))

(defun star-lang--diagnostic-region (source line column)
  (with-current-buffer source
    (save-excursion
      (goto-char (point-min))
      (forward-line (max 0 (1- (or line 1))))
      (move-to-column (max 0 (1- (or column 1))))
      (let ((begin (point)))
        (cons begin
              (min (point-max) (1+ begin)))))))

(defun star-lang--read-diagnostic-forms (buffer)
  (with-current-buffer buffer
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file nil)
        (invalid-read-syntax nil))
      (nreverse forms))))

(defun star-lang--flymake-report (source report-fn process-buffer status)
  (unwind-protect
      (let ((forms (star-lang--read-diagnostic-forms process-buffer))
            diagnostics)
        (dolist (form forms)
          (when (and (listp form) (plist-get form :message))
            (pcase-let ((`(,begin . ,end)
                         (star-lang--diagnostic-region
                          source
                          (plist-get form :line)
                          (plist-get form :column))))
              (push
               (flymake-make-diagnostic
                source begin end
                (if (eq (plist-get form :severity) :warning)
                    :warning
                  :error)
                (format "%s: %s"
                        (or (plist-get form :code) :star-lang)
                        (plist-get form :message)))
               diagnostics))))
        (when (and (null diagnostics) (not (zerop status)))
          (with-current-buffer source
            (push
             (flymake-make-diagnostic
              source (point-min) (min (point-max) (1+ (point-min)))
              :error
              "Star-Lang lint failed before structured diagnostics were produced")
             diagnostics)))
        (funcall report-fn (nreverse diagnostics)))
    (kill-buffer process-buffer)))

(defun star-lang-flymake-backend (report-fn &rest _args)
  "Run Star-Lang lint and report diagnostics through Flymake."
  (unless buffer-file-name
    (funcall report-fn nil)
    (cl-return-from star-lang-flymake-backend))
  (let* ((source (current-buffer))
         (process-buffer (generate-new-buffer " *star-lang-flymake*"))
         (command
          (append (list star-lang-executable "lint" buffer-file-name)
                  (star-lang--policy-arguments)))
         (process
          (make-process
           :name "star-lang-flymake"
           :buffer process-buffer
           :command command
           :noquery t
           :connection-type 'pipe
           :sentinel
           (lambda (process _event)
             (when (memq (process-status process) '(exit signal))
               (star-lang--flymake-report
                source report-fn process-buffer
                (process-exit-status process)))))))
    (process-put process 'source source)))

;;;###autoload
(define-derived-mode star-lang-mode lisp-mode "Star-Lang"
  "Major mode for Star-Lang source files."
  (setq-local font-lock-defaults '(star-lang-font-lock-keywords))
  (setq-local comment-start ";")
  (setq-local comment-end "")
  (add-hook 'flymake-diagnostic-functions
            #'star-lang-flymake-backend nil t))

(dolist (form '(analysis sequence define-actor define-message
                define-supervisor define-couchdb-source
                define-rabbitmq-source loop branch then else))
  (put form 'lisp-indent-function 1))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.star\\'" . star-lang-mode))

(provide 'star-lang-mode)

;;; star-lang-mode.el ends here
