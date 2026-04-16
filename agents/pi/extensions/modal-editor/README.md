# modal-editor

A [pi](https://github.com/nichochar/pi-coding-agent) extension that replaces
the default input editor with a Vim-style modal editor. Provides Normal,
Insert, Visual, and Visual-Line modes with the full Vim grammar for composing
prompts to the AI agent.

## Modes

| Mode        | Description                                   | Default |
| ----------- | --------------------------------------------- | ------- |
| Insert      | Text entry (standard editor behaviour)        | ✓       |
| Normal      | Navigation and text manipulation              |         |
| Visual      | Character-wise selection for operator actions |         |
| Visual-Line | Line-wise selection for operator actions      |         |

The editor starts in **Insert** mode — since most interactions are typing a
prompt and pressing Enter. Press `Esc` to enter Normal mode for editing.

## Vim Grammar

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

## Leader Keys

Leader menus provide quick access to pi commands from Normal mode. Pressing a
leader key (e.g. `Space` or `,`) opens a menu — an overlay appears after
500ms showing available bindings.

Leader menus are defined in `keybindings.json` and support:

- Multiple leader keys (each with its own menu tree)
- Nested sub-menus (e.g. `Space g d` for git diff)
- Three action types: events (default), `command:` slash commands, and `passthrough:` key forwarding

### Default Leader Bindings

#### Comma Leader (`,`)

| Key   | Action             | Equivalent  |
| ----- | ------------------ | ----------- |
| `, m` | Switch model       | `Ctrl-l`    |
| `, t` | Cycle thinking     | `Shift-Tab` |
| `, o` | Toggle tool output | `Ctrl-o`    |
| `, k` | Toggle thinking    | `Ctrl-t`    |
| `, e` | External editor    | `Ctrl-g`    |
| `, n` | New session        | `/new`      |
| `, r` | Resume session     | `/resume`   |
| `, b` | Session tree       | `/tree`     |
| `, c` | Compact            | `/compact`  |
| `, y` | Copy last response | `/copy`     |

#### Space Leader (`Space`)

| Key       | Action            | Equivalent  |
| --------- | ----------------- | ----------- |
| `Space s` | Settings          | `/settings` |
| `Space r` | Reload extensions | `/reload`   |

Additional Space sub-menus are registered dynamically by other extensions via
the `modal-editor:suggest-keybindings` event (see below).

## Commands

| Command            | Description                                             |
| ------------------ | ------------------------------------------------------- |
| `/editor bindings` | Show all registered keybindings in a scrollable overlay |

Note: `editor` is the command name, `bindings` is passed as an argument.

## Extension Integration

Other extensions can register leader key bindings without modifying
`keybindings.json` by using the shared utility `suggestKeybindings()` from
`lib/pi-utils.ts`, or by directly emitting the
`modal-editor:suggest-keybindings` event.

Bindings are merged additively — key clashes with existing bindings are
ignored with a warning. Two sub-menus on the same key are merged recursively.

The `modal-editor:ready` event is emitted when the editor initialises,
allowing extensions to re-send suggestions after reloads.

### Width Constraint

Extensions can reserve screen space (e.g. for a side panel) by emitting
`editor:width-constraint` with `{ fraction, minCols }`. The editor shrinks
its render width accordingly. Emit `{ fraction: 0 }` to release the space.

## Passthrough Keys

These pi shortcuts work in **all modes** and are passed through unchanged:

| Key         | Pi Action                        |
| ----------- | -------------------------------- |
| `Ctrl-c`    | Clear editor / abort agent       |
| `Ctrl-d`    | Exit (when editor empty)         |
| `Ctrl-z`    | Suspend to background            |
| `Ctrl-l`    | Open model selector              |
| `Ctrl-p`    | Cycle scoped models              |
| `Shift-Tab` | Cycle thinking level             |
| `Ctrl-o`    | Toggle tool output               |
| `Ctrl-t`    | Toggle thinking blocks           |
| `Ctrl-g`    | Open external editor             |
| `Ctrl-v`    | Paste image from clipboard       |
| `Alt-Enter` | Queue follow-up message          |
| `Enter`     | Submit message (Normal & Insert) |

## Configuration

Edit `keybindings.json` in this directory to customise leader menus.

```json
{
  "menus": {
    "space": {
      "label": "Leader (Space)",
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

## Files

| File               | Purpose                                         |
| ------------------ | ----------------------------------------------- |
| `index.ts`         | Extension entry point and VimEditor class       |
| `keybindings.json` | Leader menu configuration                       |
| `keybindings.html` | Visual keybinding reference (keep in sync)      |
| `AGENTS.md`        | Agent instructions for modifying this extension |

## Dependencies

- `@mariozechner/pi-coding-agent` — `CustomEditor`, `ExtensionAPI`, `KeybindingsManager`
- `@mariozechner/pi-tui` — `matchesKey`, `truncateToWidth`, `visibleWidth`, `EditorTheme`, `TUI`
