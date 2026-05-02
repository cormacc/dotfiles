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

- Bare-Space and bare-, in Normal mode emit `leader-menu:open`
  with `{ rootKey: " " | "," }`. Do not import `leader-menu`; the
  event is the entire contract.
- `vim-mode:enable` / `vim-mode:disable` may carry `{ source?: string }`
  for nicer notifications, but the editor must tolerate an empty `{}`.
- `editor:width-constraint` is the standard pi cross-extension event
  used by side-panel-rendering extensions (e.g. `git-diff`). When
  modal is off, the listener still exists but is a no-op.

## Settings file + migration

- `~/.pi/agent/vim-mode.json` is the live settings file. Keys today:
  `modal: bool`, `debug: bool`. Add new keys via `loadUserSettings`
  / `saveUserSettings` so partial updates do not clobber unrelated
  fields.
- On first run, `migrateLegacySettings()` migrates from
  `~/.pi/agent/keybindings-ext.json` exactly once. After migration the
  legacy file is deleted to avoid drift.
- Other extensions that historically read the legacy file directly
  (notably `tasks/overlay.ts` for the `debug` flag) have been
  retargeted to `vim-mode.json`. If you add another reader, do not
  resurrect the legacy path.

## Tests

This extension has no unit tests today. Sanity-check after edits by:

1. `/vim-mode toggle` to confirm the editor swaps in/out cleanly.
2. Pressing `Esc` to enter Normal mode, then exercising motions
   (`hjkl`, `w`, `b`, `e`), operators (`dw`, `ciw`), text objects
   (`di(`, `da{`), counts (`5x`, `3w`), and dot-repeat (`.`).
3. Pressing bare `Space` in Normal mode and confirming the
   leader-menu overlay opens (delegated via event).
4. Toggling via `Space t E e` from leader-menu to confirm the
   cross-extension event flows the other way.
