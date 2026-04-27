---
name: org-memory
description: "Use when maintaining or resuming project work stored in TASKS.org and linked change-record files. Covers the org task-memory protocol: TODO states, IDs, IMPORT links, change-records (proactive and retrospective), status discipline, archiving, and resume workflows."
---

# Org Memory
Use this skill when the user asks to work from, update, resume, review, tasks.
The canonical project memory index is `TASKS.org` in the project root.
A task may link to a *change-record* (a separate org file capturing the
task's context, plan, and implementation notes) via a `#+IMPORT:` keyword.

## Responsibility boundary
This skill owns the durable file protocol:
- `TASKS.org` and linked change-record files,
- supported TODO states and priorities,
- `:ID:`, `:STARTED:`, `#+IMPORT:`, `:BLOCKED-BY:` conventions,
- per-contributor selection state in `TASKS.local.org`,
- task notes, status discipline, archiving, bootstrap, and resume workflows.

The section structure of change-record files (`* Context`, `* Plan`,
`* Implementation`, `* Open questions`) is owned by the plan skill
(`../plan/SKILL.md`); this skill defers there for layout details.


## Core file protocol
`TASKS.org` and included task files should declare the shared TODO cycle:
```org
#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)
```

`TASKS.org` may also declare the default include/plan directory:
```org
#+DEFAULT_PLAN_DIR: [[file:./design/log]]
```

Actionable tasks are org headings:
```org
** TODO [#A] Implement feature :area:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:END:
#+IMPORT: [[file:design/log/2026-04-25-feature.org]]
```

Rules:
- TODO states: `TODO`, `STARTED`, `WAITING`, `DONE`, `CANCELLED`.
- Priorities: `[#A]` critical, `[#B]` high, `[#C]` medium, `[#D]` low.
- Tags are semantic categories. There are no reserved operational tags.
- Every task/subtask in `TASKS.org` and loaded included files must have a UUID v4
  `:ID:` property.
- `#+IMPORT:` points to another org file in the same task-memory format.
  Place the keyword on its own line in the task body (after the `:END:` of
  the properties drawer, before any description text), or at file root level
  (before any heading) to inject tasks from another file at the root.
  Use clickable `[[file:...]]` links for new values; preserve existing bare or
  labelled links when already present. Resolve relative paths against the file
  that contains the keyword.
- Included tasks may be displayed as children of the including task by tooling,
  but they remain ordinary org files without tooling.

## Example TASKS.org
```org
#+TITLE: Project Tasks
#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)
#+DEFAULT_PLAN_DIR: [[file:./design/log]]

* Improvements

** TODO [#A] Implement authentication :backend:security:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:END:
#+IMPORT: [[file:design/log/2026-04-25-authentication.org]]
[2026-04-25 Sat] Initial scope captured from user request.

*** TODO [#B] Define password reset acceptance criteria :backend:
:PROPERTIES:
:ID: 89abcdef-0123-4567-89ab-cdef01234567
:END:
Acceptance criteria: documented flows and edge cases.

* Housekeeping

** WAITING [#C] Update upstream dependency :nix:
:PROPERTIES:
:ID: fedcba98-7654-4321-8fed-cba987654321
:BLOCKED-BY: url:https://github.com/example/project/pull/123
:END:
Waiting on upstream merge.
```

Keep `TASKS.org` high-level. Put detailed checklists/history in change-record
files. The plan skill defines the section layout (`* Context`, `* Plan`,
`* Implementation`, optional `* Open questions`).

## Selection state

The currently-active task for a contributor is stored in a **gitignored**
`TASKS.local.org` file at the project root, expressed as a single top-level
keyword:

```org
#+SELECTED: 01234567-89ab-4def-8123-456789abcdef
```

The value is a UUID v4 `:ID:` that is resolved by looking up the matching
task in `TASKS.org` and any linked plan files. The file holds no task
structure — selection is a pointer, not a mutation of the shared graph.

Protocol rules:
- Absent file or missing `#+SELECTED:` keyword means "no selection".
- Writers create or overwrite `TASKS.local.org` atomically (write-then-rename)
  so the pi file watcher never sees a transient empty state.
- Deselecting writes `#+SELECTED:` with no value (file is retained).
- Selection is per-checkout. A repo with multiple local clones has independent
  `TASKS.local.org` files — this is intentional.
- Every repo using this protocol must add `TASKS.local.org` to `.gitignore`.

## Starting or resuming work

1. Read `TASKS.org`.
2. Locate the active task: read `TASKS.local.org` for a `#+SELECTED: <UUID>` pointer
   and resolve it by `:ID:` match against the task graph; fall back to a user-named
   task, the first `STARTED` task, or context.
3. Follow its `#+IMPORT:` link if present.
4. If the included file is a plan, resume the first `STARTED` task in it, or the
   first actionable `TODO` task.
5. Read nearby task notes plus relevant included-file context/implementation
   sections before editing code.
6. Keep statuses and durable notes synchronized as work proceeds.

## Creating/updating tasks and change-records

- Use the smallest useful task granularity: each task should describe a concrete
  outcome that can become `DONE`.
- Prefer adding detail to change-records rather than bloating `TASKS.org`.
- Do not remove completed historical tasks unless the user asks.
- Add discovered work as new TODO tasks, not hidden prose.

## Change-records

A *change-record* is a separate org file linked from a task via `#+IMPORT:`,
with the section layout owned by the plan skill (`* Context`, `* Plan`,
`* Implementation`, optional `* Open questions`).  The file shape is the
same regardless of when it is authored.

There are two authoring flows:

1. **Proactive** — the change-record is created before work begins.  The
   agent helps the user draft `* Context` and `* Plan` up front, then the
   user (or agent) executes the plan, marking each `* Plan` task `DONE` and
   filling in `* Implementation` as work lands.  This is the flow the pi
   tasks extension's `p` keybinding produces, and the flow the plan skill
   primarily describes.
2. **Retrospective** — the change-record is created after the parent task
   has already closed.  The agent uses the parent task's `:STARTED:` and
   `CLOSED:` timestamps to scope `git log`, then drafts `* Context` and
   `* Implementation` from the commit history.  `* Plan` may be left empty
   or filled with a brief retrospective list of steps actually taken
   (including any failed attempts that were rolled back).  This flow is
   triggered by the pi tasks extension when the user cycles a task to
   `DONE` without an existing `#+IMPORT:` link.

Whichever flow produced the file, the result is referred to as a
*change-record* and linked the same way.  A change-record begun as a
proactive plan becomes a record of what shipped as work proceeds; a
retrospective change-record captures the same information after the fact.

## Task notes

Use plain text under the task heading for durable human/agent context. Prefer a
short paragraph note, optionally with an inactive timestamp:

```org
** DONE [#B] Add parser regression coverage :agents:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:END:
CLOSED: [2026-04-25 Sat 12:00]
[2026-04-25 Sat] Verified the serializer preserves the org preamble.
```

Do not require `:LOGBOOK:` drawers for agent notes. Preserve existing logbooks
and timestamps when present.

## Blocking and WAITING tasks

When blocked:

1. Change status to `WAITING`.
2. Add/update `:BLOCKED-BY:`.
3. Add a short note if useful.

Examples:

```org
:BLOCKED-BY: human: confirm desired archive behavior
:BLOCKED-BY: task:57f300c5-bdb1-4494-9837-9474722c3182
:BLOCKED-BY: url:https://github.com/example/project/pull/123
:BLOCKED-BY: jira:ABC-123
```

When unblocked, move the task back to `TODO` or `STARTED` and either remove
`:BLOCKED-BY:` or move the old blocker into a note.

## Bootstrap protocol

If `TASKS.org` does not exist and the user wants persistent task memory:

1. Create `TASKS.org` in the project root.
2. Add `#+TITLE:`, the shared `#+TODO:`, and `#+DEFAULT_PLAN_DIR: [[file:./design/log]]`.
3. Add a semantic section such as `* Improvements` or `* Tasks`.
4. Add the first actionable TODO task with an `:ID:` property.
5. If the task needs detailed work items, create an included org file under the
   `#+DEFAULT_PLAN_DIR` directory.

## Status discipline

- Mark a task `STARTED` when beginning substantial work.
- Mark it `DONE` only when implemented and verified.
- Use `WAITING` with `:BLOCKED-BY:` for blocked work.
- Use `CANCELLED` for intentionally abandoned work.
- `DONE` and `CANCELLED` are closed states. When changing a task to either
  state, **insert** a `CLOSED:` timestamp immediately after the `:END:` of the
  properties drawer (or directly after the heading if there is no drawer).
  Use the format `CLOSED: [YYYY-MM-DD DayAbbrev HH:MM]` — always obtain the
  current date/time and correct day-of-week abbreviation by running
  `date +"%Y-%m-%d %a %H:%M"` via bash rather than computing it manually.
  Preserve existing `CLOSED:` timestamps; do not replace them.
  Ensure any note text that follows starts on its own line.
- Update parent statuses when child states change.

## Housekeeping automated by the pi tasks extension

If the pi tasks extension is active, skip this section — it handles the following
automatically. Use these procedures only when editing task files without pi.

### ID discipline

- Generate a UUID v4 for every new task/subtask and store it as `:ID:`.
- When loading project memory, add missing IDs to all tasks and subtasks in
  `TASKS.org` and any included files loaded for the current workstream, before
  making other edits.
- Preserve existing IDs, properties, heading text, and surrounding formatting.
- Do not scan or mutate arbitrary org files outside the loaded task-memory graph.

### Creating change-record files

- Suggest a path before creating a new change-record unless the user already
  gave one. Prefer `#+DEFAULT_PLAN_DIR: [[file:...]]` from `TASKS.org`,
  falling back to `[[file:./design/log]]`.
- Use `YYYY-MM-DD-short-task-name.org` for new change-records unless the
  project specifies another naming convention.
- New change-records should declare `#+TITLE:`, `#+DATE:`, `#+PARENT_ID:` (the
  parent task's `:ID:`), and the shared `#+TODO:` cycle.

### `:STARTED:` first-transition timestamp

When a task moves `TODO -> STARTED` for the first time, record a
`:STARTED: [YYYY-MM-DD Day HH:MM]` property on the task heading.  Subsequent
`DONE -> STARTED` re-opens preserve the original value.  This timestamp
lets the retrospective change-record flow scope `git log` precisely.  The
pi tasks extension writes this property automatically; manual editors
should do the same.

### Parent status propagation

When a child plan task moves to `STARTED` through direct file editing, advance
any `TODO` ancestors in `TASKS.org` to `STARTED` manually.

### Archiving

1. Only archive top-level tasks whose status is `DONE` or `CANCELLED`.
2. Move the complete task subtree to `TASKS.ARCHIVE.org` in the project root.
3. Preserve `:ID:` and content.
4. Add `:ARCHIVED: [timestamp]`.
5. Preserve or inline included task context so history remains understandable.

## Interop

For planning methodology and canonical plan file sections, see the plan skill:
`../plan/SKILL.md`.
