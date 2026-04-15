# Tasks Extension

Displays project tasks from a `TASKS.org` file in the project root using org-mode TODO syntax.

## Usage

### Commands

- `/tasks` — Open the tasks overlay

### Keybindings (modal-editor)

- `<leader> t t` — Open the tasks overlay

### Overlay Controls

The overlay is a split pane — task tree on the left, description of the selected task on the right.

| Key                       | Action                  |
| ------------------------- | ----------------------- |
| `↑` / `k`                 | Move up                 |
| `↓` / `j`                 | Move down               |
| `→` / `l`                 | Cycle status forward    |
| `←` / `h`                 | Cycle status back       |
| `Ctrl-d` / `Ctrl-u`       | Scroll description pane |
| `Enter` / `Space` / `Tab` | Toggle collapse         |
| `Esc` / `q`               | Close                   |

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
