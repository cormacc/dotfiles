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

## File format and structure

For the org file format (TODO state cycle, priorities, `:ID:` UUIDs, property
drawers), the canonical plan file section layout (`* Context` / `* Plan` /
`* Implementation` / `* Open questions`), and the conventions for creating a
linked plan from a `TASKS.org` task (`:PLAN:` property, file naming,
`#+TITLE` / `#+DATE` / `#+PARENT_ID` / `#+TODO` declarations, `#+PLANS`
directory), follow the org-memory skill: `../org-memory/SKILL.md`. That skill
is the single source of truth for those rules.

When the user asks for a plan that should persist as project memory, create
it as a linked plan file under the parent `TASKS.org` task per the org-memory
protocol. For ad-hoc plans (chat, scratch file, scoping discussion), the
planning principles above and the workflows below apply regardless of medium.

## Executing from a plan

Before starting implementation:

1. Read the relevant plan file.
2. Identify the next actionable `TODO` or `STARTED` task.
3. If using org-memory/task tooling, respect the current `:selected:` marker as
   the active task signal. Agents should not write or clear `:selected:`
   directly unless explicitly asked or acting through a task-selection tool.
4. Mark the task `STARTED` if beginning work now. (For the pi tasks
   extension's narrow STARTED propagation rule and the manual-edit exception,
   see the org-memory skill's "Status discipline" section.)
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

This skill defers all file-format and persistence rules to org-memory:
`../org-memory/SKILL.md`. The cross-reference is one-directional — org-memory
does not require this skill, and is fully usable on its own.
