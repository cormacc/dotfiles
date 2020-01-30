;;; packages.el --- my-org layer packages file for Spacemacs.
;;
;; Copyright (c) 2012-2018 Sylvain Benner & Contributors
;;
;; Author: Cormac Cannon <cormacc@nmdburger>
;; URL: https://github.com/syl20bnr/spacemacs
;;
;; This file is not part of GNU Emacs.
;;
;;; License: GPLv3
;;Compatibility layer for old org mode here: https://code.orgmode.org/bzg/org-mode/src/release_8.3.6/lisp/org-archive.el
;; (defun org-extract-archive-file (&optional location)
;;   "Extract and expand the file name from archive LOCATION.
;; if LOCATION is not given, the value of `org-archive-location' is used."
;;   (setq location (or location org-archive-location))
;;   (if (string-match "\\(.*\\)::\\(.*\\)" location)
;;     (if (= (match-beginning 1) (match-end 1))
;;       (buffer-file-name (buffer-base-buffer))
;;       (expand-file-name
;;         (format (match-string 1 location)
;;           (file-name-nondirectory
;;             (buffer-file-name (buffer-base-buffer))))))))

;; (defun org-extract-archive-heading (&optional location)
;;   "Extract the heading from archive LOCATION.
;; if LOCATION is not given, the value of `org-archive-location' is used."
;;   (setq location (or location org-archive-location))
;;   (if (string-match "\\(.*\\)::\\(.*\\)" location)
;;     (format (match-string 2 location)
;;       (file-name-nondirectory
;;         (buffer-file-name (buffer-base-buffer))))))

