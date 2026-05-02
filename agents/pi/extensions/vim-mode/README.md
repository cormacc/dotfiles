# vim-mode

Optional Vim-style modal editor for [pi](https://github.com/nichochar/pi-coding-agent).

This extension installs a `VimEditor` `CustomEditor` when modal editing is
enabled. Default-off — a fresh checkout has standard insert-only behaviour
until the user opts in. The leader-menu side (Space and `,` chords) lives
in the sibling [`leader-menu`](../leader-menu/README.md) extension; this
extension delegates bare-Space/`,` chords in Normal mode to it via the
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

## Toggling modal editing

Persistent user setting at `~/.pi/agent/vim-mode.json`:

```json
{ "modal": true }
```

Toggle at runtime via either:

- **Slash command:** `/vim-mode on | off | toggle`.
- **Leader chord:** `Space t E v` (vim) / `Space t E e` (emacs / insert-only).
  In Vim Normal mode the leader is `Space` bare; in insert-only mode use
  the direct Space-leader shortcut — so `alt+space t E v`.

Both paths write to the user settings file and apply immediately.

### Settings migration

On first session start after install, vim-mode looks for the legacy
`~/.pi/agent/keybindings-ext.json` (from the old `keybindings`
extension). If present and `vim-mode.json` does not exist, the
`modal` and `debug` keys are copied across, the old file is deleted,
and a one-shot notification is shown. After migration, only
`vim-mode.json` is consulted.

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
| `Space`         | Open `leader-menu` Space overlay  |
| `,`             | Open `leader-menu` `,` overlay    |

In Insert mode, most keys pass through to the underlying pi editor
unchanged. `alt+space` and `alt+,` are handled by `leader-menu`'s
global registerShortcut handlers.

## Cross-extension contract

Modal toggle is event-driven; this extension never imports `leader-menu`.

| Direction | Event                       | Payload                                 | Source                                                 |
|-----------|-----------------------------|-----------------------------------------|--------------------------------------------------------|
| in        | `vim-mode:enable`           | `{ source?: string }`                   | leader-menu (`<global> t E v`), or any other contributor |
| in        | `vim-mode:disable`          | `{ source?: string }`                   | leader-menu (`<global> t E e`), or any other contributor |
| in        | `leader-menu:keys-resolved` | `{ globalLeader, localLeader }`         | leader-menu — used to update the bare-leader dispatcher |
| out       | `leader-menu:open`          | `{ rootKey: string }`                   | bare-leader keys in Normal mode                        |
| in        | `editor:width-constraint`   | `{ fraction, minCols }`                 | other extensions reserving width                       |

The `source` field on enable/disable is advisory only; vim-mode uses it
to make the resulting notification more informative
(e.g. `vim-mode: on (slash-command)`). Empty/absent payload is fine.

## Abort key caveat

`alt+escape` replaces bare `escape` as the abort key when modal is on.
Some terminals (macOS Terminal.app, legacy xterm) do not send a distinct
sequence for `alt+escape` unless "Use Option as Meta" / a kitty or
CSI-u-aware key protocol is enabled. On such terminals modal users may
need to press a mode-neutral key (e.g. `Ctrl-c` to clear, or any leader
action) instead.

## Files

| File         | Purpose                                                    |
|--------------+------------------------------------------------------------|
| `index.ts`   | Extension entry point, `VimEditor` class, settings, migrator |
| `README.md`  | This file                                                  |
| `AGENTS.md`  | Agent-side notes for modifying this extension              |

User state: `~/.pi/agent/vim-mode.json` (not tracked in this repo).

## Migration from the old `keybindings` extension

This extension replaces the modal-editor half of the legacy
`keybindings/` extension (which also included leader menus). One-step
breaking changes:

| Old                                   | New                              |
|---------------------------------------+----------------------------------|
| `/kb mode emacs|vim`                  | `/vim-mode on|off|toggle`        |
| `keybindings:set-mode-vim` event      | `vim-mode:enable` event          |
| `keybindings:set-mode-emacs` event    | `vim-mode:disable` event         |
| `~/.pi/agent/keybindings-ext.json`    | `~/.pi/agent/vim-mode.json`      |

Settings are migrated automatically on first run.

## Comparison with `vim-motions-pi`

This extension was evaluated against the upstream package
[`kepatrick/vim-motions-pi`](https://github.com/kepatrick/vim-motions-pi)
and our existing `VimEditor` was kept (`KEEP_OWN`) on the basis that it
covers ~30% more of daily-use Vim grammar — notably dot-repeat,
indent/dedent operators, bracket/brace/quote text objects,
BIG-WORD variants, and the `alt+escape` abort key handling. We did
adopt one feature from upstream — repeat-find-backward (`,`) — and
the upstream package's decomposition shape is captured as a follow-up.

## Follow-up work

- Decompose `index.ts` (~2200 lines) into `index.ts` + `buffer.ts` +
  `core.ts` to mirror upstream's cleaner factoring. Improves
  maintainability without changing behaviour.
- Port `VIM_MOTION_PI_CLIPBOARD`-style clipboard sync (env-var driven,
  off/yank/all modes) — a useful upstream feature missing from the
  current implementation.

## Dependencies

- `@mariozechner/pi-coding-agent` — `CustomEditor`, `ExtensionAPI`, `KeybindingsManager`
- `@mariozechner/pi-tui` — `matchesKey`, `truncateToWidth`, `visibleWidth`, `EditorTheme`, `TUI`
