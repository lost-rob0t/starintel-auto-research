;;; star-lang-mode-tests.el --- Tests for Star-Lang mode -*- lexical-binding: t; -*-

(require 'ert)
(load-file
 (expand-file-name
  "star-lang-mode.el"
  (file-name-directory (or load-file-name buffer-file-name))))

(ert-deftest star-lang-mode-activates ()
  (with-temp-buffer
    (star-lang-mode)
    (should (eq major-mode 'star-lang-mode))
    (should (member #'star-lang-flymake-backend
                    flymake-diagnostic-functions))
    (should (equal comment-start ";"))))

(ert-deftest star-lang-auto-mode-registration ()
  (should (eq (cdr (assoc "\\.star\\'" auto-mode-alist))
              'star-lang-mode)))

(ert-deftest star-lang-policy-arguments ()
  (let ((star-lang-production-policy nil))
    (should-not (star-lang--policy-arguments)))
  (let ((star-lang-production-policy t))
    (should (equal (star-lang--policy-arguments)
                   '("--production")))))

(ert-deftest star-lang-diagnostic-forms ()
  (let ((buffer (generate-new-buffer " *star-lang-diagnostics-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (insert "(:severity :error :code :broken :message \"bad\" :line 2 :column 4)\n")
          (insert "(:severity :warning :code :warn :message \"careful\" :line 3 :column 1)\n")
          (let ((forms (star-lang--read-diagnostic-forms buffer)))
            (should (= (length forms) 2))
            (should (eq (plist-get (first forms) :code) :broken))
            (should (eq (plist-get (second forms) :severity) :warning))))
      (kill-buffer buffer))))

(ert-deftest star-lang-diagnostic-region-clamps ()
  (with-temp-buffer
    (insert "one\ntwo\n")
    (pcase-let ((`(,begin . ,end)
                 (star-lang--diagnostic-region
                  (current-buffer) 2 2)))
      (should (= begin 6))
      (should (= end 7)))))

(ert-deftest star-lang-flymake-without-file ()
  (with-temp-buffer
    (star-lang-mode)
    (let (reported)
      (star-lang-flymake-backend
       (lambda (diagnostics)
         (setq reported diagnostics)))
      (should-not reported))))

(provide 'star-lang-mode-tests)

;;; star-lang-mode-tests.el ends here
