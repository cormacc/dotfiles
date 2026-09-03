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

;; Site-lisp default file loading is not used by this config.
(setq inhibit-default-init t)

(provide 'early-init)
;;; early-init.el ends here
