---
name: plan
description: Use when asked to draft, review, or execute an implementation plan. Produces concrete plans as org-memory included task files, then guides stepwise implementation and verification.
---

# Plan

Use this skill when the user asks for a plan.
Plans are org-memory included task files: concrete, ordered, and executable.

This skill owns planning methodology and plan section conventions;
org-memory owns file-format and persistence rules: `../org-memory/SKILL.md`.

## Planning principles

- Prefer a plan that can be executed and verified task-by-task.
- Separate outcomes from implementation details.
- Include validation criteria for non-trivial tasks.
- Keep completed history when drafting retrospective plans; it helps future
  agents resume context.
- Capture important design decisions in context or implementation notes so later
  sessions understand why work was shaped this way.
- Do not plan endlessly. Once the plan is good enough and the user wants action,
  start executing the next task.

## Plan files

Plan files follow the org-memory file protocol and add a planning-oriented section convention:

Required sections:

- `* Context` :: A self-contained summary: background, motivation, scope, and
  rationale sufficient for an agent or reviewer to understand the work without
  reading the full plan. Use optional `** Design decisions` when alternatives,
  constraints, or trade-offs matter.
- `* Plan` :: Executable org TODO headings. Use `** TODO ...` for top-level plan
  tasks so they live under `* Plan` while remaining parseable by task tooling.

Optional sections:

- `* Implementation` :: Notes on decisions, tricky details, validation outcomes,
  and maintenance context discovered while executing.
- `* Open questions` :: Questions deferred for batch review rather than
  interrupting implementation.

Minimal skeleton:

```org
#+TITLE: Descriptive Plan Title
#+DATE: 2026-04-25 Sat
#+PARENT_ID: 01234567-89ab-4def-8123-456789abcdef
#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)

* Context
Brief self-contained summary.

** Design decisions
- Decision :: Rationale.

* Plan
** TODO [#A] First executable step :area:
:PROPERTIES:
:ID: 89abcdef-0123-4567-89ab-cdef01234567
:END:
Acceptance criteria.

* Implementation

* Open questions
```

Task headings may nest deeper than level 2. Keep parent statuses meaningful;
see org-memory for status rules.

## Retrospective plans

When drafting a plan for work already started:

- Mark completed work as `DONE`.
- Record key implementation outcomes and verification notes.
- Add remaining follow-up work as `TODO`.
- Mark current in-progress work `STARTED`.
- Avoid rewriting history to make it look planned in advance; label
  retrospective context clearly when useful.

## Executing from a plan

Before starting implementation:

1. Ask whether questions should be batched in `* Open questions` for final
   review or raised immediately as they arise.
2. Read the relevant plan file.
3. Identify the next actionable `TODO` or `STARTED` task.
4. Respect the current `:selected:` marker as the active task signal. Do not
   write or clear `:selected:` directly unless explicitly asked or acting
   through a task-selection tool.
5. Mark the task `STARTED` if beginning work now. See org-memory for parent
   status discipline.
6. Implement the smallest change that satisfies the task.
7. Verify the change.
8. Mark the task `DONE` and add a short result note if useful.
9. Add newly discovered follow-up work as new `TODO` tasks.
10. Handle questions according to the agreed mode: append to `* Open questions`
    or raise immediately.

## Updating plans after discoveries

Update the plan when implementation reveals:

- a prerequisite task,
- an architectural decision,
- a validation gap,
- a follow-up refactor,
- a blocked dependency,
- an unanswered question that should be reviewed later.

Keep additions concise and actionable. Prefer one task per concrete outcome.

