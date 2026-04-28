# Tasks Extension

Displays project tasks from a `TASKS.org` file in the project root using org-mode TODO syntax.
The extension is a UI over the plain-org task-memory protocol documented in
`agents/skills/org-tasks/SKILL.md`; that skill defines the durable file-format
contract, while this extension owns commands, rendering, selection, status writes,
and archive mechanics.

## Usage

### Commands

- `/tasks` — Expand the tasks UI
- `/tasks new` — Create a new top-level task without opening the expanded UI

### Keybindings

- `<leader> t t` — Expand the tasks UI

### Compact selected-task widget

When a task UUID is recorded in `TASKS.local.org` (via `#+SELECTED: <UUID>`), a
compact widget is reserved above the editor. It shows the containing top-level
task tree, with the selected task highlighted inside it. The widget:

- Appears on startup if `TASKS.local.org` already contains a `#+SELECTED:` entry.
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
| `P` (shift-p)             | Publish local task → `TASKS.org` (local tasks only)        |
| `U` (shift-u)             | Unpublish task → `TASKS.local.org` (top-level shared tasks only) |
| `J` (shift-j)             | Open linked-issue URLs in the browser (see *Linked external issues* below) |
| `Esc` / `q`               | Close                              |

### Local tasks

Tasks stored in the gitignored `TASKS.local.org` file appear at the bottom of
the task tree, separated by a `⊠  Local drafts` divider. They are rendered
with a magenta `⊠` marker instead of the standard `•`/`▶`/`▼`, and their
summary text is magenta-tinted to distinguish them from shared tasks.

`TASKS.local.org` may contain any mix of `#+SELECTED:`, task headings, and
`#+IMPORT:` keywords alongside the selection keyword — all coexist in the
same file.

- **`P`** — publish the local task under the cursor to `TASKS.org` (makes it
  git-tracked and shared). Prompts for confirmation.
- **`U`** — unpublish the top-level shared task under the cursor to
  `TASKS.local.org` (removes it from git tracking). Top-level only.
- Local tasks cannot be archived — publish first.
- Creating a new task (`n`/`N`) while the cursor is on a local task writes
  the new task to `TASKS.local.org` rather than `TASKS.org`.

### Selection

Pressing `s` marks the task under the cursor as the *selected* task. This:

- Writes `#+SELECTED: <UUID>` to the gitignored `TASKS.local.org` (single-select — any prior selection is cleared).
- Lets the selected marker move down into subtasks while keeping the selected path visible.
- Auto-collapses sibling subtrees by default, so the view focuses on the current workstream rather than only the selected leaf.
- Highlights the selected task with a `★` marker and renders the selected top-level tree with a side bar.

Press `s` again on the selected task to clear the selection and return to the default top-level collapsed view.

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
- Transfers the task as-is into `TASKS.archive.org`, preserving its `#+IMPORT:` link. Plan file contents are not inlined.
- Re-sorts `TASKS.archive.org` by `CLOSED:` time on each archive operation, falling back to `:ARCHIVED:` time when a task has no `CLOSED:` stamp.
- Adds an `:ARCHIVED: [timestamp]` property to the archived heading. The timestamp uses the task's `CLOSED` value when present, otherwise the current time.
- Clears `TASKS.local.org` selection when the selected task is archived, so the compact widget doesn't point at a task that no longer exists.
- Preserves the `#+IMPORT:` link in the archived copy; plan file contents are **not** inlined. The archive entry is a faithful copy of the task as it stood in `TASKS.org`.

Task creation, plan path approval, and archive confirmation prompts temporarily close the expanded UI so input/confirmation dialogs remain visible. After create/archive flows complete or are cancelled, the expanded UI reopens with a refreshed task tree. When creating a new plan, the path prompt is prefilled with the suggested `#+DEFAULT_PLAN_DIR`-based path; accepting it scaffolds and links the file, then sends an agent prompt to develop the plan interactively.

### Change-records (proactive and retrospective)

The file linked from a task via `#+IMPORT:` is called a *change-record*. The file shape (sections `* Context`, `* Plan`, `* Implementation`) is owned by the `org-plan` skill; the same shape is produced by both flows below.

**Proactive flow** — press `p` on a task that has no `#+IMPORT:`, accept the path prompt, and the agent helps draft `* Context` and `* Plan` up front. As work proceeds, plan tasks transition `TODO -> STARTED -> DONE` and `* Implementation` is filled in.

**Retrospective flow** — cycle a task to `DONE` (via `→` / `l`) when it has no `#+IMPORT:` already attached. The extension prompts for a path, scaffolds the change-record file, attaches `#+IMPORT:` to the parent task, and sends the agent a prompt to draft `* Context` and `* Implementation` from `git log` scoped to the task's `:STARTED:` and `CLOSED:` timestamps. The user-facing behaviour:

- Triggers only on `TODO -> DONE` and `STARTED -> DONE`. `CANCELLED` does not trigger; cycling away from `DONE` does not trigger.
- Triggers only when the parent task has no `#+IMPORT:` yet. Tasks with an existing change-record (planned or retrospective) skip the prompt.
- If the resolved path already points to an existing file, content is appended (never overwritten).
- Cancelling the path prompt leaves the task `DONE` with no record attached. The user can attach one later via the `p` keybinding.

**Setting:** `~/.pi/agent/tasks-ext.json`

```json
{
  "changeRecordOnDone": true
}
```

