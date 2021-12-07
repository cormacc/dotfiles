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

;;; Commentary:

;; See the Spacemacs documentation and FAQs for instructions on how to implement
;; a new layer:
;;
;;   SPC h SPC layers RET
;;
;;
;; Briefly, each package to be installed or configured by this layer should be
;; added to `my-org-packages'. Then, for each package PACKAGE:
;;
;; - If PACKAGE is not referenced by any other Spacemacs layer, define a
;;   function `my-org/init-PACKAGE' to load and initialize the package.

;; - Otherwise, PACKAGE is already referenced by another Spacemacs layer, so
;;   define the functions `my-org/pre-init-PACKAGE' and/or
;;   `my-org/post-init-PACKAGE' to customize the package as it is loaded.

;;; Code:

(defconst my-org-packages
  '(
     (org-archive-subtree-hierarchical :location local)
     (org :location built-in)
     org-web-tools
     org-sidebar
     ;; magit-todos
     ob-typescript
     leuven-theme
     org-roam
     )
  "The list of Lisp packages required by the my-org layer.

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


;; (defun my-org/init-org-archive-hierarchical ()
;;   (use-package org-archive-hierarchical)
;;   )

(defun my-org/post-init-org ()
  ;;Quick-and-dirty import of existing config from .spacemacs
  (with-eval-after-load 'org (my-org/config))
  )

(defun my-org/init-org-web-tools ()
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

(defun my-org/init-org-sidebar ()
  :defer t)

;; magit-todos added to spacemacs git layer April 2021
;; (defun my-org/init-magit-todos ()
;;   :defer t
;;   :init (add-hook 'magit-mode-hook 'magit-todos-mode))

(defun my-org/init-org-archive-subtree-hierarchical ()
  (use-package org-archive-subtree-hierarchical))

(defun my-org/post-init-org-archive-subtree-hierarchical ()
  (setq org-archive-default-command 'org-archive-subtree-hierarchical))

(defun my-org/init-ob-typescript ()
  :defer t)

(defun my-org/init-leuven-theme ()
  :defer t)

;; See https://systemcrafters.net/build-a-second-brain-in-emacs/capturing-notes-efficiently/
(defun my-org/post-init-org-roam ()
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
           :if-new (file+head "%<%Y%m%d%H%M%S>-${slug}.org" "#+title: ${title}\n#+date: %<%Y%m%d>\n")
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
  (setq org-roam-v2-ack t)
  (setq org-roam-dailies-directory "dailies/")
  (setq org-roam-dailies-capture-templates
        '(("d" "default" entry
           "* %?"
           :target (file+head "%<%Y-%m-%d>.org"
                              "#+title: %<%Y-%m-%d>\n"))))

  )
