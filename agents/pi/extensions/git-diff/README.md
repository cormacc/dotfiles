# git-diff

A [pi](https://github.com/nichochar/pi-coding-agent) extension that displays a
live git diff panel as a side overlay, showing uncommitted changes (staged,
unstaged, and untracked files) or committed-but-unpushed diffs when the
worktree is clean.

## Features

- **Live diff panel** — anchored to the top-right of the terminal, showing a
  unified diff with line numbers, add/remove highlighting, and per-file stats.
- **Auto-refresh** — updates after every `edit`, `write`, or `bash` tool
  invocation.
- **Foldable files** — three fold states cycled with `a`: names-only →
  collapsed (preview, 5 lines) → fully expanded.
- **Focus mode** — captures keyboard input for scrolling and navigation
  without leaving the diff panel.
- **Smart diff source** — shows working tree changes when dirty; falls back to
  unpushed commits (vs upstream or main/master) when clean.
- **Editor width constraint** — automatically narrows the input editor to make
  room for the panel (40% of terminal width, minimum 45 columns).

## Slash Command

### `/diff [subcommand]`

| Subcommand    | Description                     |
| ------------- | ------------------------------- |
| _(none)_      | Toggle the diff panel           |
| `toggle`      | Toggle the diff panel           |
| `focus`       | Show panel and enter focus mode |
| `scroll-up`   | Scroll the panel up (3 lines)   |
| `scroll-down` | Scroll the panel down (3 lines) |
| `fold`        | Toggle fold on the current file |

## Suggested Keybindings

Registered with the `keybindings` extension under `Space g` (git sub-menu):

| Key         | Action              | Command             |
| ----------- | ------------------- | ------------------- |
| `Space g d` | Toggle diff panel   | `/diff toggle`      |
| `Space g f` | Focus diff panel    | `/diff focus`       |
| `Space g j` | Scroll diff down    | `/diff scroll-down` |
| `Space g k` | Scroll diff up      | `/diff scroll-up`   |
| `Space g e` | Toggle fold on file | `/diff fold`        |

## Focus Mode Keybindings

When the diff panel is focused (via `/diff focus` or `Space g f`):

| Key                     | Action                                       |
| ----------------------- | -------------------------------------------- |
| `j` / `↓`               | Scroll down                                  |
| `k` / `↑`               | Scroll up                                    |
| `Ctrl-d` / `PgDn`       | Page down                                    |
| `Ctrl-u` / `PgUp`       | Page up                                      |
| `Home`                  | Scroll to top                                |
| `End`                   | Scroll to bottom                             |
| `n` / `Tab`             | Jump to next file                            |
| `m` / `Shift-Tab`       | Jump to previous file                        |
| `Enter` / `e` / `Space` | Toggle fold on current file                  |
| `a`                     | Cycle all folds: names-only → preview → full |
| `Esc` / `q`             | Exit focus mode                              |

## Diff Source Logic

1. **Uncommitted changes** — `git diff --cached` + `git diff` + untracked files
   (via `git diff --no-index -- /dev/null <file>`).
2. If worktree is clean, falls back to **commit diffs**:
   - Commits ahead of `@{upstream}` (tracking branch)
   - Commits diverging from `main` or `master` via merge-base
   - Last 10 commits as final fallback

## Files

| File        | Purpose                             |
| ----------- | ----------------------------------- |
| `index.ts`  | Extension entry point, panel UI     |
| `parser.ts` | Unified diff parser (`parseDiff()`) |

## Dependencies

- `@mariozechner/pi-coding-agent` — `ExtensionAPI`, `Theme`
- `@mariozechner/pi-tui` — `OverlayHandle`, `TUI`, `matchesKey`, `truncateToWidth`, `visibleWidth`
- `keybindings` — for `editor:width-constraint` event and `suggestKeybindings` integration
