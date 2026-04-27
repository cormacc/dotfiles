---
name: org-memory
description: "Use when maintaining or resuming project work stored in TASKS.org and included org task files. Covers the org task-memory protocol: TODO states, IDs, IMPORT links, status discipline, archiving, and resume workflows."
---

# Org Memory
Use this skill when the user asks to work from, update, resume, review, tasks.
The canonical project memory index is `TASKS.org` in the project root.
A task may include additional tasks from another org file using a `#+IMPORT:` keyword.

## Responsibility boundary
This skill owns the durable file protocol:
- `TASKS.org` and included org task files,
- supported TODO states and priorities,
- `:ID:`, `#+IMPORT:`, `:BLOCKED-BY:` conventions,
- per-contributor selection state in `TASKS.local.org`,
- task notes, status discipline, archiving, bootstrap, and resume workflows.


## Core file protocol
`TASKS.org` and included task files should declare the shared TODO cycle:
```org
#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)
```

`TASKS.org` may also declare the default include/plan directory:
```org
#+DEFAULT-PLAN-DIR: [[file:./design/log]]
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
#+DEFAULT-PLAN-DIR: [[file:./design/log]]

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

Keep `TASKS.org` high-level. Put detailed checklists/history in included files.
If an included file is a plan, follow the `plan` skill for its section layout.

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

## Creating/updating tasks and included files

- Use the smallest useful task granularity: each task should describe a concrete
  outcome that can become `DONE`.
- Prefer adding detail to included files rather than bloating `TASKS.org`.
- Do not remove completed historical tasks unless the user asks.
- Add discovered work as new TODO tasks, not hidden prose.

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
2. Add `#+TITLE:`, the shared `#+TODO:`, and `#+DEFAULT-PLAN-DIR: [[file:./design/log]]`.
3. Add a semantic section such as `* Improvements` or `* Tasks`.
4. Add the first actionable TODO task with an `:ID:` property.
5. If the task needs detailed work items, create an included org file under the
   `#+DEFAULT-PLAN-DIR` directory.

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

### Creating included task files

- Suggest a path before creating a new included file unless the user already gave
  one. Prefer `#+DEFAULT-PLAN-DIR: [[file:...]]` from `TASKS.org`, falling back
  to `[[file:./design/log]]`.
- Use `YYYY-MM-DD-short-task-name.org` for new included task files unless the
  project specifies another naming convention.
- New included files should declare `#+TITLE:`, `#+DATE:`, `#+PARENT_ID:` (the
  including task's `:ID:`), and the shared `#+TODO:` cycle.

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
