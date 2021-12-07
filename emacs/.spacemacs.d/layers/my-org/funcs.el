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

(defun my-org/config ()
  ;; For interop, prefer visual to actual indentation
  (setq org-startup-indented t)
  (add-hook 'org-mode-hook #'visual-line-mode)
  (setq org-confirm-babel-evaluate nil
    org-src-fontify-natively t
    org-src-tab-acts-natively t
    org-startup-folded nil)
  ;; Output to docx rather than odf
  (setq org-odt-preferred-output-format "docx")
  ;; Allow a., A. etc. for lists
  (setq org-list-allow-alphabetical t)
  (require 'ob-ruby)
  (org-babel-do-load-languages
    'org-babel-load-languages
    '((C . t)
      (js . t)
      (plantuml . t)
      (python . t)
      (ruby . t)
      (shell . t)
      (typescript . t)
      ))
  ;; todo keywords
  ;; (setq org-todo-keywords
  ;;   (quote ((sequence "TODO(t)" "|" "DONE(d)"
  ;;             (sequence "TODO(t)" "MAYBE(m)" "NEXT(n)" "WAITING(w)" "|" "CANCELLED(c)" "FINISHED"i)))))
  (setq org-use-sub-superscripts "{}")
  (setq org-export-with-sub-superscripts "{}")
  (setq org-src-tab-acts-natively t)
  ;;BEGIN GTD
  ;; Pilfered from https://emacs.cafe/emacs/orgmode/gtd/2017/06/30/orgmode-gtd.html
  ;; See also: http://www.cachestocaches.com/2016/9/my-workflow-org-agenda/
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
  ;; (setq org-todo-keywords '((sequence "TODO(t)" "WAITING(w)" "|" "DONE(d)" "CANCELLED(c)")))
  (setq org-todo-keywords '((sequence "TODO(t)" "NEXT(n)" "WAITING(w)" "SOMEDAY(s)" "|" "DONE(d)" "CANCELLED(c)")))
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
