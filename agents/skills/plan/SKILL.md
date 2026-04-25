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
- Capture important design decisions in the plan context or implementation
  notes so later sessions can understand why work was shaped this way.
- Do not plan endlessly. Once the plan is good enough and the user wants action,
  start executing the next task.

## Org plan format

When the project uses org-memory, write plans as org TODO task trees and follow
that skill's ID and property protocol. Newly created plan files should declare
the supported TODO state cycle near the top of the file:

```org
#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)
```

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

Every task and subtask should have an `:ID:` property containing a UUID v4 value:

```org
** TODO [#A] Implement feature :area:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:END:
```

When loading a plan as project memory, add missing IDs to loaded tasks before
editing, as described in the org-memory skill.

## Plan file structure

Plan files should begin with a title and a small number of top-level sections.

Required sections:

- `* Context` :: Background, motivation, initial discussion, and design
  decisions that are not themselves actionable work. For retrospective plans,
  summarize scope and workstream here. When rationale matters, use an optional
  `** Design decisions` subsection under `* Context`.
- `* Plan` :: The plan itself — a list of TODO headings nested under this
  heading. Use `** TODO ...` (level 2) so the tasks live under `* Plan`
  while remaining parseable by the tasks extension.

Optional sections as appropriate:

- `* Implementation` :: Notes on implementation decisions or details that may
  be useful during later maintenance.
- `* Open questions` :: Unresolved questions that should be reviewed as a batch
  later, rather than interrupting implementation when the user asked not to be
  prompted.

Example:

```org
#+TITLE: Descriptive Plan Title
#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)

* Context
Brief background on why this plan exists and what prompted it.

** Design decisions

- Decision A :: Rationale.

* Plan
** DONE [#A] First completed step :area:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:END:
Short retrospective note.

** STARTED [#A] Current active task :area:
:PROPERTIES:
:ID: 89abcdef-0123-4567-89ab-cdef01234567
:END:
What is being changed and how it will be verified.

** TODO [#B] Next task :area:
:PROPERTIES:
:ID: fedcba98-7654-4321-8fed-cba987654321
:END:
Acceptance criteria.

* Implementation
Notes on key implementation decisions or subtleties.

* Open questions
- What should happen if X?
```

The tasks extension parser ignores non-task top-level headings
(`Context`, `Plan`, `Implementation`, `Open questions`) and does not attribute
their bodies to preceding tasks. For predictable results, keep actionable
headings under `* Plan`; that is the intended convention for linked plans.

Task headings may nest deeper than level 2, for example `*** TODO ...` under a
plan task. The tasks extension parses deeper nested TODO headings, but status is
not automatically propagated to parent tasks. Agents must update parent statuses
manually.

## Creating a plan for TASKS.org

When a parent task in `TASKS.org` needs a detailed plan:

1. Propose or use a `:PLAN:` path relative to `TASKS.org`.
2. Prefer the filename pattern:

```text
YYYY-MM-DD-short-task-name.org
```

3. Prefer an existing planning directory such as `design/log/` if present.
4. Add the property drawer to the parent task. For new plans, prefer the org
   file-link form so the property is clickable in Emacs:

```org
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:PLAN: [[file:design/log/YYYY-MM-DD-short-task-name.org]]
:END:
```

   Bare relative paths and labelled file links are accepted for compatibility
   and should be preserved when already present:

```org
:PLAN: design/log/YYYY-MM-DD-short-task-name.org
:PLAN: [[file:design/log/YYYY-MM-DD-short-task-name.org][Plan]]
```

   The tasks extension's `p` keybinding currently writes the `[[file:...]]`
   form so the property is clickable in Emacs by default.

5. Create the linked plan file with `#+TITLE:` and `#+TODO:` declarations.
6. Put org TODO headings under `* Plan`.
7. Add UUID `:ID:` properties to every task/subtask in the plan.
8. Keep the linked plan parseable by the tasks extension.

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
3. If using org-memory/task tooling, respect the current `:selected:` marker as
   the active task signal. Agents should not write or clear `:selected:`
   directly unless explicitly asked or acting through a task-selection tool.
4. Mark the task `STARTED` if beginning work now.
5. Implement the smallest change that satisfies the task.
6. Verify the change.
7. Mark the task `DONE` and add a short result note if useful.
8. Add newly discovered follow-up work as new `TODO` tasks.
9. If the user asked not to be interrupted with questions, append questions to
   `* Open questions` or a final question section in the plan for batch review.

## Updating plans after discoveries

Update the plan when implementation reveals:

- a prerequisite task,
- an architectural decision,
- a validation gap,
- a follow-up refactor,
- a blocked dependency,
- an unanswered question that should be reviewed later.

Keep additions concise and actionable. Prefer one task per concrete outcome.

## Cross-reference

If a plan is part of project memory, also follow the org-memory rules in:

```text
../org-memory/SKILL.md
```
