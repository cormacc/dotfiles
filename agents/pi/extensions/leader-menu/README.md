# leader-menu

Which-key-style leader chord discovery and dispatch for [pi](https://github.com/nichochar/pi-coding-agent).

This extension owns two abstract leader slots, the `alt+<leader>`
global shortcuts that open them, and the cross-extension *contribution*
API that every other extension uses to register its own sub-menus.
It has no opinion on modal editing — the optional vim layer lives in
the sibling [`vim-mode`](../vim-mode/README.md) extension. If that
extension is loaded it is always on; there is no leader-menu toggle for
it.

## Leaders

Two abstract slots, each with a configurable trigger key:

| Slot     | Default key | Purpose                                       |
|----------+-------------+-----------------------------------------------|
| Global   | `Space`     | Primary leader; extensions contribute here.   |
| Local    | `,`         | pi-agent quick actions (model, thinking, …). |

User overrides live in `~/.pi/agent/leader-menu.json`:

```json
{
  "globalLeader": "/",
  "localLeader": ";",
  "debug": true
}
```

All keys optional:

- `globalLeader` / `localLeader` — default `" "` and `","`.
- `debug` — when true, every key press is reported via
  `ctx.ui.notify`. Read by both this extension and sibling
  input-handling extensions (`vim-mode`, `tasks`); the loggers are
  intentionally co-located here because the flag is about *key
  dispatch*, not modal editing.

Trigger key resolution happens once at session_start; runtime
reconfiguration requires a `/reload` (because the underlying
`alt+<leader>` shortcuts are registered with pi at startup and have
no unregister hook).

Extensions never name trigger keys directly — they contribute via
`registerLeaderMenu()` with `globalMenu` / `localMenu` slots. The
final trigger key is whatever the user has configured.

### Settings migration

On first session_start, leader-menu copies the `debug` flag (and only
`debug`) from any pre-split settings file it finds and then deletes
the source:

- `~/.pi/agent/vim-mode.json` (post-keybindings-split, pre-toggle-removal)
- `~/.pi/agent/keybindings-ext.json` (pre-keybindings-split)

The legacy `modal` flag is intentionally not migrated — `vim-mode` is
now always-on whenever the extension is loaded; to disable, remove
the extension itself.

## Slash commands

| Command                            | Description                                                |
|------------------------------------+------------------------------------------------------------|
| `/leader-menu bindings`            | Interactive overlay listing every registered chord         |
| `/leader-menu bindings --export`   | Print every chord as an org-mode table (replaces hand-maintained `keybindings.org`) |

## Global shortcuts

| Shortcut             | Action                  |
|----------------------+-------------------------|
| `alt+<globalLeader>` | Open the global menu    |
| `alt+<localLeader>`  | Open the local menu     |

With default leaders these are `alt+space` and `alt+,`.

In modal `vim-mode`, configured leader keys may be pressed bare from
Normal mode — the `vim-mode` extension forwards into this overlay via
the `leader-menu:open` event. Note that a leader key that also has Vim
meaning (notably the default local leader `,`, used for repeat-find)
will be handled by Vim grammar first; use `alt+<localLeader>` or
choose a non-conflicting local leader such as `;` if you want a bare
Normal-mode local leader.

## Default leader bindings (`defaults.json`)

### `,` — pi agent

| Chord | Label              |
|-------+--------------------|
| `, m` | Switch model       |
| `, t` | Cycle thinking     |
| `, o` | Toggle tool output |
| `, k` | Toggle thinking    |
| `, e` | External editor    |
| `, n` | New session        |
| `, r` | Resume session     |
| `, b` | Session tree       |
| `, c` | Compact            |
| `, y` | Copy last response |
| `, s` | Settings           |
| `, R` | Reload extensions  |

### `Space` — leader

`defaults.json` ships no global bindings of its own. Global menus are
registered dynamically by other extensions (for example `tasks`,
`term`, and `git-diff`) via the contribution API below.

Additional local-menu entries may also be registered dynamically by
other extensions.

## Contribution API

Other extensions contribute leader entries via the
`registerLeaderMenu()` helper in `lib/pi-utils.ts`:

```typescript
import { getExtensionName, registerLeaderMenu } from "../lib/pi-utils.js";

const EXT_NAME = getExtensionName(import.meta.url);
let cleanupKb: (() => void) | null = null;

export default function (pi: ExtensionAPI) {
  pi.on("session_start", () => {
    cleanupKb = registerLeaderMenu(pi, EXT_NAME, {
      globalMenu: {
        items: {
          m: {
            label: "+my-ext",
            items: {
              x: { label: "Do thing", action: "myext:do-thing" },
            },
          },
        },
      },
    });
  });
  pi.on("session_shutdown", () => { cleanupKb?.(); });
}
```

The registration has two slots, both optional:

- `globalMenu` — contributions appear under the configured global
  leader (default `Space`). Most extensions use this slot.
- `localMenu` — contributions appear under the configured local
  leader (default `,`). Reserved for pi-agent quick-action style
  bindings; most extensions don't need it.

Note: extensions never specify trigger keys directly. The final
trigger key is whatever the user has configured (or the default).
This means the same registration JSON works regardless of how the
user has rebound their leaders.

The helper:

- Sends a `leader-menu:register` event when leader-menu is loaded;
- Subscribes to `leader-menu:ready` so contributions are re-sent after
  pi reloads and after leader-menu re-initialises;
- Returns a `cleanup: () => void` for `session_shutdown`.

Contributions are merged additively. Same-key sub-menus merge
recursively. A clash with an existing leaf binding is logged as a
warning and the existing entry wins. Two contributions of the same
key+label are deduped silently (idempotent re-registration).

### Action types

Any action string without a recognised prefix is emitted as an event on
`pi.events`. This is the primary mechanism for cross-extension
keybindings — the contributing extension subscribes to the event itself.

| Prefix         | Description              | Example                     |
|----------------+--------------------------+-----------------------------|
| *(none)*       | Emit as event (default)  | `myext:do-thing`            |
| `command:`     | Insert a slash command   | `command:/diff`             |
| `passthrough:` | Forward a key combo      | `passthrough:ctrl+l`        |
| `event:`       | Emit as event (legacy)   | `event:term:toggle`         |

## Cross-extension contracts

### Publish resolved leader keys

After resolving leader keys (defaults + user overrides) at
`session_start`, leader-menu emits:

```
  leader-menu:keys-resolved   { globalLeader: string, localLeader: string }
```

`vim-mode` subscribes so its Normal-mode dispatcher picks up
user-reconfigured leader keys without needing a parallel settings
read of its own.

## Files

| File             | Purpose                                                |
|------------------+--------------------------------------------------------|
| `index.ts`       | Extension entry point, overlays, contribution merger   |
| `defaults.json`  | Immutable default leader-menu definitions              |
| `README.md`      | This file                                              |
| `AGENTS.md`      | Agent-side notes for modifying this extension          |

User settings live in `~/.pi/agent/leader-menu.json` (leader trigger
keys plus the shared `debug` flag).

## Migration from the old `keybindings` extension

This extension replaces the leader-menu half of the legacy
`keybindings/` extension (which also included a modal editor). One-step
breaking changes:

| Old                                    | New                              |
|----------------------------------------+----------------------------------|
| `/kb bindings`                         | `/leader-menu bindings`          |
| `/kb mode emacs|vim`                   | removed; unload `vim-mode` to disable |
| `keybindings:suggest` event            | `leader-menu:register` event     |
| `keybindings:ready` event              | `leader-menu:ready` event        |
| `keybindings:set-mode-vim` event       | removed                          |
| `keybindings:set-mode-emacs` event     | removed                          |
| `suggestKeybindings()` helper          | `registerLeaderMenu()` helper    |
| `KeybindingSuggestion` type            | `LeaderMenuRegistration` type    |
| `~/.pi/agent/keybindings-ext.json`     | `~/.pi/agent/leader-menu.json` (`debug` only; `modal` dropped) |
| `extensions/keybindings.org` (manual)  | `/leader-menu bindings --export` |

`registerLeaderMenu` is the replacement helper, but its payload is
intentionally slot-based (`globalMenu` / `localMenu`) rather than the
legacy raw-trigger-key `menus` map. In-tree consumers were migrated
atomically with the split.

## Dependencies

- `@mariozechner/pi-coding-agent` — `ExtensionAPI`, `KeybindingsManager`
- `@mariozechner/pi-tui` — `matchesKey`, `truncateToWidth`, `Component`, `TUI`
- `lib/pi-utils.ts` — `ansiPad`
