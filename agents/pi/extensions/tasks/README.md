# Tasks Extension

Displays project tasks from a `TASKS.org` file in the project root using org-mode TODO syntax.
The extension is a UI over the plain-org task-memory protocol documented in
`agents/skills/org-memory/SKILL.md`; that skill defines the durable file-format
contract, while this extension owns commands, rendering, selection, status writes,
and archive mechanics.

## Usage

### Commands

- `/tasks` — Expand the tasks UI
- `/tasks new` — Create a new top-level task without opening the expanded UI

### Keybindings

- `<leader> t t` — Expand the tasks UI

### Compact selected-task widget

When a task is marked `:selected:` in `TASKS.org`, a compact widget is reserved
above the editor. It shows the containing top-level task tree, with the selected
task highlighted inside it. The widget:

- Appears on startup if the file already contains a `:selected:` tag.
- Hides while the tasks UI is expanded, then returns after the expanded UI closes.
- Refreshes automatically when `TASKS.org` or any linked plan file is modified on disk (for example after saving from Emacs via the `e` keybinding). No need to reopen `/tasks`.
- Does not take keyboard focus, so normal input keeps working.
- Reserves layout space instead of covering conversation scrollback.
- Shows at most 6 lines, with a single full-width divider at the top and no bottom divider.
- When truncating, completed subtasks are elided first as `… N completed subtasks`, so the selected task and next pending subtasks stay visible.
- Shows the selected top-level task's linked plan path, for example `./relative/path/to/plan.org`, when loaded plan children are present.

### Status colors

Status and metadata tokens use a fixed palette across the expanded tasks UI and the compact selected-task widget.
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

### Expanded UI controls

The expanded UI is a centered split pane — task tree on the left, details for the selected task on the right. The details pane starts with the cursor task's status and title, followed by plan metadata and the task description.

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
| `p`                       | Edit the task's linked plan in Emacs, or start agent-assisted plan creation |
| `n`                       | Create a new sibling task          |
| `N`                       | Create a new child task            |
| `A` (shift-a)             | Archive the top-level task (must be `DONE` or `CANCELLED`) |
| `Esc` / `q`               | Close                              |

### Selection

Pressing `s` marks the task under the cursor as the *selected* task. This:

- Writes a `:selected:` tag on that heading in `TASKS.org` (single-select — any prior selection is cleared).
- Lets the selected marker move down into subtasks while keeping the selected path visible.
- Auto-collapses sibling subtrees by default, so the view focuses on the current workstream rather than only the selected leaf.
- Highlights the selected task with a `★` marker and renders the selected top-level tree with a side bar.

Press `s` again on the selected task to clear the selection and return to the default top-level collapsed view. The `:selected:` tag is hidden from the tag list in the UI — it's conveyed by the marker and highlight instead.

### Default collapse behaviour

On open, the expanded UI starts compact:

- With no selected task, top-level tasks are shown and task subtrees are collapsed.
- With a selected task, the path to the selected task is expanded so the selected row is visible.
- Sibling subtrees are collapsed by default.
- Completed (`DONE`/`CANCELLED`) subtrees are collapsed unless they must be expanded to reveal the selected task.

Manual expand/collapse using Enter, Space, or Tab applies for the lifetime of the expanded UI session.

### Archiving

Pressing `A` (shift-a) archives the top-level task containing the cursor's task. Archiving:

- Requires the top-level task's status to be `DONE` or `CANCELLED` — other statuses are refused with a notification, to avoid archiving active work by accident.
- Prompts for confirmation before writing anything.
- Removes the task (and all its subtasks and content) from `TASKS.org`.
- Inlines any linked plan children into the archived copy so the archive file is self-contained.
- Re-sorts `TASKS.ARCHIVE.org` by `CLOSED:` time on each archive operation, falling back to `:ARCHIVED:` time when a task has no `CLOSED:` stamp.
- Adds an `:ARCHIVED: [timestamp]` property to the archived heading. The timestamp uses the task's `CLOSED` value when present, otherwise the current time.
- Strips `:selected:` from the archived copy so reloading `TASKS.org` doesn't flip the compact widget onto a no-longer-present task.

Task creation, plan path approval, and archive confirmation prompts temporarily close the expanded UI so input/confirmation dialogs remain visible. After create/archive flows complete or are cancelled, the expanded UI reopens with a refreshed task tree. When creating a new plan, the path prompt is prefilled with the suggested `#+DEFAULT-PLAN-DIR`-based path; accepting it scaffolds and links the file, then sends an agent prompt to develop the plan interactively.

## TASKS.org Format

The file uses org-mode heading syntax. A `#+TODO:` declaration is recommended so Emacs users get the same state cycle as the extension. `#+DEFAULT-PLAN-DIR:` optionally sets the default directory for newly created plan files and must use org-link syntax; when omitted, the default is `[[file:./design/log]]`.