;; (defun org-local-archive-location ()
;;   (org-archive--compute-location
;;     (or (org-entry-get nil "ARCHIVE" 'inherit)
;;       org-archive-location))
;;   )


;; (defadvice org-archive-subtree (around fix-hierarchy activate)
;;   (let* ((fix-archive-p (and (not current-prefix-arg)
;;                              (not (use-region-p))))
;;          (afile (org-extract-archive-file (org-local-archive-location)))
;;           ;; (afile (org-archive--compute-location org-archive-location))
;;           ;; (afile (org-archive--compute-location "%s_archive::"))
;;          (buffer (or (find-buffer-visiting afile) (find-file-noselect afile))))
;;     ad-do-it
;;     (when fix-archive-p
;;       (with-current-buffer buffer
;;         (goto-char (point-max))
;;         (while (org-up-heading-safe))
;;         (let* ((olpath (org-entry-get (point) "ARCHIVE_OLPATH"))
;;                (path (and olpath (split-string olpath "/")))
;;                (level 1)
;;                tree-text)
;;           (when olpath
;;             (org-mark-subtree)
;;             (setq tree-text (buffer-substring (region-beginning) (region-end)))
;;             (let (this-command) (org-cut-subtree))
;;             (goto-char (point-min))
;;             (save-restriction
;;               (widen)
;;               (-each path
;;                 (lambda (heading)
;;                   (if (re-search-forward
;;                        (rx-to-string
;;                         `(: bol (repeat ,level "*") (1+ " ") ,heading)) nil t)
;;                       (org-narrow-to-subtree)
;;                     (goto-char (point-max))
;;                     (unless (looking-at "^")
;;                       (insert "\n"))
;;                     (insert (make-string level ?*)
;;                             " "
;;                             heading
;;                             "\n"))
;;                   (cl-incf level)))
;;               (widen)
;;               (org-end-of-subtree t t)
;;               (org-paste-subtree level tree-text))))))))


;; This is an alternative implementation using a local package, but doesn't work
;; (defun org-insert-struct (struct)
;;   "TODO"
;;   (interactive)
;;   (when struct
;;     (insert (car struct))
;;     (newline)
;;     (org-insert-struct (cdr struct))))

;; (defun org-archive-subtree ()
;;   (interactive)
;;   (org-archive-hierarchical)
;;   )

(defun my-org/config ()
  ;; For interop, prefer visual to actual indentation
  (setq org-startup-indented t)
  (add-hook 'org-mode-hook #'visual-line-mode)
  (setq org-confirm-babel-evaluate nil
    org-src-fontify-natively t
    org-src-tab-acts-natively t
    org-startup-folded nil)
  (require 'ob-ruby)
  (org-babel-do-load-languages
    'org-babel-load-languages
    '((ruby . t)
      (python . t)
      (shell . t)
      (C . t)
      (plantuml . t)))
  ;; todo keywords
  ;; (setq org-todo-keywords
  ;;   (quote ((sequence "TODO(t)" "|" "DONE(d)"
  ;;             (sequence "TASK(t)" "MAYBE(m)" "NEXT(n)" "WAITING(w)" "|" "CANCELLED(c)" "FINISHED")))))
  (setq org-use-sub-superscripts "{}")
  (setq org-export-with-sub-superscripts "{}")
  (setq org-src-tab-acts-natively t)
  ;;BEGIN GTD
  ;; Pilfered from https://emacs.cafe/emacs/orgmode/gtd/2017/06/30/orgmode-gtd.html
  (setq org-agenda-files '("~/org/gtd/inbox.org"
                            "~/org/gtd/gtd.org"
                            "~/org/gtd/reminders.org"))
  (setq org-capture-templates '(("t" "Todo [inbox]" entry
                                  (file+headline "~/org/gtd/inbox.org" "Tasks")
                                  "* TODO %i%?")
                                 ("r" "Tickler" entry
                                   (file+headline "~/org/gtd/reminders.org" "Reminders")
                                   "* %i%? \n %U")))
  (setq org-refile-targets '(("~/org/gtd/gtd.org" :maxlevel . 3)
                              ("~/org/gtd/someday.org" :level . 1)
                              ("~/org/gtd/reminders.org" :maxlevel . 2)))
  (setq org-todo-keywords '((sequence "TODO(t)" "WAITING(w)" "|" "DONE(d)" "CANCELLED(c)")))
  ;;TODO: add @home context -- also see skip section of website linked above to show only first item from each project...
  (setq org-agenda-custom-commands
    '(
       ("o" "At the office" tags-todo "@office"
         ((org-agenda-overriding-header "Office")
           (org-agenda-skip-function #'my-org-agenda-skip-all-siblings-but-first)))
       ("h" "At home" tags-todo "@home"
         ((org-agenda-overriding-header "Home")
           (org-agenda-skip-function #'my-org-agenda-skip-all-siblings-but-first)))
       ))

  (defun my-org-agenda-skip-all-siblings-but-first ()
    "Skip all but the first non-done entry."
    (let (should-skip-entry)
      (unless (org-current-is-todo)
        (setq should-skip-entry t))
      (save-excursion
        (while (and (not should-skip-entry) (org-goto-sibling t))
          (when (org-current-is-todo)
            (setq should-skip-entry t))))
      (when should-skip-entry
        (or (outline-next-heading)
          (goto-char (point-max))))))

  (defun org-current-is-todo ()
    (string= "TODO" (org-get-todo-state)))


  ;;END GTD
  (defun toggle-org-html-export-on-save ()
    (interactive)
    (if (memq 'org-html-export-to-html after-save-hook)
      (progn
        (remove-hook 'after-save-hook 'org-html-export-to-html t)
        (message "Disabled org html export on save for current buffer..."))
      (add-hook 'after-save-hook 'org-html-export-to-html nil t)
      (message "Enabled org html export on save for current buffer..."))))

;; See https://github.com/alphapapa/org-sidebar/blob/master/examples.org
;; This is nice in theory, but more work required -- some conflicts with spacemacs keybindings?
(defun my-org/gtd-sidebar ()
  "Display my GTD sidebar."
  (interactive)
  (org-sidebar
   :sidebars (make-org-sidebar
              :name "GTD"
              :description "Get things done"
              :items (org-ql (org-agenda-files)
                             (and (not (done))
                                  (or (deadline auto)
                                      (scheduled :to today)))
                             :action element-with-markers))))
