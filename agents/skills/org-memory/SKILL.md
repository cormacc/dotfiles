---
name: org-memory
description: Use when maintaining or resuming project work stored in TASKS.org and included org task files. Covers the org task-memory protocol, INCLUDE properties, IDs, status updates, and compatibility with or without the pi tasks extension.
---

# Org Memory

Use this skill when the user asks to work from, update, resume, review, or create
project task memory in org files. The canonical project memory index is
`TASKS.org` in the project root. A task may include additional tasks from another
org file using its `:INCLUDE:` property.

This skill is harness-agnostic. The pi tasks extension is an optional UI over the
same plain org files; always keep the files useful without pi.

## Responsibility boundary

This skill owns the durable file protocol:

- `TASKS.org` and included org task files,
- supported TODO states and priorities,
- `:ID:`, `:INCLUDE:`, `:BLOCKED_BY:`, and reserved `:selected:` conventions,
- task notes, status discipline, archiving, bootstrap, and resume workflows.

The tasks extension owns UI concerns: commands, keybindings, overlays, rendering,
selection mechanics, safe round-tripping, and archive implementation. If docs and
implementation differ, verify the extension source before relying on UI details.

## Core file protocol

`TASKS.org` and included task files should declare the shared TODO cycle:

```org
#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)
```

`TASKS.org` may also declare the default include/plan directory:

```org
#+INCLUDES: [[file:./design/log]]
```

Actionable tasks are org headings:

```org
** TODO [#A] Implement feature :area:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:INCLUDE: [[file:design/log/2026-04-25-feature.org]]
:END:
```

Rules:

- TODO states: `TODO`, `STARTED`, `WAITING`, `DONE`, `CANCELLED`.
- Priorities: `[#A]` critical, `[#B]` high, `[#C]` medium, `[#D]` low.
- Tags are semantic categories. The only reserved operational tag is
  `:selected:`, marking the active task for task-selection tooling. Preserve and
  respect it; do not move or clear it unless explicitly asked or acting through a
  selection tool.
- Every task/subtask in `TASKS.org` and loaded included files must have a UUID v4
  `:ID:` property.
- `:INCLUDE:` points to another org file in the same task-memory format. Use
  clickable `[[file:...]]` links for new values; preserve existing bare or
  labelled links when already present. Resolve relative paths against the file
  that declares the property.
- Included tasks may be displayed as children of the including task by tooling,
  but they remain ordinary org files without tooling.

## Example TASKS.org

```org
#+TITLE: Project Tasks
#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)
#+INCLUDES: [[file:./design/log]]

* Improvements

** TODO [#A] Implement authentication :backend:security:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:INCLUDE: [[file:design/log/2026-04-25-authentication.org]]
:END:
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
:BLOCKED_BY: url:https://github.com/example/project/pull/123
:END:
Waiting on upstream merge.
```

Keep `TASKS.org` high-level. Put detailed checklists/history in included files.
If an included file is a plan, follow the `plan` skill for its section layout.

## ID discipline

- Generate a UUID v4 for every new task/subtask and store it as `:ID:`.
- When loading project memory, add missing IDs to `TASKS.org` and included files
  actually loaded for the current workstream before making other edits.
- Preserve existing IDs, properties, heading text, and surrounding formatting.
- Do not scan or mutate arbitrary org files outside the loaded task-memory graph.

## Starting or resuming work

1. Read `TASKS.org`.
2. Add missing `:ID:` properties to loaded tasks/subtasks.
3. Locate the active task: prefer `:selected:`, otherwise use a user-named task,
   the first `STARTED` task, or context.
4. Follow its `:INCLUDE:` link if present.
5. If the included file is a plan, resume the first `STARTED` task in it, or the
   first actionable `TODO` task.
6. Read nearby task notes plus relevant included-file context/implementation
   sections before editing code.
7. Keep statuses and durable notes synchronized as work proceeds.

## Creating/updating tasks and included files

- Use the smallest useful task granularity: each task should describe a concrete
  outcome that can become `DONE`.
- Prefer adding detail to included files rather than bloating `TASKS.org`.
- Do not remove completed historical tasks unless the user asks.
- Add discovered work as new TODO tasks, not hidden prose.
- For new included files, suggest a path before creating it unless the user
  already gave one. Prefer `#+INCLUDES: [[file:...]]` from `TASKS.org`, falling
  back to `[[file:./design/log]]`.
- Use `YYYY-MM-DD-short-task-name.org` for new included task files unless the
  project specifies another naming convention.
- New included files should declare `#+TITLE:`, `#+DATE:`, `#+PARENT_ID:` (the
  including task's `:ID:`), and the shared `#+TODO:` cycle.

## Task notes

Use plain text under the task heading for durable human/agent context. Prefer a
short paragraph note, optionally with an inactive timestamp:

```org
** DONE [#B] Add parser regression coverage :agents:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:END:
[2026-04-25 Sat] Verified the serializer preserves the org preamble.
```

Do not require `:LOGBOOK:` drawers for agent notes. Preserve existing logbooks
and timestamps when present.

## Blocking and WAITING tasks

When blocked:

1. Change status to `WAITING`.
2. Add/update `:BLOCKED_BY:`.
3. Add a short note if useful.

Examples:

```org
:BLOCKED_BY: human: confirm desired archive behavior
:BLOCKED_BY: task:57f300c5-bdb1-4494-9837-9474722c3182
:BLOCKED_BY: url:https://github.com/example/project/pull/123
:BLOCKED_BY: jira:ABC-123
```

When unblocked, move the task back to `TODO` or `STARTED` and either remove
`:BLOCKED_BY:` or move the old blocker into a note.

## Bootstrap protocol

If `TASKS.org` does not exist and the user wants persistent task memory:

1. Create `TASKS.org` in the project root.
2. Add `#+TITLE:`, the shared `#+TODO:`, and `#+INCLUDES: [[file:./design/log]]`.
3. Add a semantic section such as `* Improvements` or `* Tasks`.
4. Add the first actionable TODO task with an `:ID:` property.
5. If the task needs detailed work items, create an included org file under the
   `#+INCLUDES` directory.

## Status discipline

- Mark a task `STARTED` when beginning substantial work.
- Mark it `DONE` only when implemented and verified.
- Use `WAITING` with `:BLOCKED_BY:` for blocked work.
- Use `CANCELLED` for intentionally abandoned work.
- `DONE` and `CANCELLED` are closed states; preserve Emacs-style `CLOSED:`
  timestamps when present.
- Update parent statuses manually when child states change.
- Exception: the pi tasks extension may auto-advance a top-level `TASKS.org`
  ancestor from `TODO` to `STARTED` when an included child task is set to
  `STARTED` through the UI. When editing files directly, update parents yourself.

## Archiving without pi

- Only archive top-level tasks whose status is `DONE` or `CANCELLED`.
- Move the complete task subtree to `TASKS.ARCHIVE.org` in the project root.
- Preserve `:ID:` and content; strip `:selected:`.
- Add `:ARCHIVED: [timestamp]`.
- Preserve or inline included task context so history remains understandable.

## Interop

- pi tasks extension: optional UI over this protocol. It displays `TASKS.org`,
  injects included tasks, manages selection/status writes, and implements
  archiving. See `agents/pi/extensions/tasks/README.md` for current UI details.
- plan skill: use for planning methodology and canonical plan sections when an
  included file is specifically an implementation plan: `../plan/SKILL.md`.
