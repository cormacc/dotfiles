# keybindings

A [pi](https://github.com/nichochar/pi-coding-agent) extension providing
which-key-style leader menus and (optional) vim-style modal editing.

Primary role is the leader menu: other extensions register their commands
under a leader key (Space, `,`, etc.) and the extension renders a
discoverable overlay listing them. Modal (Normal / Visual / Visual-Line)
editing is opt-in — disabled by default.

## Modes

| Mode        | Description                                   | Default |
| ----------- | --------------------------------------------- | ------- |
| Insert      | Text entry (standard pi editor behaviour)     | ✓       |
| Normal      | Navigation and text manipulation              |         |
| Visual      | Character-wise selection for operator actions |         |
| Visual-Line | Line-wise selection for operator actions      |         |

With modal editing **disabled** (the default) the editor is always in Insert
mode and all of pi's default editor keybindings apply unchanged. The leader
menu is still available, reached via the `alt+m` prefix (see below).

With modal editing **enabled**, the editor starts in Insert mode. Press
`Esc` to enter Normal mode. Press `alt+escape` (anywhere) to send an
abort/interrupt to pi (replaces plain `escape`, which is used to switch
modes).

## Toggling modal editing

Persistent user setting stored in `~/.pi/agent/keybindings-ext.json`:

```json
{ "modal": true }
```

Toggle at runtime via either:

- Leader: `Space t E e` (emacs / insert-only) / `Space t E v` (vim / modal).
  In modal mode the leader is `Space` bare; in insert mode the leader is
  reached with `alt+m` first — so `alt+m Space t E v`.
- Slash command: `/kb mode emacs` or `/kb mode vim`.

Both write to the user settings file and apply immediately.

## Insert-mode leader prefix

In Insert mode (both emacs and vim modes), the leader menus are reached via
the `alt+m` prefix:

- `alt+m Space …` — Space leader menu (e.g. `alt+m Space t E v` to enable vim mode).
- `alt+m ,`       — `,` leader (pi-agent quick actions).

After `alt+m`, press the leader root key you want. The usual which-key
overlay appears after 500ms.

In Normal mode (vim / modal on), the leader keys are pressed bare: `Space`,
`,`, etc. — no prefix.

## Vim Grammar (Normal / Visual, modal mode only)

Operators compose with motions and text objects:

- **Operators:** `d` (delete), `c` (change), `y` (yank), `>` / `<` (indent/dedent)
- **Motions:** `h/j/k/l`, `w/b/e/W/B/E`, `0/$`, `^`, `f/F/t/T{char}`, `;`, `Ctrl-d/Ctrl-u`
- **Text objects:** `iw/aw`, `iW/aW`, `ip/ap`, `i"/a"`, `i'/a'`, `` i`/a` ``, `i(/a(`, `i[/a[`, `i{/a{`
- **Counts:** Numeric prefixes (e.g. `3dw`, `5x`, `2dd`)
- **Dot-repeat:** `.` replays the last change
- **Visual operators:** `d`, `c`, `y`, `>`, `<`, `~`, `u`, `U`

### Single-key Commands (Normal mode)

| Key             | Action                            |
| --------------- | --------------------------------- |
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
| `Esc`           | Clear pending op / leader state   |
| `alt+Esc`       | Abort / interrupt                 |

## Default Leader Bindings (from `defaults.json`)

### `,` leader (pi-agent)

| Key   | Action             | Equivalent  |
| ----- | ------------------ | ----------- |
| `, m` | Switch model       | `Ctrl-l`    |
| `, t` | Cycle thinking     | `Shift-Tab` |
| `, o` | Toggle tool output | `Ctrl-o`    |
| `, k` | Toggle thinking    | `Ctrl-t`    |
| `, e` | External editor    | `Ctrl-g`    |
| `, n` | New session        | `/new`      |
| `, r` | Resume session     | `/resume`   |
| `, R` | Reload extensions  | `/reload`   |
| `, b` | Session tree       | `/tree`     |
| `, c` | Compact            | `/compact`  |
| `, y` | Copy last response | `/copy`     |
| `, s` | Settings           | `/settings` |

In insert mode prefix with `alt+m` (e.g. `alt+m , m` to switch model).

### Space leader

| Key               | Action        |
| ----------------- | ------------- |
| `Space t E e`     | Emacs mode    |
| `Space t E v`     | Vim mode      |

Additional Space sub-menus are registered dynamically by other extensions
via the `keybindings:suggest` event (see below).

## Commands

| Command            | Description                                             |
| ------------------ | ------------------------------------------------------- |
| `/kb bindings`     | Show all registered keybindings in a scrollable overlay |
| `/kb mode emacs`   | Switch to emacs (insert-only) mode                      |
| `/kb mode vim`     | Switch to vim (modal) mode                              |

## Extension Integration

Other extensions register leader key bindings via the shared utility
`suggestKeybindings()` from `lib/pi-utils.ts`, or by directly emitting the
`keybindings:suggest` event.

Bindings are merged additively — key clashes with existing bindings are
ignored with a warning. Two sub-menus on the same key are merged
recursively.

The `keybindings:ready` event is emitted when the editor initialises,
allowing extensions to re-send suggestions after reloads.

### Width Constraint

Extensions can reserve screen space (e.g. for a side panel) by emitting
`editor:width-constraint` with `{ fraction, minCols }`. The editor shrinks
its render width accordingly. Emit `{ fraction: 0 }` to release the space.

## Configuration

`defaults.json` in this directory holds the immutable default menu
configuration and is git-tracked — do not write user state to it. User
state (currently only the modal-editing preference) lives in
`~/.pi/agent/keybindings-ext.json`.

```json
{
  "menus": {
    "space": {
      "label": "Leader",
      "key": " ",
      "items": {
        "n": { "label": "New session", "action": "command:/new" },
        "m": { "label": "Switch model", "action": "passthrough:ctrl+l" },
        "g": {
          "label": "+git",
          "items": {
            "d": { "label": "Diff", "action": "command:/diff" }
          }
        },
        "t": { "label": "Toggle mirror", "action": "term:toggle" }
      }
    }
  }
}
```

### Action Types

Any action string without a recognized prefix is emitted as an event on
`pi.events`. This is the primary mechanism for cross-extension keybindings.

| Prefix         | Description                  | Example              |
| -------------- | ---------------------------- | -------------------- |
| *(none)*       | Emit as event (default)      | `term:toggle`        |
| `command:`     | Submit a slash command       | `command:/new`       |
| `passthrough:` | Forward a key combo to pi    | `passthrough:ctrl+l` |
| `event:`       | Emit as event (legacy alias) | `event:term:toggle`  |

## Abort key caveat (modal mode)

`alt+escape` replaces bare `escape` as the abort key when modal editing is
on. Some terminals (macOS Terminal.app, legacy xterm) do not send a
distinct sequence for `alt+escape` unless "Use Option as Meta" / a kitty or
CSI-u-aware key protocol is enabled. On such terminals modal users may
need to press a mode-neutral key (e.g. `Ctrl-c` to clear, or any leader
action) instead.

## Files

| File               | Purpose                                         |
| ------------------ | ----------------------------------------------- |
| `index.ts`         | Extension entry point and VimEditor class       |
| `defaults.json`    | Immutable default menu configuration            |
| `README.md`        | This file                                       |
| `AGENTS.md`        | Agent instructions for modifying this extension |

User state: `~/.pi/agent/keybindings-ext.json` (not tracked in this repo).

## Dependencies

- `@mariozechner/pi-coding-agent` — `CustomEditor`, `ExtensionAPI`, `KeybindingsManager`
- `@mariozechner/pi-tui` — `matchesKey`, `truncateToWidth`, `visibleWidth`, `EditorTheme`, `TUI`
