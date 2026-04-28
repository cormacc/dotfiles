---
name: org-tasks
description: "Use when maintaining or resuming project work stored in TASKS.org and linked change-record files. Covers the org task-memory protocol: TODO states, IDs, IMPORT links, change-records (proactive and retrospective), status discipline, archiving, and resume workflows."
---

# Org-mode task management and memory protocol

Use this skill when the user asks to work from, update, resume, or review
tasks. The canonical project memory index is `TASKS.org` in the project
root. A task may link to a *change-record* (a separate org file capturing
the task's context, plan, and implementation notes) via a `#+IMPORT:`
keyword.

This skill owns the durable file protocol: file format, properties,
keywords, statuses, selection, and archive layout. The change-record
section structure (`* Context`, `* Plan`, `* Implementation`, optional
`* Open questions`) is owned by the `org-plan` skill
(`../org-plan/SKILL.md`).

## File protocol

`TASKS.org` and included task files declare the shared TODO cycle:

```org
#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)
```

`TASKS.org` may also declare the default change-record directory:

```org
#+DEFAULT_PLAN_DIR: [[file:./design/log]]
```

When the keyword is absent or malformed the default is
`[[file:./design/log]]`.

### Task headings

```org
** TODO [#A] Implement feature :area:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:CREATED: [2026-04-25 Sat 09:00]
:END:
#+IMPORT: [[file:design/log/2026-04-25-feature.org]]
Optional description text.
```

- **States**: `TODO`, `STARTED`, `WAITING`, `DONE`, `CANCELLED`.
- **Priorities**: `[#A]` critical, `[#B]` high, `[#C]` medium, `[#D]` low.
- **Tags**: semantic categories. There are no reserved operational tags.
- **`:ID:`**: UUID v4, required on every task and subtask.
- **`:CREATED:`**: `[YYYY-MM-DD Day HH:MM]`, set on creation. Do not
  backfill on existing tasks. Do not prefix the description with an
  inline `[YYYY-MM-DD Day]` creation marker — that role is owned by
  the property.
- **`:STARTED:`**: `[YYYY-MM-DD Day HH:MM]`, written the first time
  a task transitions out of `TODO` into `STARTED`. Preserved on
  subsequent `DONE -> STARTED` re-opens. Used to scope `git log`
  for retrospective change-records.
- **`CLOSED:`**: `[YYYY-MM-DD Day HH:MM]`, written on transition to
  `DONE` or `CANCELLED`. Lives on its own line *between the heading
  and the `:PROPERTIES:` drawer* (matches `org-todo`'s native
  behaviour). Preserve existing values; do not replace them.
- **`:BLOCKED-BY:`**: free-form blocker reference on `WAITING` tasks
  (e.g. `human: …`, `task:<UUID>`, `url:…`, `jira:ABC-123`).
- **`#+IMPORT:`**: clickable `[[file:...]]` link on its own line in
  the task body, after the `:END:` of the drawer. Resolves relative
  to the file containing the keyword. May also appear at file root
  (before any heading) to inject tasks from another file at the root.
  Preserve any existing bare or labelled link form on round-trip.

Always obtain timestamps via `date +"%Y-%m-%d %a %H:%M"` rather than
computing them manually.

### Example `TASKS.org`

```org
#+TITLE: Project Tasks
#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)
#+DEFAULT_PLAN_DIR: [[file:./design/log]]

* Improvements

** TODO [#A] Implement authentication :backend:security:
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:CREATED: [2026-04-25 Sat 09:00]
:END:
#+IMPORT: [[file:design/log/2026-04-25-authentication.org]]
Initial scope captured from user request.

* Housekeeping

** WAITING [#C] Update upstream dependency :nix:
:PROPERTIES:
:ID: fedcba98-7654-4321-8fed-cba987654321
:CREATED: [2026-04-20 Mon 14:30]
:BLOCKED-BY: url:https://github.com/example/project/pull/123
:END:
Waiting on upstream merge.
```

Keep `TASKS.org` high-level. Put detailed checklists and implementation
history in change-record files.

## Selection state

The active task for a contributor is stored in a **gitignored**
`TASKS.local.org` at the project root, expressed as a single keyword:

```org
#+SELECTED: 01234567-89ab-4def-8123-456789abcdef
```

- `TASKS.local.org` is per-checkout and must be in `.gitignore`.
- Absent file or empty `#+SELECTED:` value means "no selection".
- Resolve the UUID against `:ID:` properties in the loaded task graph.
- Writers must use atomic write-then-rename so file watchers never see
  a half-written file.

`TASKS.local.org` may also contain task headings and `#+IMPORT:`
keywords alongside `#+SELECTED:` — these are local drafts not visible
to other checkouts until published.

## Change-records

A *change-record* is a separate org file linked from a task via
`#+IMPORT:`. Two flows produce the same artefact:

1. **Proactive** — created before work begins. Agent drafts `* Context`
   and `* Plan` up front; `* Implementation` fills in as plan tasks
   transition `TODO -> STARTED -> DONE`.
2. **Retrospective** — created after the parent task closed without a
   prior plan. Agent uses the parent's `:STARTED:` and `CLOSED:`
   timestamps to scope `git log`, then drafts `* Context` and
   `* Implementation` from the commit history. `* Plan` may be empty
   or hold a brief retrospective list including failed attempts.

See `../org-plan/SKILL.md` for the section structure both flows produce
and the planning workflow.

## Status discipline

- Mark `STARTED` when beginning substantial work; write `:STARTED:`
  on the first such transition.
- Mark `DONE` only when implemented and verified; write `CLOSED:` on
  transition.
- Use `WAITING` with `:BLOCKED-BY:` for blocked work; clear or move
  the blocker to a note when unblocked.
- Use `CANCELLED` for intentionally abandoned work; write `CLOSED:`.
- When a child plan task advances, update its ancestors in `TASKS.org`
  to keep parent status meaningful (e.g. parent `TODO -> STARTED` when
  any child reaches `STARTED`).

## Starting or resuming work

1. Read `TASKS.org`.
2. Resolve `#+SELECTED:` from `TASKS.local.org` against the task graph;
   fall back to a user-named task, the first `STARTED` task, or context.
3. Follow the active task's `#+IMPORT:` link if present. In a plan,
   resume the first `STARTED` task or the first actionable `TODO`.
4. Read nearby task notes plus relevant `* Context` /
   `* Implementation` sections before editing code.
5. Keep statuses and durable notes synchronized as work proceeds.

## Creating tasks and change-records

- Use the smallest useful task granularity: each task should describe
  a concrete outcome that can become `DONE`.
- Prefer adding detail to change-records rather than bloating
  `TASKS.org`.
- New change-records use `YYYY-MM-DD-short-task-name.org` under
  `#+DEFAULT_PLAN_DIR` and declare `#+TITLE:`, `#+DATE:`, `#+PARENT_ID:`
  (the parent task's `:ID:`), and the shared `#+TODO:` cycle.
- Add discovered work as new `TODO` tasks rather than burying it in
  prose. Do not remove completed historical tasks unless asked.

## Archiving

Only top-level `DONE`/`CANCELLED` tasks are archived. Archiving moves
the complete subtree to `TASKS.archive.org` in the project root,
preserves `:ID:` and content, and adds an `:ARCHIVED: [timestamp]`
property. The `#+IMPORT:` link is preserved; plan file contents are
not inlined.

## Bootstrap

If `TASKS.org` does not exist and the user wants persistent task
memory: create it in the project root with `#+TITLE:`, the shared
`#+TODO:`, and `#+DEFAULT_PLAN_DIR: [[file:./design/log]]`; add a
semantic section (e.g. `* Improvements`) and the first actionable
`TODO` with `:ID:` and `:CREATED:` properties. Detailed work items go
in an included change-record under `#+DEFAULT_PLAN_DIR`.

## Extension points

Third-party skills and pi extensions can build on the task graph by
attaching their own data without modifying this protocol:

- **Unknown `#+` keywords** in `TASKS.org` and `TASKS.local.org`
  preambles round-trip through the parser/serializer untouched. Other
  skills or extensions may claim them for their own use.
- **Unknown drawer properties** on task headings round-trip untouched.
  Other skills or extensions may claim them for per-task data.
- **Naming convention**: third-party properties and keywords should
  use an `UPPERCASE_NAMESPACE_` prefix (e.g. `:NAMESPACE_FOO:`,
  `#+NAMESPACE_BAR`) so they don't collide with first-party
  metadata.
- **`TASKS.local.org` keyword overrides** are last-write-wins,
  mirroring the existing `#+SELECTED:` rule. A keyword present in both
  files takes its value from `TASKS.local.org`.

First-party generic extension features in the `tasks` extension itself
(documented in `agents/pi/extensions/tasks/README.md`):

- **`:LINKED_ISSUES:`** drawer property — multi-valued list of
  external-tracker references; rendered as badges on task rows.
- **`#+ISSUE_URL_BASE:`** keyword — URL template used to resolve bare
  keys in `:LINKED_ISSUES:` to clickable URLs.

These two features are tracker-agnostic; tracker-specific behaviour
(workflow names, MCP routing, slash commands) lives in companion
extensions and skills, not in this protocol.

## Tooling

The pi tasks extension and the `tasks-org` Emacs minor mode automate
ID assignment, `:CREATED:` / `:STARTED:` / `CLOSED:` timestamps,
parent status propagation, and archive mechanics against this
protocol. When editing task files by hand, follow the rules above
explicitly.
