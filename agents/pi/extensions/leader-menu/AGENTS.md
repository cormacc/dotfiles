# leader-menu — agent notes

## Scope

This extension owns *only* leader-menu discovery and dispatch. Modal
editing lives in the sibling `vim-mode` extension. Do not add
modal-editor code, mode toggling, or settings persistence here — those
all belong in `vim-mode`.

## Editing rules

- `defaults.json` is git-tracked and represents the project-level
  default *menu structure* (no trigger keys). Do not write user state
  to it.
- The two-slot model (`globalMenu` / `localMenu`) is intentional. Do
  not add a third top-level slot or accept raw trigger keys from
  contributors; that would defeat the configurable-leader design and
  re-introduce the surface area the leader-menu / vim-mode split was
  meant to clean up.
- User-side trigger keys are resolved at `session_start` from
  `~/.pi/agent/leader-menu.json`. The resolved keys are emitted via
  `leader-menu:keys-resolved` for sibling extensions (today: just
  `vim-mode`) to consume. Treat this event as part of the public
  cross-extension contract.
- `VIM_NORMAL_RESERVED_KEYS` (in `index.ts`) is duplicated from
  `vim-mode/` by design rather than imported. Its purpose is purely to
  emit a soft warning at registration time when a configured leader
  key would clash with the modal grammar; cross-extension imports
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
