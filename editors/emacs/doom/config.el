;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; This file is intentionally a stub. `init.el` and `packages.el` are the
;; in-store, nix-managed half of this Doom config (doomDir is
;; types.pathInStore, so they must be git-tracked and only take effect via a
;; rebuild). Day-to-day customisation instead lives in the live-editable
;; sibling file loaded below, so it can be edited with no rebuild required.
(load (expand-file-name "~/dotfiles/editors/emacs/doom/config-live.el") 'noerror 'nomessage)