```org
#+TITLE: Project Tasks
#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)
#+DEFAULT-PLAN-DIR: [[file:./design/log]]

* TODO [#A] Implement authentication :backend:security:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:INCLUDE: [[file:design/log/auth.org]]
:END:
  Design and implement user auth.
** TODO Create user model
:PROPERTIES:
:ID: 89abcdef-0123-4567-89ab-cdef01234567
:END:
** STARTED Implement login endpoint
:PROPERTIES:
:ID: fedcba98-7654-4321-8fed-cba987654321
:END:
   Working on JWT token generation.
** WAITING Add OAuth support :oauth:
:PROPERTIES:
:ID: 11111111-2222-4333-8444-555555555555
:BLOCKED-BY: human: provider credentials
:END:
   Waiting on provider credentials.
* DONE [#B] Set up CI pipeline :devops:
:PROPERTIES:
:ID: 22222222-3333-4444-8555-666666666666
:END:
```

### Heading syntax

```
* STATUS [#PRIORITY] Summary text :tag1:tag2:
```

- **Stars** (`*`) — heading level; nested headings become subtasks
- **Status** — one of `TODO`, `STARTED`, `WAITING`, `DONE`, `CANCELLED`
- **Priority** — optional, e.g. `[#A]`, `[#B]`, `[#C]`, `[#D]`
- **Summary** — the task title
- **Tags** — optional, colon-delimited at end of line
- **ID property** — UUID in the properties drawer, compatible with org-id.el and the org-memory skill protocol. Missing IDs in `TASKS.org` and loaded linked plans are inserted automatically on load.
- **INCLUDE property** — optional org properties drawer value pointing to a relative org file with a detailed task plan
- **BLOCKED-BY property** — optional property recording why a `WAITING` task is blocked
- **Description** — any non-heading text below a heading, excluding the properties drawer
- **DEFAULT-PLAN-DIR keyword** — optional top-level `#+DEFAULT-PLAN-DIR: [[file:./path/to/dir]]` setting used as the default directory for new plan files; defaults to `[[file:./design/log]]` when absent or malformed

Subtasks nest arbitrarily deep — any TODO heading under another becomes its child. Parent statuses are not automatically inferred from child statuses.

### Linked plans

A task can link to a detailed plan using an org properties drawer immediately below the heading:

```org
* TODO [#A] Implement authentication :backend:security:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:INCLUDE: [[file:design/log/auth.org]]
:END:
  Parent task description.
```

The `INCLUDE` path is resolved relative to the org file that contains the property. New plan path suggestions use the top-level `#+DEFAULT-PLAN-DIR: [[file:...]]` directory from `TASKS.org`, defaulting to `[[file:./design/log]]` when the keyword is absent or malformed. The linked file is parsed with the same TODO heading syntax as `TASKS.org`; its tasks are injected into the expanded UI as children of the parent task. The details pane shows the plan target, loaded plan-task count, or a missing/unreadable-plan warning. New plan files scaffolded by the extension include `#+TITLE`, `#+DATE`, `#+PARENT_ID` with the parent task's UUID `:ID:`, `#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)`, `* Context`, and `* Plan` sections. If a new plan is created from a task that already has local subtasks, those subtask trees are moved into the linked plan under `* Plan`; the parent task keeps a plain-text bullet summary of the extracted subtasks instead of retaining them as actionable child headings in `TASKS.org`. After scaffolding and linking the file, the extension sends an agent prompt to develop the plan with the user, write the final plan to disk, and offer to open it in Emacs. Status changes made to injected plan tasks are saved back to the linked plan file, not copied into `TASKS.org`. Saves preserve non-task org content such as file metadata, category headings, `* Context`, optional `** Design decisions`, `* Plan`, `* Implementation`, and `* Open questions` sections.

The parser is intentionally permissive: actionable task headings may appear anywhere in the linked file. Using a dedicated `* Plan` section is recommended as a convention for readability, but it is not required by the extension.

### Round-trip preservation

The extension preserves non-task org content when saving status or selection changes. In `TASKS.org`, metadata/preamble text and non-task category headings remain in place. In linked plan files, sections such as `#+TITLE`, `#+TODO`, `* Context`, optional `** Design decisions`, `* Plan`, `* Implementation`, and `* Open questions` remain in place; only parsed task subtrees are rewritten.

#### Org-link syntax

The `:INCLUDE:` value can be written as an org link so it's clickable in Emacs (`C-c C-o` on the property value):

```org
:INCLUDE: [[file:design/log/auth.org]]
:INCLUDE: [[file:design/log/auth.org][Auth plan]]
```

Both the link form and the plain-path form are parsed identically by the extension. Whichever form the file uses is preserved exactly on round-trip save. New plans created via the `p` keybinding are written in the `[[file:...]]` form so they're clickable in Emacs by default.


## Dependencies

- `lib/pi-utils.ts` — `getExtensionName`, `suggestKeybindings`
