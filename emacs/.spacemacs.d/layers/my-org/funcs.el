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

;;Vulpea used to tag/untag org-roam files with TODOs as projects
;;This allows efficient org-agenda generation (only files with project tags parsed)
;;See https://d12frosted.io/posts/2021-01-16-task-management-with-roam-vol5.html
(defun my-org//vulpea-project-p ()
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

(defun my-org//vulpea-buffer-p ()
  "Return non-nil if the currently visited buffer is a note."
  (and buffer-file-name
       (string-prefix-p
        (expand-file-name (file-name-as-directory org-roam-directory))
        (file-name-directory buffer-file-name))))

(defun my-org/vulpea-project-update-tag ()
    "Update PROJECT tag in the current buffer."
    (when (and (not (active-minibuffer-window))
               (my-org//vulpea-buffer-p))
      (save-excursion
        (goto-char (point-min))
        (let* ((tags (vulpea-buffer-tags-get))
               (original-tags tags))
          (if (my-org//vulpea-project-p)
              (setq tags (cons "project" tags))
            (setq tags (remove "project" tags)))

          ;; cleanup duplicates
          (setq tags (seq-uniq tags))

          ;; update tags if changed
          (when (or (seq-difference tags original-tags)
                    (seq-difference original-tags tags))
            (apply #'vulpea-buffer-tags-set tags))))))

(defun my-org/vulpea-project-files ()
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

;; Replaced by my-org/inject... function below to avoid clobbering other agenda files outside roam dirs
;; (defun my-org/vulpea-agenda-files-update (&rest _)
;;   "Update the value of `org-agenda-files'."
;;   (setq org-agenda-files (my-org/vulpea-project-files)))

;; See https://github.com/d12frosted/d12frosted.io/issues/15#issuecomment-910213001
(defun my-org/inject-vulpea-project-files (org-agenda-files--output)
  "Wrapper for org-agenda-files, to add org-roam projects identified by vulpea to the list."
  (append org-agenda-files--output (vulpea-project-files)))
