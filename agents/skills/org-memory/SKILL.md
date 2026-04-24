---
name: org-memory
description: Use when maintaining or resuming project work stored in TASKS.org and linked org plan files. Covers the org task-memory protocol, PLAN properties, status updates, and compatibility with or without the pi tasks extension.
---

# Org Memory

Use this skill when the user asks to work from, update, resume, review, or create
project task memory in org files. The canonical project memory index is
`TASKS.org` in the project root. Detailed workstreams live in linked org plan
files referenced by a task's `:PLAN:` property.

This skill is harness-agnostic. The pi-specific tasks extension provides a UI on
top of the same files, but the files remain plain org-mode and must be useful
without pi.

## Core model

- `TASKS.org` is the project memory index.
- Each actionable task is an org heading with a TODO status:
  - `TODO`, `STARTED`, `WAITING`, `DONE`, `CANCELLED`
- Optional priority appears after status:
  - `[#A]` critical, `[#B]` high, `[#C]` medium, `[#D]` low
- Tags are trailing org tags: `:tag1:tag2:`
- A task can link a detailed plan via an org properties drawer:

```org
* TODO [#A] Implement feature :area:
:PROPERTIES:
:PLAN: design/log/2026-04-24-short-feature-name.org
:END:
```

- The `:PLAN:` value is a path relative to the org file that declares it.
- A linked plan file is itself a parseable org task tree using the same TODO
  heading syntax.
- In the pi tasks extension, linked plan tasks are injected as children of the
  parent task. Without the extension, they remain accessible as normal org files.

## When starting work

1. Read `TASKS.org` from the project root.
2. Locate the relevant task:
   - Prefer the task marked with `:selected:` if present.
   - Otherwise use the task named by the user or infer from context.
3. If the task has a `:PLAN:` property, read that linked plan file.
4. Treat the linked plan as the working checklist for this workstream.
5. Before changing code, identify the next unfinished `TODO`/`STARTED` task in
   the selected task hierarchy.
6. Keep status synchronized as work proceeds.

## When creating or updating tasks

- Use the smallest useful task granularity: each task should describe a concrete
  outcome that can become `DONE`.
- Prefer adding detail to the linked plan rather than bloating `TASKS.org`.
- Keep `TASKS.org` high-level; keep implementation checklists in plan files.
- Use `STARTED` for active work, `WAITING` for blocked work, `DONE` for
  completed work, and `CANCELLED` for work intentionally abandoned.
- Do not remove completed historical tasks from a plan unless the user asks;
  they are useful memory.

## When creating a linked plan

1. Suggest a path before creating it unless the user already gave one.
2. Use this naming pattern for new plan files:

```text
YYYY-MM-DD-short-task-name.org
```

3. Prefer storing plans under a project design/log or planning directory when
   present, e.g. `design/log/`.
4. Add the relative path to the parent task's properties drawer:

```org
:PROPERTIES:
:PLAN: design/log/YYYY-MM-DD-short-task-name.org
:END:
```

5. Draft the plan as org TODO headings; include enough retrospective context to
   resume later.

## Status discipline

- Mark a task `STARTED` when beginning substantial work on it.
- Mark it `DONE` only when the requested change is implemented and verified.
- Add a brief note under the task when the result or rationale will matter later.
- If blocked, mark `WAITING` and record the dependency or question.
- `DONE` and `CANCELLED` are closed states. If the surrounding workflow tracks
  `CLOSED:` timestamps, preserve them when closing tasks.
- If new work is discovered, add it as a new TODO rather than hiding it in prose.

## Using the pi tasks extension

If the pi tasks extension is available:

- `/tasks` opens the task overlay.
- `s` selects a task and writes `:selected:` to the task.
- The selected marker can move down into subtasks, while the pinned overlay
  continues to show the containing top-level task tree.
- The selected task and linked plan tasks appear in a pinned top overlay.
- Status changes in the overlay update the underlying org file immediately.
- The pinned overlay also refreshes when `TASKS.org` or any linked plan file is modified on disk, so edits made via `e` (or any other external editor) appear without reopening `/tasks`.
- `e` opens the selected task's source file/line in Emacs.
- `A` archives the top-level selected workstream when its status is `DONE` or
  `CANCELLED`.

Do not rely on the extension being present. Always keep the org files correct.

## Without the pi tasks extension

Use plain file editing:

1. Read `TASKS.org`.
2. Follow `:PLAN:` links manually.
3. Update org TODO keywords and notes directly.
4. Preserve properties drawers when editing headings.
5. Keep linked plan paths relative and portable.

## Interop with planning workflows

For larger planning tasks, use the `plan` skill if available. It should create
or update linked org plan files that comply with this org-memory format.

Relative reference from this skill directory: `../plan/SKILL.md`.
