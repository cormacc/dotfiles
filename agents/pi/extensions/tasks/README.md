# Tasks Extension

Displays project tasks from a `TASKS.org` file in the project root using org-mode TODO syntax.

## Usage

### Commands

- `/tasks` — Open the tasks overlay

### Keybindings

- `<leader> t t` — Open the tasks overlay

### Persistent selection overlay

When a task is marked `:selected:` in `TASKS.org`, a non-capturing overlay
is pinned to the top of the visible terminal viewport and shows the containing
top-level task tree, with the selected task highlighted inside it. The overlay:

- Appears on startup if the file already contains a `:selected:` tag.
- Updates immediately while the `/tasks` overlay is open when status or selection changes.
- Refreshes automatically when `TASKS.org` or any linked plan file is modified on disk (for example after saving from Emacs via the `e` keybinding). No need to reopen `/tasks`.
- Does not take keyboard focus, so normal input keeps working.
- Shows at most 12 lines. When truncating, completed subtasks are elided first as `… N completed subtasks`, so the selected task and next pending subtasks stay visible.

### Status colors

Status and metadata tokens use a fixed palette across the main tasks overlay and the pinned selection overlay.
Tags are styled separately from task titles.

| Status    | Color  |
| --------- | ------ |
| `TODO`      | yellow |
| `WAITING`   | orange |
| `STARTED`   | blue   |
| `DONE`      | green  |
| `CANCELLED` | red    |

| Priority | Meaning  | Color  |
| -------- | -------- | ------ |
| `[#A]`   | Critical | orange |
| `[#B]`   | High     | yellow |
| `[#C]`   | Medium   | green  |
| `[#D]`   | Low      | blue   |

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
| `p`                       | Edit the task's linked plan in Emacs (or create one) |
| `A` (shift-a)             | Archive the top-level task (must be `DONE` or `CANCELLED`) |
| `Esc` / `q`               | Close                              |

### Selection

Pressing `s` marks the task under the cursor as the *selected* task. This:

- Writes a `:selected:` tag on that heading in `TASKS.org` (single-select — any prior selection is cleared).
- Lets the selected marker move down into subtasks while keeping the *top-level parent task* as the visible selected tree root.
- Auto-collapses every task outside that top-level root, so the view focuses on the current workstream rather than only the selected leaf.
- Highlights the selected task with a `★` marker and renders the selected top-level tree with a side bar.

Press `s` again on the selected task to clear the selection and drop the auto-collapse. The `:selected:` tag is hidden from the tag list in the overlay — it's conveyed by the marker and highlight instead.

### Archiving

Pressing `A` (shift-a) archives the top-level task containing the cursor's task. Archiving:

- Requires the top-level task's status to be `DONE` or `CANCELLED` — other statuses are refused with a notification, to avoid archiving active work by accident.
- Prompts for confirmation before writing anything.
- Removes the task (and all its subtasks and content) from `TASKS.org`.
- Inlines any linked plan children into the archived copy so the archive file is self-contained.
- Appends the archived task to `TASKS.ARCHIVE.org` in archive-date order (which matches CLOSED order in normal use).
- Adds an `:ARCHIVED: [timestamp]` property to the archived heading. The timestamp uses the task's `CLOSED` value when present, otherwise the current time.
- Strips `:selected:` from the archived copy so reloading `TASKS.org` doesn't flip the pinned overlay onto a no-longer-present task.

## TASKS.org Format

The file uses org-mode heading syntax:

```org
* TODO [#A] Implement authentication :backend:security:
:PROPERTIES:
:PLAN: plans/auth.org
:END:
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
- **Status** — one of `TODO`, `STARTED`, `WAITING`, `DONE`, `CANCELLED`
- **Priority** — optional, e.g. `[#A]`, `[#B]`, `[#C]`
- **Summary** — the task title
- **Tags** — optional, colon-delimited at end of line
- **PLAN property** — optional org properties drawer value pointing to a relative org file with a detailed task plan
- **Description** — any non-heading text below a heading, excluding the properties drawer

Subtasks nest arbitrarily deep — any TODO heading under another becomes its child.

### Linked plans

A task can link to a detailed plan using an org properties drawer immediately below the heading:

```org
* TODO [#A] Implement authentication :backend:security:
:PROPERTIES:
:PLAN: plans/auth.org
:END:
  Parent task description.
```

The `PLAN` path is resolved relative to the org file that contains the property. The linked file is parsed with the same TODO heading syntax as `TASKS.org`; its tasks are injected into the overlay as children of the parent task. Status changes made to injected plan tasks are saved back to the linked plan file, not copied into `TASKS.org`.

#### Org-link syntax

The `:PLAN:` value can also be written as an org link so it's clickable in Emacs (`C-c C-o` on the property value):

```org
:PLAN: [[file:plans/auth.org]]
:PLAN: [[file:plans/auth.org][Auth plan]]
```

Both the link form and the plain-path form are parsed identically by the extension. Whichever form the file uses is preserved exactly on round-trip save. New plans created via the `p` keybinding are written in the `[[file:...]]` form so they're clickable in Emacs by default.

## Dependencies

- `lib/pi-utils.ts` — `getExtensionName`, `suggestKeybindings`