Default is `true`. When `false`, the retrospective flow is suppressed and `TODO/STARTED -> DONE` behaves as it did before the feature.

### Timestamps

- **`:CREATED:`** — written on every new task created via `/tasks new`,
  `n`, or `N`, in `[YYYY-MM-DD Day HH:MM]` format. Existing tasks are
  not backfilled.
- **`:STARTED:`** — written the first time a task moves `TODO -> STARTED`.
  Subsequent `DONE -> STARTED` re-opens preserve the original value.
  Used by the retrospective change-record flow to scope `git log`.
- **`CLOSED:`** — written on transition to `DONE` or `CANCELLED`.
  Emitted on its own line above the `:PROPERTIES:` drawer (matches
  `org-todo`'s native behaviour). The parser accepts `CLOSED:` in
  either position and serializes back above the drawer.

### Linked external issues

Tasks may reference issues in external trackers (Jira, GitHub, Linear,
etc.) via a generic, tracker-agnostic mechanism owned by this extension.

**Drawer property `:LINKED_ISSUES:`** — multi-valued, whitespace-separated
list of tokens. Each token is either:

1. **Bare key** (e.g. `MBFW-123`) — resolved against `#+ISSUE_URL_BASE`
   (see below) to produce a clickable URL. Rendered as the key itself.
2. **Org link** `[[url][label]]` — resolved directly, no template needed.
   Rendered as `label`.

The two forms can mix freely on a single line:

```org
:PROPERTIES:
:ID: 01234567-…
:LINKED_ISSUES: MBFW-123 MBE-45 [[https://github.com/foo/bar/issues/42][gh#42]]
:END:
```

The property is created on first link only — never auto-backfilled on
existing tasks or pre-created on new tasks (mirroring `:STARTED:`).

**File keyword `#+ISSUE_URL_BASE:`** — URL template used to resolve bare
keys. Two forms accepted:

```org
#+ISSUE_URL_BASE: https://your-org.atlassian.net/browse/{ID}
#+ISSUE_URL_BASE: https://your-org.atlassian.net/browse/
```

Resolution rule for bare keys:

1. URL-encode the key.
2. If the template contains `{ID}`, substitute the encoded key for every
   occurrence.
3. Otherwise treat the template as a prefix and append the encoded key.

Unusual URL shapes (`https://issues.example.com/?id={ID}&v=full`) are
also expressible. `TASKS.local.org` may override the keyword
(last-write-wins, mirroring `#+SELECTED:`).

**Rendering** — each linked issue appears as a cyan badge prefixed with
`⤴`, immediately before the tags suffix on the task row. Badges show
in both the expanded UI and the compact selected-task widget. Tasks
with no `:LINKED_ISSUES:` are rendered unchanged.

**`J` keybinding (expanded UI)** — opens every resolvable URL on the
cursor task in the user's browser, capped at 5 with a notification when
exceeded. Empty/absent property is a silent no-op. Bare tokens with no
resolvable URL (no `#+ISSUE_URL_BASE` and not an org link) trigger a
notification pointing at the missing keyword. Browser is invoked via
`open` (macOS) or `xdg-open` (Linux/other).

**Tracker-specific workflows** (claim, transition, comment, create) are
intentionally *not* part of this extension. They live in companion
extensions like `jira` that contribute slash commands and use
`getDrawerProperty` / `setDrawerProperty` / `getLinkedIssues` from this
extension's parser to read and write the property.

## File format

File-format details (heading syntax, properties, `#+IMPORT:`,
`#+DEFAULT_PLAN_DIR:`, `#+SELECTED:`, change-record sections) live
in the `org-tasks` skill: `agents/skills/org-tasks/SKILL.md`. The
extension implements that protocol; this README only covers the UI
and extension-specific behaviour.

Extension-specific notes:

- **Round-trip preservation**: in `TASKS.org`, file-level metadata,
  preamble, and non-task category headings stay in place; only
  parsed task subtrees are rewritten. In linked change-records,
  sections like `#+TITLE`, `#+TODO`, `* Context`,
  `** Design decisions`, `* Plan`, `* Implementation`, and
  `* Open questions` are preserved; only parsed task subtrees are
  rewritten.
- **Permissive parsing**: actionable task headings may appear
  anywhere in a linked change-record. Using `* Plan` is the
  recommended convention but not required.
- **`#+IMPORT:` link form**: the value can be a bare path,
  `[[file:...]]`, or `[[file:...][label]]`. Whichever form is on
  disk is preserved exactly. New change-records scaffolded by `p`
  are written in `[[file:...]]` form so they're clickable in Emacs.
- **Subtask absorption**: if `p` is pressed on a task that already
  has local subtasks, those subtask trees are moved into the new
  change-record under `* Plan`; the parent retains a plain-text
  bullet summary of the extracted subtasks.

## Tests

```sh
./test.sh
```

Runs structural sanity checks against `index.ts` and the
`parser.test.ts` unit suite (parser round-trip invariants and the
`scaffoldPlan()` literal-snapshot test). The snapshot is paired with
an equivalent `ert` test in the spacemacs `tasks-org` layer
(`editors/emacs/spacemacs/layers/org-user/local/tasks-org/tasks-org-tests.el`)
so drift between the TS scaffolder and the elisp helpers is caught
on both sides.

Requires `tsx` on `$PATH` (e.g. via `npx tsx` or a global install).

## Dependencies

- `lib/pi-utils.ts` — `getExtensionName`, `suggestKeybindings`
