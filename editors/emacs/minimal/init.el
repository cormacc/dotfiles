;;; init.el --- Bootstrap for the minimal literate config -*- lexical-binding: t; -*-

;;; Commentary:

;; Thin bootstrap: pin the Elpaca core date, run the Elpaca installer, enable
;; `use-package' integration, then tangle and load the literate config.org.
;;
;; Everything configurable lives in config.org.  Keep this file mechanical.

;;; Code:

;;;; Elpaca core date
;;
;; Elpaca needs a YYYYMMDD "core date" to check dependency constraints against
;; the Elisp bundled with Emacs.  It normally derives this from
;; `emacs-build-time', which is nil on a nixpkgs build (`--disable-build-details').
;;
;; The elpaca wiki (https://github.com/progfolio/elpaca/wiki/Usage-with-Nix)
;; recommends scraping an 8-digit date out of `system-configuration-options'.
;; That only works for emacs-overlay's `emacs-git', whose store path carries a
;; date; the nixpkgs `emacs-pgtk' prefix is `.../<hash>-emacs-pgtk-31.1', with
;; no date at all.  So: try the wiki regexp, and fall back to the release date
;; of this Emacs from etc/HISTORY ("GNU Emacs 31.1 (2026-08-24)").
;;
;; Bump `my/emacs-release-dates' when the Emacs version changes.
(defvar my/emacs-release-dates
  '(("30.2" . 20250814)
    ("31.1" . 20260824))
  "Alist of Emacs version to release date, as reported by etc/HISTORY.")

(defun my/emacs-core-date ()
  "Return a YYYYMMDD integer describing the Elisp bundled with this Emacs."
  (or (and (stringp system-configuration-options)
           (string-match "--prefix.*emacs.*\\([[:digit:]]\\{8\\}\\)"
                         system-configuration-options)
           (string-to-number (match-string 1 system-configuration-options)))
      (cdr (assoc emacs-version my/emacs-release-dates))
      ;; Unknown Emacs: today is wrong but never blocks the bootstrap.
      (string-to-number (format-time-string "%Y%m%d"))))

;; Must run before elpaca.el is loaded, i.e. before the installer below.
(unless emacs-build-time
  (setq elpaca-core-date (list (my/emacs-core-date))))

;;;; Elpaca installer (verbatim from the Elpaca README, installer version 0.12)

(defvar elpaca-installer-version 0.12)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-sources-directory (expand-file-name "sources/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1 :inherit ignore
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca-activate)))
(let* ((repo  (expand-file-name "elpaca/" elpaca-sources-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (when (<= emacs-major-version 28) (require 'subr-x))
    (condition-case-unless-debug err
        (if-let* ((buffer (pop-to-buffer-same-window "*elpaca-bootstrap*"))
                  ((zerop (apply #'call-process `("git" nil ,buffer t "clone"
                                                  ,@(when-let* ((depth (plist-get order :depth)))
                                                      (list (format "--depth=%d" depth) "--no-single-branch"))
                                                  ,(plist-get order :repo) ,repo))))
                  ((zerop (call-process "git" nil buffer t "checkout"
                                        (or (plist-get order :ref) "--"))))
                  (emacs (concat invocation-directory invocation-name))
                  ((zerop (call-process emacs nil buffer nil "-Q" "-L" "." "--batch"
                                        "--eval" "(byte-recompile-directory \".\" 0 'force)")))
                  ((require 'elpaca))
                  ((elpaca-generate-autoloads "elpaca" repo)))
            (progn (message "%s" (buffer-string)) (kill-buffer buffer))
          (error "%s" (with-current-buffer buffer (buffer-string))))
      ((error) (warn "%s" err) (delete-directory repo 'recursive))))
  (unless (require 'elpaca-autoloads nil t)
    (require 'elpaca)
    (elpaca-generate-autoloads "elpaca" repo)
    (let ((load-source-file-function nil)) (load "./elpaca-autoloads"))))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

;;;; use-package integration

(elpaca elpaca-use-package
  (elpaca-use-package-mode))

;; `use-package-expand-minimally' nil wraps each :init/:config body in
;; `condition-case-unless-debug', so a failing block reports
;;   Error (use-package): PACKAGE/:config: <message>
;; and the rest of config.el still loads.  With t the error propagates and
;; silently truncates the file at the point of failure -- which is how a bare
;; (require 'nerd-icons) once took out every block below it.
;;
;; Measured over the 38 use-package forms in config.el: expanded code grows
;; 8.8k -> 25.8k chars and expansion takes 6.4ms -> 12.9ms, but startup is
;; unchanged (median `emacs-init-time' 248ms either way, 3 runs each).
(setq use-package-always-defer nil
      use-package-expand-minimally nil)

;;;; Literate configuration
;;
;; Tangled with the *built-in* org (9.8.x), never an Elpaca-installed one --
;; loading a second org version mid-session is the classic bootstrap conflict.
;; The config.org Home Manager link resolves into the dotfiles repository.
;; `org-babel-load-file' would tangle beside that real source but then load the
;; older config.el beside the link.  Use an explicit runtime target so tangle
;; and load always refer to the same file outside the repository.
(let* ((org-file (expand-file-name "config.org" user-emacs-directory))
       (org-source (file-truename org-file))
       (el-file (expand-file-name "config.el" user-emacs-directory)))
  (when (or (not (file-exists-p el-file))
            (file-newer-than-file-p org-source el-file))
    (require 'ob-tangle)
    (org-babel-tangle-file org-source el-file "emacs-lisp"))
  (load el-file nil nil))

(provide 'init)
;;; init.el ends here
