---
name: org-memory
description: Use when maintaining or resuming project work stored in TASKS.org and linked org plan files. Covers the org task-memory protocol, PLAN properties, IDs, status updates, and compatibility with or without the pi tasks extension.
---

# Org Memory

Use this skill when the user asks to work from, update, resume, review, or create
project task memory in org files. The canonical project memory index is
`TASKS.org` in the project root. Detailed workstreams live in linked org plan
files referenced by a task's `:PLAN:` property.

This skill is harness-agnostic. The pi-specific tasks extension provides a UI on
top of the same files, but the files remain plain org-mode and must be useful
without pi.

## Responsibility boundary

This skill defines the shared file-format and agent-behaviour protocol:

- `TASKS.org` and linked plan file structure,
- supported TODO states and priority conventions,
- `:ID:`, `:PLAN:`, and `:BLOCKED_BY:` properties,
- task notes, blockers, archiving, bootstrap, and resume workflows.

The tasks extension owns UI concerns:

- commands, keybindings, and overlays,
- visual rendering and task navigation,
- selection mechanics,
- safe file round-tripping,
- status/selection writes made through the UI,
- archive command implementation.

When this skill and the extension documentation differ, verify the extension's
current implementation before relying on extension-specific UI details.

## Core model

- `TASKS.org` is the project memory index.
- `TASKS.org` and newly scaffolded plan files should declare the supported TODO
  states explicitly near the top of the file. `TASKS.org` may also declare the
  default directory for new linked plans using org-link syntax:

```org
#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)
#+PLANS: [[file:./design/log]]
```

- Each actionable task is an org heading with a TODO status:
  - `TODO`, `STARTED`, `WAITING`, `DONE`, `CANCELLED`
- Optional priority appears after status:
  - `[#A]` critical, `[#B]` high, `[#C]` medium, `[#D]` low
- Tags are trailing org tags and should describe semantic categories:
  - examples: `:agents:`, `:nix:`, `:backend:`, `:security:`
- `:selected:` is the single reserved operational tag. It marks the currently
  selected task for task-selection tooling. Agents should preserve and respect
  it, and should not create, move, or clear it unless explicitly asked or acting
  through a task-selection tool.
- Every task and subtask in `TASKS.org` and linked plan files must have an
  `:ID:` property containing a UUID v4 value. This follows the standard
  org-mode/org-id.el convention and gives tools stable identity across task
  renames and restructuring.
- A task can link a detailed plan via an org properties drawer:

```org
* TODO [#A] Implement feature :area:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:PLAN: [[file:design/log/2026-04-24-short-feature-name.org]]
:END:
```

- Use the `[[file:...]]` form for newly created `:PLAN:` values so the property
  is clickable in Emacs. Bare relative paths and labelled org links are accepted
  for compatibility and should be preserved when already present.
- The `:PLAN:` value resolves relative to the org file that declares it.
- New plan-file suggestions should use the top-level `#+PLANS: [[file:...]]`
  directory from `TASKS.org`; when absent, default to `[[file:./design/log]]`.
- A linked plan file is itself a parseable org task tree using the same TODO
  heading syntax. Newly created linked plans should include `#+PARENT_ID:` with
  the parent `TASKS.org` task's UUID `:ID:`.
- In the pi tasks extension, linked plan tasks are injected as children of the
  parent task. Without the extension, they remain accessible as normal org files.

## Example TASKS.org

