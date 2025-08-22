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

;;; Commentary:

;; See the Spacemacs documentation and FAQs for instructions on how to implement
;; a new layer:
;;
;;   SPC h SPC layers RET
;;
;;
;; Briefly, each package to be installed or configured by this layer should be
;; added to `org-user-packages'. Then, for each package PACKAGE:
;;
;; - If PACKAGE is not referenced by any other Spacemacs layer, define a
;;   function `org-user/init-PACKAGE' to load and initialize the package.

;; - Otherwise, PACKAGE is already referenced by another Spacemacs layer, so
;;   define the functions `org-user/pre-init-PACKAGE' and/or
;;   `org-user/post-init-PACKAGE' to customize the package as it is loaded.

;;; Code:

(defconst org-user-packages
  '(
    (org-archive-subtree-hierarchical :location local)
    org
    org-web-tools
    org-sidebar
    ;; org-super-agenda
    org-roam-bibtex
    ;; magit-todos
    ob-clojurescript
    ob-typescript
    ;; leuven-theme
    org-roam
    ob-mermaid
    ;; excorporate
    ;; (vulpea :location (recipe
    ;;                    :fetcher github
    ;;                    :repo "d12frosted/vulpea"
    ;;                    :branch "master"))
    )
  "The list of Lisp packages required by the org-user layer.

Each entry is either:

1. A symbol, which is interpreted as a package to be installed, or

2. A list of the form (PACKAGE KEYS...), where PACKAGE is the
    name of the package to be installed or loaded, and KEYS are
    any number of keyword-value-pairs.

    The following keys are accepted:

    - :excluded (t or nil): Prevent the package from being loaded
      if value is non-nil

    - :location: Specify a custom installation location.
      The following values are legal:

      - The symbol `elpa' (default) means PACKAGE will be
        installed using the Emacs package manager.

      - The symbol `local' directs Spacemacs to load the file at
        `./local/PACKAGE/PACKAGE.el'

      - A list beginning with the symbol `recipe' is a melpa
        recipe.  See: https://github.com/milkypostman/melpa#recipe-format")


;; (defun org-user/init-org-archive-hierarchical ()
;;   (use-package org-archive-hierarchical)
;;   )

