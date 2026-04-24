---
name: plan
description: Use when asked to draft, review, or execute an implementation plan. Produces concrete org TODO plans that can be linked from TASKS.org via org-memory, then guides stepwise implementation and verification.
---

# Plan

Use this skill when the user asks for a plan, implementation plan, roadmap,
retrospective plan, or to continue a multi-step workstream. Plans should be
concrete, ordered, and executable.

For persistent task memory, pair this with the org-memory skill:
`../org-memory/SKILL.md`.

## Planning principles

- Prefer a plan that can be executed and verified task-by-task.
- Separate outcomes from implementation details.
- Include validation criteria for non-trivial tasks.
- Keep completed history when drafting retrospective plans; it helps future
  agents resume context.
- Do not plan endlessly. Once the plan is good enough and the user wants action,
  start executing the next task.

## Org plan format

When the project uses org-memory, write plans as org TODO task trees.

Use only these TODO states unless the project specifies otherwise:

- `TODO`
- `STARTED`
- `WAITING`
- `DONE`
- `CANCELLED`

Use priorities consistently:

- `[#A]` critical
- `[#B]` high
- `[#C]` medium
- `[#D]` low

## Plan file structure

Plan files should begin with a title and a small number of top-level sections.

Required sections:

- `* Context` :: Background, motivation, and any initial discussion that is
  not itself actionable work. For retrospective plans, summarize scope and
  workstream here.
- `* Plan` :: The plan itself — a list of TODO headings nested under this
  heading. Use `** TODO ...` (level 2) so the tasks live under `* Plan`
  while remaining parseable by the tasks extension.

Optional sections as appropriate:

- `* Implementation` :: Notes on implementation decisions or details that may
  be useful during later maintenance.
- `* Open questions` :: Unresolved questions that should be answered before
  or during execution.

Example:

```org
#+TITLE: Descriptive Plan Title

* Context
Brief background on why this plan exists and what prompted it.

* Plan
** DONE [#A] First completed step :area:
   Short retrospective note.

** STARTED [#A] Current active task :area:
   What is being changed and how it will be verified.

** TODO [#B] Next task :area:
   Acceptance criteria.

* Implementation
Notes on key implementation decisions or subtleties.

* Open questions
- What should happen if X?
```

The tasks extension parser ignores non-TODO top-level headings
(`Context`, `Plan`, `Implementation`, `Open questions`) and does not
attribute their bodies to preceding tasks. Only TODO/STARTED/WAITING/DONE
headings inside `* Plan` become linked plan tasks in the overlay.

## Creating a plan for TASKS.org

When a parent task in `TASKS.org` needs a detailed plan:

1. Propose or use a `:PLAN:` path relative to `TASKS.org`.
2. Prefer the filename pattern:

```text
YYYY-MM-DD-short-task-name.org
```

3. Prefer an existing planning directory such as `design/log/` if present.
4. Add the property drawer to the parent task:

```org
:PROPERTIES:
:PLAN: design/log/YYYY-MM-DD-short-task-name.org
:END:
```

5. Create the linked plan file with org TODO headings.
6. Keep the linked plan parseable by the tasks extension.

## Retrospective plans

When drafting a retrospective plan for work already started:

- Mark completed work as `DONE`.
- Record key implementation outcomes and verification notes.
- Add remaining follow-up tasks as `TODO`.
- If a task represents current in-progress work, mark it `STARTED`.
- Avoid rewriting history to make it look planned in advance; label retrospective
  context clearly when useful.

## Executing from a plan

Before starting implementation:

1. Read the relevant plan file.
2. Identify the next actionable `TODO` or `STARTED` task.
3. Mark the task `STARTED` if beginning work now.
4. Implement the smallest change that satisfies the task.
5. Verify the change.
6. Mark the task `DONE` and add a short result note if useful.
7. Add newly discovered follow-up work as new `TODO` tasks.

## Updating plans after discoveries

Update the plan when implementation reveals:

- a prerequisite task,
- an architectural decision,
- a validation gap,
- a follow-up refactor,
- a blocked dependency.

Keep additions concise and actionable. Prefer one task per concrete outcome.

## Cross-reference

If a plan is part of project memory, also follow the org-memory rules in:

```text
../org-memory/SKILL.md
```
