# keybindings extension

When modifying the keybindings extension source:

- The immutable default menu configuration lives in `defaults.json` in this
  directory. Edit it for default bindings that ship with the extension.
- User-mutable state (currently the modal-editing toggle) lives in
  `~/.pi/agent/keybindings-ext.json`. Never write user state into
  `defaults.json`.
- Event names are `keybindings:ready`, `keybindings:suggest`,
  `keybindings:set-mode-emacs`, `keybindings:set-mode-vim`. The legacy
  `modal-editor:*` names are gone — update any extension using them.
- The internal editor class is still `VimEditor`; it is not exported.
- Slash command is `/kb` (`/kb bindings`, `/kb mode emacs|vim`).
