# vim-mode

Vim-style modal editor for [pi](https://github.com/nichochar/pi-coding-agent).

Single-responsibility: when this extension is loaded, the modal editor
is installed unconditionally. There is no runtime toggle. To disable,
remove the extension directory (or in the dotfiles repo, comment out
/ Nix-toggle its inclusion).

The leader-menu side (Space and `,` chord discovery + dispatch) lives
in the sibling [`leader-menu`](../leader-menu/README.md) extension;
this extension delegates bare-leader keys in Normal mode to it via the
`leader-menu:open` event.

## Modes

| Mode        | Description                                   |
|-------------|-----------------------------------------------|
| Insert      | Text entry (standard pi editor behaviour)     |
| Normal      | Navigation and text manipulation              |
| Visual      | Character-wise selection for operator actions |
| Visual-Line | Line-wise selection for operator actions      |

The editor starts in Insert mode. Press `Esc` to enter Normal mode.
Press `alt+escape` (anywhere) to send an abort/interrupt to pi (replaces
plain `escape`, which is used to switch modes).

## Vim grammar (Normal / Visual)

Operators compose with motions and text objects:

- **Operators:** `d` (delete), `c` (change), `y` (yank), `>` / `<` (indent/dedent)
- **Motions:** `h/j/k/l`, `w/b/e/W/B/E`, `0/$`, `^`, `f/F/t/T{char}`, `;` (repeat last), `,` (repeat last reversed), `Ctrl-d/Ctrl-u`
- **Text objects:** `iw/aw`, `iW/aW`, `ip/ap`, `i"/a"`, `i'/a'`, `` i`/a` ``, `i(/a(`, `i[/a[`, `i{/a{`
- **Counts:** Numeric prefixes (e.g. `3dw`, `5x`, `2dd`)
- **Dot-repeat:** `.` replays the last change
- **Visual operators:** `d`, `c`, `y`, `>`, `<`, `~`, `u`, `U`

### Single-key commands (Normal mode)

| Key             | Action                            |
|-----------------+-----------------------------------|
| `x` / `X`       | Delete char at / before cursor    |
| `r{c}`          | Replace char with `{c}`           |
| `s` / `S`       | Substitute char / line            |
| `p` / `P`       | Paste after / before              |
| `u`             | Undo                              |
| `.`             | Repeat last change                |
| `J`             | Join lines                        |
| `~`             | Toggle case                       |
| `D` / `C` / `Y` | Delete/Change/Yank to end of line |
| `Enter`         | Submit message                    |
| `Esc`           | Clear pending op state            |
| `alt+Esc`       | Abort / interrupt                 |
| `<global>`      | Open global leader-menu overlay   |
| `<local>`       | Open local leader-menu overlay    |

`<global>` / `<local>` are the configured leader keys (defaults
`Space` and `,`; see `leader-menu` for reconfiguration).

In Insert mode, most keys pass through to the underlying pi editor
unchanged. `alt+space` and `alt+,` (or whatever the user's leaders
have been remapped to) are handled by `leader-menu`'s global
registerShortcut handlers.

## Settings

This extension has no settings file of its own. The only knob that
applies is the per-keypress `debug` logger, which lives in
`~/.pi/agent/leader-menu.json`:

```json
{ "debug": true }
```

The flag is co-owned with `leader-menu` and `tasks/overlay` because
all three extensions log keys through the same channel; centralising
it makes the toggle a single switch rather than three.

`leader-menu` migrates `debug` automatically from any pre-split
settings files (`vim-mode.json`, `keybindings-ext.json`) on first
session start.

## Cross-extension contract

| Direction | Event                       | Payload                                 | Source                                                 |
|-----------|-----------------------------|-----------------------------------------|--------------------------------------------------------|
| in        | `leader-menu:keys-resolved` | `{ globalLeader, localLeader }`         | leader-menu — used to update the bare-leader dispatcher |
| out       | `leader-menu:open`          | `{ rootKey: string }`                   | bare-leader keys in Normal mode                        |
| in        | `editor:width-constraint`   | `{ fraction, minCols }`                 | other extensions reserving width                       |

This extension never imports `leader-menu`; communication is purely
event-based. There are no `vim-mode:enable` / `vim-mode:disable`
events — the extension has no toggle to dispatch.

## Abort key caveat

`alt+escape` replaces bare `escape` as the abort key. Some terminals
(macOS Terminal.app, legacy xterm) do not send a distinct sequence for
`alt+escape` unless "Use Option as Meta" / a kitty or CSI-u-aware key
protocol is enabled. On such terminals you may need to press a
mode-neutral key (e.g. `Ctrl-c` to clear, or any leader action)
instead.

## Files

| File         | Purpose                                                    |
|--------------+------------------------------------------------------------|
| `index.ts`   | Extension entry point + `VimEditor` class                  |
| `README.md`  | This file                                                  |
| `AGENTS.md`  | Agent-side notes for modifying this extension              |

User state: none in this extension. See
`~/.pi/agent/leader-menu.json` for the shared `debug` flag.

## Migration history

| Was                                   | Now                                       |
|---------------------------------------+-------------------------------------------|
| `keybindings` extension (monolith)    | this extension + `leader-menu`            |
| `~/.pi/agent/keybindings-ext.json`    | merged into `leader-menu.json` (`debug`); `modal` dropped (always-on now) |
| `~/.pi/agent/vim-mode.json`           | merged into `leader-menu.json` (`debug`); deleted on first run |
| `/kb mode emacs|vim`                  | (removed; remove the extension to disable) |
| `/vim-mode on|off|toggle`             | (removed; same)                            |
| `vim-mode:enable` / `vim-mode:disable`| (removed; no toggle)                       |

`leader-menu` performs the settings file migrations on first run,
copying `debug` into `leader-menu.json` and deleting the legacy file.

## Comparison with `vim-motions-pi`

This extension was evaluated against the upstream package
[`kepatrick/vim-motions-pi`](https://github.com/kepatrick/vim-motions-pi)
and our existing `VimEditor` was kept (`KEEP_OWN`) on the basis that it
covers ~30% more of daily-use Vim grammar — notably dot-repeat,
indent/dedent operators, bracket/brace/quote text objects, BIG-WORD
variants, and the `alt+escape` abort key handling. We did adopt one
feature from upstream — repeat-find-backward (`,`) — and the upstream
package's decomposition shape is captured as a follow-up.

## Follow-up work

- Decompose `index.ts` (~2050 lines) into `index.ts` + `buffer.ts` +
  `core.ts` to mirror upstream's cleaner factoring. Improves
  maintainability without changing behaviour.
- Port `VIM_MOTION_PI_CLIPBOARD`-style clipboard sync (env-var driven,
  off/yank/all modes) from upstream.

## Dependencies

- `@mariozechner/pi-coding-agent` — `CustomEditor`, `ExtensionAPI`, `KeybindingsManager`
- `@mariozechner/pi-tui` — `matchesKey`, `truncateToWidth`, `visibleWidth`, `EditorTheme`, `TUI`