```org
#+TITLE: Project Tasks
#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)
#+PLANS: [[file:./design/log]]

* Improvements

** TODO [#A] Implement authentication :backend:security:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:PLAN: [[file:design/log/2026-04-25-authentication.org]]
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

Keep `TASKS.org` high-level. Put implementation checklists and detailed work
history in linked plan files.

## ID discipline

- Generate a UUID v4 for every task or subtask when creating it.
- Store it as `:ID:` in the task's properties drawer.
- When loading project task memory, scan `TASKS.org` and any linked plan files
  actually loaded for the current workstream. Add `:ID:` to loaded tasks and
  subtasks that lack one before making other edits to those files.
- Preserve existing IDs, properties, heading text, and surrounding formatting.
- Do not scan or mutate arbitrary org files outside the loaded task-memory graph.

## When starting work

1. Read `TASKS.org` from the project root.
2. Add missing `:ID:` properties to loaded tasks/subtasks before further edits.
3. Locate the relevant task:
   - Prefer the task marked with the reserved `:selected:` tag if present.
   - Otherwise use the task named by the user or infer from context.
4. If the task has a `:PLAN:` property, read that linked plan file.
5. Treat the linked plan as the working checklist for this workstream.
6. Before changing code, identify the next unfinished `TODO`/`STARTED` task in
   the selected task hierarchy.
7. Keep status synchronized as work proceeds.

## Resuming interrupted work

When the user asks to resume or continue:

1. Read `TASKS.org`.
2. Find the task marked with `:selected:`. If none exists, find the first
   `STARTED` task. If still ambiguous, use the user's context.
3. Add missing `:ID:` properties to loaded tasks/subtasks.
4. Follow the selected task's `:PLAN:` link if present.
5. In the linked plan, resume the first `STARTED` task. If none exists, choose
   the first actionable `TODO` task.
6. Read nearby task notes plus the plan's self-contained `* Context` summary
   (including optional `** Design decisions`) and relevant `* Implementation`
   sections before editing code.
7. Update task status and notes as work proceeds.

## When creating or updating tasks

- Use the smallest useful task granularity: each task should describe a concrete
  outcome that can become `DONE`.
- Prefer adding detail to the linked plan rather than bloating `TASKS.org`.
- Keep `TASKS.org` high-level; keep implementation checklists in plan files.
- Use semantic tags for topic/category only. Avoid operational tags other than
  the reserved `:selected:` tag.
- Use `STARTED` for active work, `WAITING` for blocked work, `DONE` for
  completed work, and `CANCELLED` for work intentionally abandoned.
- Do not remove completed historical tasks from a plan unless the user asks;
  they are useful memory.
- If new work is discovered, add it as a new TODO rather than hiding it in prose.

## Task notes

Use plain text under the task heading for durable human/agent context. Prefer a
short indented or paragraph note, optionally prefixed with an inactive timestamp:

```org
** DONE [#B] Add parser regression coverage :agents:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:END:
[2026-04-25 Sat] Verified the serializer preserves the org preamble and plan
sections when status changes are saved.
```

Do not require `:LOGBOOK:` drawers for agent notes. Preserve existing logbooks
and timestamps when present.

## Blocking and WAITING tasks

When a task is blocked:

1. Change its status to `WAITING`.
2. Add or update `:BLOCKED_BY:` in the properties drawer.
3. Add a short note if the rationale or next action is useful for later.

Examples:

```org
:BLOCKED_BY: human: confirm desired archive behavior
:BLOCKED_BY: task:57f300c5-bdb1-4494-9837-9474722c3182
:BLOCKED_BY: url:https://github.com/example/project/pull/123
:BLOCKED_BY: jira:ABC-123
```

When unblocked, move the task back to `TODO` or `STARTED` and either remove
`:BLOCKED_BY:` or move the old blocker into a note.

## When creating a linked plan

1. Suggest a path before creating it unless the user already gave one.
2. Use this naming pattern for new plan files:

```text
YYYY-MM-DD-short-task-name.org
```

3. Prefer the top-level `#+PLANS: [[file:...]]` directory from `TASKS.org`.
   If unspecified, use `[[file:./design/log]]`.
4. Add the plan path to the parent task's properties drawer using the clickable
   org link form for new plans:

```org
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:PLAN: [[file:design/log/YYYY-MM-DD-short-task-name.org]]
:END:
```

5. Preserve bare path or labelled-link forms when already present:

```org
:PLAN: design/log/YYYY-MM-DD-short-task-name.org
:PLAN: [[file:design/log/YYYY-MM-DD-short-task-name.org][Plan]]
```

6. Include `#+TITLE:`, `#+DATE:`, `#+PARENT_ID:`, and the same `#+TODO: TODO(t)
   STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)` declaration in newly scaffolded
   plan files. `#+PARENT_ID:` should match the parent task's `:ID:` in
   `TASKS.org`.
7. Use the plan skill's file structure: a self-contained `* Context` summary,
   optional `** Design decisions`, and org TODO headings under `* Plan`.
   If the parent task already has subtasks, move those subtask trees into the
   plan and leave a plain-text bullet summary on the parent task in `TASKS.org`.
   Include enough retrospective context to resume later.

## Bootstrap protocol

If `TASKS.org` does not exist and the user wants persistent task memory:

1. Create `TASKS.org` in the project root.
2. Add a `#+TITLE:` line.
3. Add `#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)` so
   org-mode users get the same state cycle as agents and tooling.
4. Add `#+PLANS: [[file:./design/log]]` so agents and the tasks extension have
   a default directory for newly created linked plans.
5. Add a high-level semantic section such as `* Improvements` or `* Tasks`.
6. Add the first actionable TODO task with an `:ID:` property.
7. If the task needs implementation detail, create a linked plan file under the
   `#+PLANS` directory, creating that directory if appropriate for the project.

## Status discipline

- Mark a task `STARTED` when beginning substantial work on it.
- Mark it `DONE` only when the requested change is implemented and verified.
- Add a brief task note when the result or rationale will matter later.
- If blocked, mark `WAITING` and record the dependency in `:BLOCKED_BY:`.
- `DONE` and `CANCELLED` are closed states. Use Emacs-style `CLOSED:`
  timestamps when the workflow supports them, and preserve existing stamps
  when closing or editing tasks.
- If a parent task's subtasks change state, update the parent status manually;
  do not assume tooling will propagate status automatically.
- **Exception — pi tasks extension**: when a plan subtask's status is set to
  `STARTED` through the extension UI, the extension automatically advances the
  top-level `TASKS.org` ancestor from `TODO` to `STARTED`. Agents should still
  update parent statuses explicitly when editing files directly.

## Using the pi tasks extension

The pi tasks extension is an optional UI over this file protocol. It displays
`TASKS.org`, injects linked plan tasks, manages the reserved `:selected:` tag,
writes status changes, and implements archiving. See the extension README for
current commands, keybindings, and UI behaviour:

```text
agents/pi/extensions/tasks/README.md
```

Do not rely on the extension being present. Always keep the org files correct.

## Without the pi tasks extension

Use plain file editing:

1. Read `TASKS.org`.
2. Follow `:PLAN:` links manually.
3. Update org TODO keywords, properties, and notes directly.
4. Preserve properties drawers, `:ID:` values, and linked plan paths.
5. Keep linked plan paths relative and portable.

For archiving without pi:

- Only archive top-level tasks whose status is `DONE` or `CANCELLED`.
- Move the complete task subtree to `TASKS.ARCHIVE.org` in the project root.
- Preserve the task's `:ID:` and content.
- Strip `:selected:` from the archived copy.
- Add an `:ARCHIVED: [timestamp]` property.
- Preserve or inline linked plan context so history remains understandable.
- Do not delete historical task content.

## Interop with planning workflows

For larger planning tasks, use the `plan` skill if available. It should create
or update linked org plan files that comply with this org-memory format.

Relative reference from this skill directory: `../plan/SKILL.md`.
