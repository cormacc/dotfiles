# leader-menu — agent notes

## Scope

This extension owns *only* leader-menu discovery and dispatch. Modal
editing lives in the sibling `vim-mode` extension. Do not add
modal-editor code, mode toggling, or settings persistence here — those
all belong in `vim-mode`.

## Editing rules

- `defaults.json` is git-tracked and represents the project-level
  default leader bindings. Do not write user state to it.
- `VIM_NORMAL_RESERVED_KEYS` (in `index.ts`) is duplicated from
  `vim-mode/` by design rather than imported. Its purpose is purely to
  emit a soft warning at registration time when a contributed leader
  trigger would clash with the modal grammar; cross-extension imports
  are deliberately avoided so this extension stays usable in
  insert-only configurations where `vim-mode` isn't loaded. If the
  modal grammar's reserved keys change, update both sets.
- The contribution API (`leader-menu:register` event +
  `registerLeaderMenu()` helper) is consumed by every other extension
  in the repo. Treat its payload shape (`LeaderMenuRegistration`) as a
  stable interface and rev it only with a coordinated migration.

## Cross-extension contract with `vim-mode`

`Space t E v` and `Space t E e` are dispatched as plain events
(`vim-mode:enable` / `vim-mode:disable`) via the standard
`buildAction()` event-dispatch path. There is no direct import between
the two extensions — keep it that way. If a richer toggle handshake is
needed, extend the event payload (it accepts `{}` today) rather than
introducing an import.

## Tests

This extension has no unit tests today. Sanity-check after edits by:

1. Running `pi` in a session with at least one consumer extension
   loaded (`tasks`, `term`, or `git-diff`).
2. Pressing `alt+space` and confirming the overlay shows both
   `defaults.json` entries and the consumer's contributed entries.
3. Running `/leader-menu bindings --export` and verifying the
   org-format output matches the loaded chord tree.
