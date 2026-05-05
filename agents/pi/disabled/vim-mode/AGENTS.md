# vim-mode — agent notes

## Scope

This extension owns *only* the modal editor. Leader-menu chord
discovery and dispatch live in the sibling `leader-menu` extension.
Do not add leader-menu code, default chord configuration, or
contribution-API logic here — those belong in `leader-menu`.

## Editing rules

- The `VimEditor` class is intentionally large (~2200 lines) and
  monolithic today. A planned follow-up decomposes it into
  `index.ts` + `buffer.ts` + `core.ts` mirroring the upstream
  `vim-motions-pi` shape; do not preemptively start that decomposition
  in unrelated PRs.
- `Mode`, `Pos`, `Range`, `EditorState`, and `Recordable` types are
  duplicated from pi-tui's `Editor` internal shape. If pi-tui exposes
  these officially in a future version, switch to importing them.
- Reserved-key list maintained at the top of the file (the
  normal-mode operator/motion keys) is duplicated in
  `leader-menu/index.ts` for clash warnings. Keep both in sync if you
  add new normal-mode keys.

## Cross-extension contract

- Bare leader keys in Normal mode emit `leader-menu:open` with
  `{ rootKey: string }`. The set of recognised leader keys is
  delivered via the `leader-menu:keys-resolved` event — this
  extension does not read the leader-menu settings file directly.
- Do not import `leader-menu`; events are the entire contract.
- `editor:width-constraint` is the standard pi cross-extension event
  used by side-panel-rendering extensions (e.g. `git-diff`).

## Settings

This extension has no settings file of its own. The only knob is the
shared `debug` flag (per-keypress logger), which lives in
`~/.pi/agent/leader-menu.json`. It is loaded synchronously on editor
construction via `loadDebugFlag()` near the entry point. Do not
resurrect a vim-mode-specific settings file; if you need a new knob,
add it to `leader-menu.json` and document the cross-extension shared
ownership in both READMEs.

The pre-split `~/.pi/agent/vim-mode.json` and `keybindings-ext.json`
files are migrated automatically by `leader-menu` on first run. The
migration is a one-shot copy of the `debug` field; the legacy `modal`
field is intentionally dropped (vim-mode is always on when loaded).

## Tests

This extension has no unit tests today. Sanity-check after edits by:

1. Confirm the editor is installed at session_start (status line
   shows `INSERT` / `NORMAL`, not pi's default editor footer).
2. Pressing `Esc` to enter Normal mode, then exercising motions
   (`hjkl`, `w`, `b`, `e`), operators (`dw`, `ciw`), text objects
   (`di(`, `da{`), counts (`5x`, `3w`), and dot-repeat (`.`).
3. Pressing the configured global leader (default `Space`) in Normal
   mode and confirming the leader-menu overlay opens (delegated via
   `leader-menu:open` event).
