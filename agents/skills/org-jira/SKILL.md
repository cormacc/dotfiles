---
name: org-jira
description: "Use when working with tasks that link to Jira issues. Covers Jira-specific authoring conventions on top of the org-tasks protocol — :LINKED_ISSUES: drawer key shape, #+JIRA_* keywords, agent prompts that drive the atlassian MCP for clone/claim/comment/create/transition workflows."
---

# Jira integration for org-tasks

This skill extends [`org-tasks`](../org-tasks/SKILL.md) with
Jira-specific authoring conventions and agent prompts. Use it when:

- A task references one or more Jira issues.
- The user asks to clone, claim, comment on, transition, or create a
  Jira issue.
- The user wants to know the Atlassian MCP connection state.

This skill owns Jira semantics. The underlying file format
(`:LINKED_ISSUES:` drawer property, `#+ISSUE_URL_BASE` keyword, badge
rendering, browser-open) is owned by the [`tasks`
extension](../../pi/extensions/tasks/README.md#linked-external-issues)
and is *tracker-agnostic* — the rules below apply only to Jira-shaped
links.

## File-format conventions

### Issue keys

Jira keys are stored as **bare `PROJ-NNN` tokens** in the generic
`:LINKED_ISSUES:` drawer property defined by the `tasks` extension:

```org
* TODO Refactor stim driver
:PROPERTIES:
:ID: 01234567-89ab-4def-8123-456789abcdef
:LINKED_ISSUES: MBFW-123 MBE-45
:END:
```

- Validation regex: `^[A-Z][A-Z0-9_]+-\d+$`.
- Whitespace-separated; `:LINKED_ISSUES:` is multi-valued.
- A single task may link to many Jira issues; mixing bare Jira keys
  with non-Jira org-link tokens (`[[https://github.com/.../issues/42][gh#42]]`)
  in the same drawer line is supported.
- The property is created on first link only — never auto-backfilled
  on existing tasks (mirrors `:STARTED:` behaviour).

### File-level keywords

`TASKS.org` (overridable in `TASKS.local.org`):

```org
#+ISSUE_URL_BASE: https://your-org.atlassian.net/browse/{ID}
#+JIRA_CLOUDID: 00000000-0000-4000-8000-000000000000
#+JIRA_PROJECT: MBFW
#+JIRA_BASE_URL: https://your-org.atlassian.net
```

| Keyword            | Owner          | Purpose                                                    |
| ------------------ | -------------- | ---------------------------------------------------------- |
| `#+ISSUE_URL_BASE` | `tasks`        | URL template for bare keys; rendered badges & `J` open.    |
| `#+JIRA_CLOUDID`   | `jira`         | MCP routing: skip `getAccessibleAtlassianResources`.       |
| `#+JIRA_PROJECT`   | `jira`         | Default project for `/jira create`; short-key disambiguation. |
| `#+JIRA_BASE_URL`  | `jira`         | Filter `:LINKED_ISSUES:` for Jira-shaped tokens.           |

The `tasks` extension reads only `#+ISSUE_URL_BASE`. The three
`#+JIRA_*` keywords are read only by the `jira` extension and this
skill.

`TASKS.local.org` overrides any of these (last-write-wins, mirroring
`#+SELECTED:`). Useful for per-checkout overrides like a different
default project.

### Identifying Jira tokens within `:LINKED_ISSUES:`

When `/jira *` commands need to operate only on Jira-shaped tokens
(claim, transition, comment), they apply this filter:

1. **Bare token** matches `/^[A-Z][A-Z0-9_]+-\d+$/` → Jira key.
2. **Org-link token** `[[url][label]]` whose target host matches
   `#+JIRA_BASE_URL` → Jira key. (Uncommon — Jira keys are usually
   stored bare so they can be reused across machines.)

Tokens that match neither are silently ignored by Jira workflows — a
task carrying `MBFW-123 [[https://github.com/foo/bar/issues/42][gh#42]]`
exposes only `MBFW-123` to `/jira claim`.

## Atlassian MCP connection

All Jira read/write goes through the `atlassian` MCP server, exclusively
driven by the agent. The `jira` extension itself is I/O-free and only
detects connection state by checking `pi.getAllTools()` for tools
matching the `atlassian_` prefix.

Before any Jira workflow, ensure the MCP is connected:

```
/mcp reconnect atlassian
```

If `/jira` (the status command) reports "disconnected", surface the
reconnect instruction to the user rather than retrying.

### cloudId resolution

When making MCP calls, prefer `#+JIRA_CLOUDID` from the file. If absent:

1. Call `atlassian_getAccessibleAtlassianResources`.
2. Pick the resource whose `url` field equals `#+JIRA_BASE_URL`.
3. Use its `id` as the `cloudId` for subsequent calls.

## Workflows

All workflows below are **agent-driven**: the slash command drafts a
structured prompt that *you*, the agent, dispatch to MCP tools. The
extension code itself never invokes MCP tools directly.

### Reference (read-only)

No prompt needed. The user types a Jira key into `:LINKED_ISSUES:` and
sets `#+ISSUE_URL_BASE` once; `tasks` renders badges and `J` opens
URLs. Fully offline-safe.

### Clone (`/jira clone <KEY>`)

1. Validate `KEY` against the regex above. If the user passes a bare
   number (`123`), prepend `#+JIRA_PROJECT-` (or refuse if
   `#+JIRA_PROJECT` is absent).
2. Call `atlassian_getJiraIssue` with the resolved cloudId and key.
3. Create a new task via the `tasks` extension with:
   - **Heading**: `${issue.fields.summary}`.
   - **Body**: `${issue.fields.description}` (plain-text rendering of
     the ADF body; if the body is rich Jira ADF, summarise to plain
     text rather than embedding raw ADF).
   - **Priority**: map `issue.fields.priority.name` per the table:
     `Highest → #A`, `High → #B`, `Medium → #C`, `Low → #D`,
     `Lowest → #D`. Tasks without a priority field stay unprioritised.
   - **`:LINKED_ISSUES:`**: bare `KEY` (set via `setDrawerProperty` if
     editing the org file directly, or via the `tasks` new-task flow's
     property hooks).
3. Smoke test against `SAND` only.

### Claim (`/jira claim`)

1. Resolve the cursor task's `:LINKED_ISSUES:` and filter to Jira-shaped
   tokens.
2. Call `atlassian_atlassianUserInfo` once to get the current user's
   accountId.
3. For each Jira key, call `atlassian_editJiraIssue` setting
   `assignee.accountId`.
4. Surface a one-line summary per key (key, success / error message).

### Comment (`/jira comment <markdown>`)

1. Filter `:LINKED_ISSUES:` for Jira tokens.
2. For each, call `atlassian_addCommentToJiraIssue` with the markdown
   body. The MCP server handles markdown → ADF conversion.
3. Surface a one-line summary per key.

### Create (`/jira create [PROJECT] [--type Task|Story|Bug|Epic]`)

1. Project defaults to `#+JIRA_PROJECT`. Refuse if neither argument nor
   keyword provides one.
2. Issue type defaults to `Task`. Validate via
   `atlassian_getJiraProjectIssueTypesMetadata` before submitting.
3. Call `atlassian_createJiraIssue` with summary = task heading,
   description = task body.
4. On success, append the returned key to the task's `:LINKED_ISSUES:`
   via `setDrawerProperty`.
5. Smoke test against `SAND` only.

### Transition (auto, optional)

When the user toggles a task's status (`TODO → STARTED → DONE`), and
the `jira` extension's `autoTransition` setting is enabled, attempt to
mirror the change on every Jira-shaped token:

1. Call `atlassian_getTransitionsForJiraIssue`.
2. Pick a transition whose name matches the target state by convention:
   - `STARTED` → "Start Progress" or "In Progress".
   - `DONE` → "Done", "Closed", or "Resolved" (try in order).
3. If no match, surface a chooser to the user instead of guessing.

This requires `tasks` to publish status-change events on the pi event
bus. If unavailable, the auto-transition flow blocks until the
prerequisite extension point lands.

## Question-handling

Default mode for this work: batch minor implementation ambiguities into
the parent change-record's `* Open questions`; raise immediately
anything that affects downstream design (extension API, data shape,
cross-extension contract). See the parent
`design/log/2026-04-28-jira-integration.org` for the latest list.

## Sandbox

All write-path development and smoke testing runs against project `SAND`.
Never call `editJiraIssue`, `addCommentToJiraIssue`, `createJiraIssue`,
or `transitionJiraIssue` against any other project until the relevant
plan stage is signed off.

## Offline / disconnected behaviour

The badge display and `J` browser-open work unconditionally because they
live in `tasks` and don't touch the MCP. Anything in this skill that
needs the MCP must surface a clear notification ("Atlassian MCP not
connected — run /mcp reconnect atlassian") rather than failing
silently.
