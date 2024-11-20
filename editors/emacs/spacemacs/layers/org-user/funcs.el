;;; packages.el --- org-user layer packages file for Spacemacs.
;;
;; Copyright (c) 2012-2018 Sylvain Benner & Contributors
;;
;; Author: Cormac Cannon <cormacc@nmdburger>
;; URL: https://github.com/syl20bnr/spacemacs
;;
;; This file is not part of GNU Emacs.
;;
;;; License: GPLv3

(defun org-user/configure-babel ()
  (setq org-confirm-babel-evaluate nil)
  (require 'ob-ruby)
  ;; Configure clojure backend to use babashka -- otherwise need leiningen and a running repl to eval codeblocks
  (require 'ob-clojure)
  (setq org-babel-clojure-backend 'babashka)
  ;; TODO Remind myself why this is necessary.... and why not necessary for clojure...
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((C . t)
     (emacs-lisp . t)
     (http . t)
     (js . t)
     (plantuml . t)
     (python . t)
     (ruby . t)
     (shell . t)
     (typescript . t))))

(defun org-user/configure-exports ()
  (setq org-export-with-sub-superscripts "{}")
  ;; Output to docx rather than odf
  (setq org-odt-preferred-output-format "docx")
  ;; TODO: Figure out why I needed this?
  (defun toggle-org-html-export-on-save ()
    (interactive)
    (if (memq 'org-html-export-to-html after-save-hook)
        (progn
          (remove-hook 'after-save-hook 'org-html-export-to-html t)
          (message "Disabled org html export on save for current buffer..."))
      (add-hook 'after-save-hook 'org-html-export-to-html nil t)
      (message "Enabled org html export on save for current buffer..."))))


(defun org-user/configure-gtd ()
  ;; Pilfered from https://emacs.cafe/emacs/orgmode/gtd/2017/06/30/orgmode-gtd.html
  ;; See also: http://www.cachestocaches.com/2016/9/my-workflow-org-agenda/
  ;;TODO: add @home context -- also see skip section of website linked above to show only first item from each project...
  (setq org-agenda-files '("~/notes/gtd/inbox.org"
                           "~/notes/gtd/gtd.org"
                           "~/notes/gtd/reminders.org"))
  (setq org-capture-templates '(("t" "Todo [inbox]" entry
                                 (file+headline "~/notes/gtd/inbox.org" "Tasks")
                                 "* TODO %i%?")
                                ("r" "Tickler" entry
                                 (file+headline "~/notes/gtd/reminders.org" "Reminders")
                                 "* %i%? \n %U")))
  (setq org-refile-targets '(("~/notes/gtd/gtd.org" :maxlevel . 3)
                             ("~/notes/gtd/someday.org" :level . 1)
                             ("~/notes/gtd/reminders.org" :maxlevel . 2)))
  (setq org-todo-keywords '((sequence "TODO(t)" "NEXT(n)" "WAITING(w)" "SOMEDAY(s)" "|" "DONE(d)" "CANCELLED(c)")))



  (defun org-current-is-todo ()
    (string= "TODO" (org-get-todo-state))))

(defun org-user/config ()
  ;; For interop, prefer visual to actual indentation
  (setq org-startup-indented t
        org-startup-folded nil)
  (add-hook 'org-mode-hook #'visual-line-mode)
  (setq org-src-fontify-natively t
        org-src-tab-acts-natively t)
  ;; Allow a., A. etc. for lists
  (setq org-list-allow-alphabetical t)
  (setq org-use-sub-superscripts "{}")

  (org-user/configure-babel)
  (org-user/configure-gtd)
  (org-user/configure-exports))

;; See https://github.com/alphapapa/org-sidebar/blob/master/examples.org
;; This is nice in theory, but more work required -- some conflicts with spacemacs keybindings?
(defun org-user/agenda-sidebar ()
  "Display my gtd + org-roam agenda sidebar."
  (interactive)
  (org-sidebar-ql
    (org-agenda-files)
    '(and (not (done))
          (or (deadline auto)
              (scheduled :to today)))
    :title "Agenda"
    )
  )

;;Vulpea used to tag/untag org-roam files with TODOs as projects
;;This allows efficient org-agenda generation (only files with project tags parsed)
;;See https://d12frosted.io/posts/2021-01-16-task-management-with-roam-vol5.html
(defun org-user//vulpea-project-p ()
  "Return non-nil if current buffer has any todo entry.

TODO entries marked as done are ignored, meaning the this
function returns nil if current buffer contains only completed
tasks."
  (seq-find                                 ; (3)
   (lambda (type)
     (eq type 'todo))
   (org-element-map                         ; (2)
       (org-element-parse-buffer 'headline) ; (1)
       'headline
     (lambda (h)
       (org-element-property :todo-type h)))))

(defun org-user//vulpea-buffer-p ()
  "Return non-nil if the currently visited buffer is a note."
  (and buffer-file-name
       (string-prefix-p
        (expand-file-name (file-name-as-directory org-roam-directory))
        (file-name-directory buffer-file-name))))

(defun org-user/vulpea-project-update-tag ()
  "Update PROJECT tag in the current buffer."
  (when (and (not (active-minibuffer-window))
             (org-user//vulpea-buffer-p))
    (save-excursion
      (goto-char (point-min))
      (let* ((tags (vulpea-buffer-tags-get))
             (original-tags tags))
        (if (org-user//vulpea-project-p)
            (setq tags (cons "project" tags))
          (setq tags (remove "project" tags)))

        ;; cleanup duplicates
        (setq tags (seq-uniq tags))

        ;; update tags if changed
        (when (or (seq-difference tags original-tags)
                  (seq-difference original-tags tags))
          (apply #'vulpea-buffer-tags-set tags))))))

(defun org-user/vulpea-project-files ()
  "Return a list of note files containing 'project' tag." ;
  (seq-uniq
   (seq-map
    #'car
    (org-roam-db-query
     [:select [nodes:file]
              :from tags
              :left-join nodes
              :on (= tags:node-id nodes:id)
              :where (like tag (quote "%\"project\"%"))]))))

;; Replaced by org-user/inject... function below to avoid clobbering other agenda files outside roam dirs
;; (defun org-user/vulpea-agenda-files-update (&rest _)
;;   "Update the value of `org-agenda-files'."
;;   (setq org-agenda-files (org-user/vulpea-project-files)))

;; See https://github.com/d12frosted/d12frosted.io/issues/15#issuecomment-910213001
(defun org-user/inject-vulpea-project-files (org-agenda-files--output)
  "Wrapper for org-agenda-files, to add org-roam projects identified by vulpea to the list."
  (append org-agenda-files--output (org-user/vulpea-project-files)))

(defun org-user/excorporate-diary-update-hook ()
  "Call excorporate to update the diary for today."
  ;;To add the hook, add the line below to excorporate post-init
  ;;(add-hook 'org-agenda-cleanup-fancy-diary-hook 'ab/agenda-update-diary )
  (exco-diary-diary-advice (calendar-current-date) (calendar-current-date) #'message "diary updated"))

(defun org-user/auth-source-extract-username (host)
  "Extract username from an encrypted auth-source entry"
  (require 'auth-source)
  (let* ((auth (car (auth-source-search
                     :host host
                     :requires '(:user :secret)))))
    (plist-get auth :user)))

(defun org-user/extract-o365-username ()
  (org-user/auth-source-extract-username "outlook.office365.com"))
