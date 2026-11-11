;;; early-init.el --- Pre-frame setup for the minimal config -*- lexical-binding: t; -*-

;;; Commentary:

;; Loaded before the first frame and before package.el would normally
;; activate.  Everything here must be cheap: this is the default
;; configuration, so it runs on every bare `emacs' launch (see
;; editors/emacs/emacs.nix).
;;
;; This file is symlinked out of store to ~/.config/emacs, so edits take
;; effect on the next launch without a Home Manager switch.

;;; Code:

;; Elpaca manages packages; package.el must not activate anything.
(setq package-enable-at-startup nil)

;; Raise the GC ceiling for startup, then restore a sane steady-state value.
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 32 1024 1024)
                  gc-cons-percentage 0.1)))

;; Strip chrome before the first frame is mapped, so nothing flashes.
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(setq menu-bar-mode nil
      tool-bar-mode nil
      scroll-bar-mode nil
      inhibit-startup-screen t
      inhibit-startup-echo-area-message (user-login-name)
      initial-scratch-message nil
      frame-inhibit-implied-resize t
      frame-resize-pixelwise t
      use-dialog-box nil
      ring-bell-function #'ignore)

;; Native compilation is noisy on a fresh package set.  `defcustom' keeps a
;; value already set here, so these take effect when comp.el loads.
(setq native-comp-async-report-warnings-errors 'silent
      native-comp-warning-on-missing-source nil)

;; Without a deployment target, the GCC driver in the emacs-app cask's
;; libgccjit derives `-mmacosx-version-min' from the Darwin kernel version.
;; On Darwin 27 (macOS 27) it passes 18.0, clang rejects that value, and every
;; native compile fails.
;; An explicit deployment target overrides the derived value.  Child compile
;; processes inherit it through `process-environment'.
(when (and (eq system-type 'darwin)
           (not (getenv "MACOSX_DEPLOYMENT_TARGET"))
           (>= (string-to-number operating-system-release) 25))
  (setenv "MACOSX_DEPLOYMENT_TARGET" "26.0"))

;; An app started from the Dock, Finder or Spotlight inherits launchd's PATH
;; (/usr/bin:/bin:/usr/sbin:/sbin), so Home Manager and nix-darwin tools such
;; as rg are missing.  Insert the profile directories ahead of the system
;; directories, in nix-darwin's `environment.systemPath' order, then Homebrew.
;; A launch from a shell already has them, so nothing changes.
(when (eq system-type 'darwin)
  (let* ((wanted (list (expand-file-name "~/.nix-profile/bin")
                       (concat "/etc/profiles/per-user/" (user-login-name) "/bin")
                       "/run/current-system/sw/bin"
                       "/nix/var/nix/profiles/default/bin"
                       "/opt/homebrew/bin"
                       "/opt/homebrew/sbin"
                       "/usr/local/bin"))
         (path (split-string (or (getenv "PATH") "") path-separator t))
         (missing (delq nil (mapcar (lambda (dir)
                                      (and (not (member dir path))
                                           (file-directory-p dir)
                                           dir))
                                    wanted))))
    (when missing
      (let* ((tail (member "/usr/bin" path))
             (new (append (butlast path (length tail)) missing tail)))
        (setenv "PATH" (mapconcat #'identity new path-separator))
        (setq exec-path (append new (list exec-directory)))))))

;; Site-lisp default file loading is not used by this config.
(setq inhibit-default-init t)

(provide 'early-init)
;;; early-init.el ends here
