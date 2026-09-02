;;; init.el -*- lexical-binding: t; -*-

;; Fresh minimal Doom config. Authored from scratch (nothing ported from the
;; old hand-rolled config) -- see the change-record at
;; design/log/2026-09-02-replace-hand-rolled-doom-emacs-wiring-wi.org.
;;
;; This file is nix-managed (doomDir is types.pathInStore): editing it
;; requires a `home-manager switch` to take effect. Keep the module set
;; small -- every addition here needs re-verifying against the upstream
;; module tree at https://github.com/doomemacs/modules, and enlarges what a
;; rebuild can break. Day-to-day config belongs in the live-editable sibling
;; loaded by config.el instead.

(doom! :completion
       vertico            ; the search engine of the future

       :ui
       doom               ; what makes DOOM look the way it does
       dashboard          ; a nifty splash screen for Emacs
       modeline           ; snazzy, Atom-inspired modeline, plus API

       :editor
       (evil +everywhere) ; come to the dark side, we have cookies
       lispy
       multiple-cursors
       snippets           ; my elves. They type so I don't have to
       (whitespace +trim)

       :emacs
       dired              ; making dired pretty [functional]
       tramp
       undo               ; persistent, smarter undo for your inevitable mistakes
       vc                 ; version-control and Emacs, sitting in a tree

       :checkers
       syntax             ; tasing you for every semicolon you forget

       :tools
       direnv
       docker
       editorconfig
       llm
       lookup             ; navigate your code and its documentation
       (lsp +peek)
       magit              ; a git porcelain for Emacs
       pdf
       tree-sitter

       :lang
       (cc +lsp +tree-sitter)
       (clojure +lsp)
       emacs-lisp         ; drown in parentheses
       (markdown +lsp +tree-sitter)
       org                ; organize your plain life in plain text
       plantuml
       (python +lsp +tree-sitter)
       (ruby +lsp +tree-sitter)
       (sh +lsp)
       (web +lsp +tree-sitter)
       (yaml +lsp +tree-sitter)

       :config
       (default +bindings))