(defun org-user/post-init-org ()
  ;;Quick-and-dirty import of existing config from .spacemacs
  (with-eval-after-load 'org (org-user/config))
  ;;TODO: Set path to mmdc?
  (spacemacs|use-package-add-hook org
    :post-config (add-to-list 'org-babel-load-languages '(mermaid . t))))


(defun org-user/init-ob-mermaid ()
  (use-package ob-mermaid))

(defun org-user/init-org-web-tools ()
  :defer t
  :init (progn
          (spacemacs/declare-prefix-for-mode 'org-mode "mw" "web")
          (spacemacs/set-leader-keys-for-major-mode 'org-mode
            "iw" 'org-web-tools-insert-link-for-url
            "iW" 'org-web-tools-insert-web-page-as-entry
            "wc" 'org-web-tools-convert-links-to-page-entries
            "wa" 'org-web-tools-archive-attach
            "wv" 'org-web-tools-archive-view)
          )
  )

;; (defun org-user/init-org-super-agenda ()
;;   :defer t)

;; (defun org-user/post-init-org-super-agenda ()
;;   (setq org-agenda-custom-commands
;;         '(
;;           ("w" "At work" tags-todo "@work"
;;            ((org-agenda-overriding-header "Work")
;;             (org-agenda-skip-function #'org-user-agenda-skip-all-siblings-but-first)))
;;           ("h" "At home" tags-todo "@home"
;;            ((org-agenda-overriding-header "Home")
;;             (org-agenda-skip-function #'org-user-agenda-skip-all-siblings-but-first)))
;;           ("o" "Overview"
;;            ;;; Adapted from https://hugocisneros.com/org-config/
;;            ((agenda "" ((org-agenda-span 'day)
;;                         (org-super-agenda-groups
;;                          '((:name "Today"
;;                                   :time-grid t
;;                                   :date today
;;                                   :todo "TODAY"
;;                                   :scheduled today
;;                                   :order 1)))))
;;             (alltodo "" ((org-agenda-overriding-header "")
;;                          (org-super-agenda-groups
;;                           '(;; Each group has an implicit boolean OR operator between its selectors.
;;                             (:name "Today"
;;                                    :deadline today
;;                                    :face (:background "black"))
;;                             (:name "Overdue"
;;                                    :and (:deadline past :todo ("TODO" "WAITING" "HOLD" "NEXT"))
;;                                    :face (:background "#7f1b19"))
;;                             ;; (:name "Work Important"
;;                             ;;        :and (:priority>= "B" :category "Work" :todo ("TODO" "NEXT")))
;;                             ;; (:name "Work other"
;;                             ;;        :and (:category "Work" :todo ("TODO" "NEXT")))
;;                             (:name "Important"
;;                                    :priority "A")
;;                             (:priority<= "B"
;;                                          ;; Show this section after "Today" and "Important", because
;;                                          ;; their order is unspecified, defaulting to 0. Sections
;;                                          ;; are displayed lowest-number-first.
;;                                          :order 1)
;;                             ;; (:name "Papers"
;;                             ;;        :file-path "org/roam/notes")
;;                             (:name "Waiting"
;;                                    :todo "WAITING"
;;                                    :order 9)
;;                             (:name "Someday"
;;                                    :todo "SOMEDAY"
;;                                    :order 10)))))))

;;           ))
;;   (add-hook 'org-agenda-mode-hook 'org-super-agenda-mode)
;;   )

(defun org-user/init-org-sidebar ()
  :defer t)

(defun org-user/init-org-archive-subtree-hierarchical ()
  (use-package org-archive-subtree-hierarchical))

(defun org-user/post-init-org-archive-subtree-hierarchical ()
  (setq org-archive-default-command 'org-archive-subtree-hierarchical))

(defun org-user/init-ob-clojurescript ()
  :defer t)

(defun org-user/init-ob-typescript ()
  :defer t)

;; (defun org-user/init-leuven-theme ()
;;   :defer t)

;; See https://d12frosted.io/posts/2021-01-16-task-management-with-roam-vol5.html
;; (defun org-user/init-vulpea ()
;;   (use-package vulpea
;;     ;; Not deferring, as 'vulpea-buffer-tags-get' not tagged with ;;;###autoload upstream...
;;     ;; :defer t
;;     :after org-roam
;;     :ensure t
;;     ;; hook into org-roam-db-autosync-mode you wish to enable
;;     ;; persistence of meta values (see respective section in README to
;;     ;; find out what meta means)
;;     ;; :hook ((org-roam-db-autosync-mode . vulpea-db-autosync-enable)))
;;     ;; As the hook approach isn't working for me in spacemacs...
;;     :init (vulpea-db-autosync-enable)
;;     ))

;; (defun org-user/post-init-vulpea ()
;;   (add-hook 'find-file-hook #'org-user/vulpea-project-update-tag)
;;   (add-hook 'before-save-hook #'org-user/vulpea-project-update-tag)
;;   ;; (advice-add 'org-agenda :before #'org-user/vulpea-agenda-files-update)
;;   (advice-add 'org-agenda-files :filter-return #'org-user/inject-vulpea-project-files)
;;   ;; As the hook approach isn't working for me in spacemacs...
;;   ;; (vulpea-db-autosync-enable)
;;   )

(defun org-user/pre-init-org-roam ()
  (if org-user-roam-directory (setq org-roam-directory org-user-roam-directory)))

;; See https://systemcrafters.net/build-a-second-brain-in-emacs/capturing-notes-efficiently/
(defun org-user/post-init-org-roam ()
  (setq org-roam-capture-templates
        '(("d" "default" plain
           "%?"
           :if-new (file+head "${slug}.org" "#+title: ${title}\n#+date: %<%Y%m%d>\n#+filetags: topic")
           :unnarrowed t)
          ("m" "meeting" plain
           "* Agenda\n\n%?\n\n* Attendees\n- Cormac Cannon\n- \n\n* Notes\n\n"
           :if-new (file+head "meeting-${slug}-%<%Y%m%d%H%M%S>.org" "#+title: ${title}\n#+date: %<%Y%m%d>\n")
           :unnarrowed t)
          ("t" "timestamped" plain
           "%?"
           :if-new (file+head "${slug}-%<%Y%m%d%H%M%S>.org" "#+title: ${title}\n#+date: %<%Y%m%d>\n")
           :unnarrowed t)
          ("l" "programming language" plain
           "%?"
           :if-new (file+head "${slug}.org" "#+title: ${title}\n#+date: %<%Y%m%d>\n#+filetags: tech lang\n")
           :unnarrowed t)
          ("p" "project" plain
           "* Goals\n\n%?\n\n* Tasks\n\n** TODO Add initial tasks\n\n* Dates\n\n"
           :if-new (file+head "${slug}.org" "#+title: ${title}\n#+date: %<%Y%m%d>\n#+filetags: project\n")
           :unnarrowed t))
        )
  ;; Required for org-export to work -- see https://github.com/org-roam/org-roam/issues/2046
  (setq org-id-track-globally t)
  (setq org-roam-v2-ack t)
  (setq org-roam-dailies-directory "dailies/")
  (setq org-roam-dailies-capture-templates
        '(("d" "default" entry
           "* %?"
           :target (file+head "%<%Y-%m-%d>.org"
                              "#+title: %<%Y-%m-%d>\n"))))

  )

;; BYPASSING EXCORPORATE INIT FOR NOW - simple auth permanently disabled for EWS.....
;; (defun org-user/init-excorporate ()
;;  :defer t)

;; (defun org-user/post-init-excorporate ()
;;   ;; Password cached in .authinfo
;;  (if org-user-o365
;;       ;; N.B. client-identifier from here: https://gitlab.gnome.org/GNOME/evolution/-/wikis/EWS-OAuth2
;;      (setq excorporate-configuration `((client-identifier . "20460e5d-ce91-49af-a3a5-70b6be7486d1")
;;                                       (login_hint . ,(org-user/extract-o365-username)))))


;;   ;; Excorporate imports to emacs diary -- connect this to org-agenda
;;  (setq org-agenda-include-diary t)
;;  (excorporate)
;;  (add-hook 'org-agenda-cleanup-fancy-diary-hook 'org-user/excorporate-diary-update-hook )
;;  )

;;; See https://github.com/org-roam/org-roam-bibtex
(defun org-user/init-org-roam-bibtex ()
  (use-package org-roam-bibtex
    :after org-roam
                                        ; optional: if using Org-ref v2 or v3 citation links -- probably better to use new org-cite instead?
    ;;:config
    ;;(require 'org-ref)
    ))
