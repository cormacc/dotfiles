;;; config-live.el -*- lexical-binding: t; -*-

;; Live-editable Doom configuration. Loaded by config.el at startup. Edit
;; this file directly -- changes take effect on the next Doom (doom-emacs)
;; restart, with no `home-manager switch` and no rebuild. Only `init.el` and
;; `packages.el` are in-store and require a rebuild to change.

;; Seed placeholders -- nothing ported from the old config; uncomment and
;; edit these to set your own values:
;; (setq doom-theme 'doom-vibrant)
;; (setq doom-font (font-spec :family "Fira Code" :size 14))
(setq doom-localleader-key "," ;;easier than <SPC m>, but overrides repeat
      doom-theme 'doom-dracula)

;; Some lsp defaults from https://gist.github.com/ericdallo/09217734a925148976e13b872b91e134
(use-package! lsp-mode
  :commands lsp
  :config
  (setq lsp-semantic-tokens-enable t)
  (add-hook 'lsp-after-apply-edits-hook (lambda (&rest _) (save-buffer)))) ;; save buffers after renaming

;; From https://github.com/doomemacs/modules/tree/main/modules/editor/lispy
(map! :after (lispy lispyville)
      :map lispy-mode-map-lispy
      ;; unbind individual bracket keys
      "[" nil
      "]" nil
      ;; re-bind commands bound to bracket keys by default
      "M-[" #'lispyville-previous-opening
      "M-]" #'lispyville.next-opening)
