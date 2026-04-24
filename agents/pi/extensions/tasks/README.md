# Tasks Extension

Displays project tasks from a `TASKS.org` file in the project root using org-mode TODO syntax.

## Usage

### Commands

- `/tasks` — Open the tasks overlay

### Keybindings

- `<leader> t t` — Open the tasks overlay

### Persistent selection overlay

When a task is marked `:selected:` in `TASKS.org`, a non-capturing overlay
is pinned to the top of the visible terminal viewport and shows that task and
its subtasks. The overlay:

- Appears on startup if the file already contains a `:selected:` tag.
- Updates immediately while the `/tasks` overlay is open when status or selection changes.
- Does not take keyboard focus, so normal input keeps working.
- Shows at most 12 lines; deeper subtrees collapse into a `… N more` line.

### Status colors

Status tokens use a fixed palette across the main tasks overlay and the pinned selection overlay:

| Status    | Color  |
| --------- | ------ |
| `TODO`    | yellow |
| `WAITING` | orange |
| `STARTED` | blue   |
| `DONE`    | green  |

### Overlay Controls

The overlay is a split pane — task tree on the left, description of the selected task on the right.

| Key                       | Action                             |
| ------------------------- | ---------------------------------- |
| `↑` / `k`                 | Move cursor up                     |
| `↓` / `j`                 | Move cursor down                   |
| `→` / `l`                 | Cycle status forward               |
| `←` / `h`                 | Cycle status back                  |
| `Ctrl-d` / `Ctrl-u`       | Scroll description pane            |
| `Enter` / `Space` / `Tab` | Toggle collapse                    |
| `s`                       | Toggle selection on current task   |
| `e`                       | Edit in Emacs at task              |
| `Esc` / `q`               | Close                              |

### Selection

Pressing `s` marks the task under the cursor as the *selected* task. This:

- Writes a `:selected:` tag on that heading in `TASKS.org` (single-select — any prior selection is cleared).
- Auto-collapses every task that isn't the selected task, one of its ancestors, or one of its descendants, so the view focuses on the selected subtree.
- Highlights the selected task with a `★` marker and renders the selected subtree in bold with a side bar.

Press `s` again on the selected task to clear the selection and drop the auto-collapse. The `:selected:` tag is hidden from the tag list in the overlay — it's conveyed by the marker and highlight instead.

## TASKS.org Format

The file uses org-mode heading syntax:

```org
* TODO [#A] Implement authentication :backend:security:
  Design and implement user auth.
** TODO Create user model
** STARTED Implement login endpoint
   Working on JWT token generation.
** WAITING Add OAuth support :oauth:
   Waiting on provider credentials.
* DONE [#B] Set up CI pipeline :devops:
```

### Heading syntax

```
* STATUS [#PRIORITY] Summary text :tag1:tag2:
```

- **Stars** (`*`) — heading level; nested headings become subtasks
- **Status** — one of `TODO`, `STARTED`, `WAITING`, `DONE`
- **Priority** — optional, e.g. `[#A]`, `[#B]`, `[#C]`
- **Summary** — the task title
- **Tags** — optional, colon-delimited at end of line
- **Description** — any non-heading text below a heading

Subtasks nest arbitrarily deep — any TODO heading under another becomes its child.

## Dependencies

- `lib/pi-utils.ts` — `getExtensionName`, `suggestKeybindings`
