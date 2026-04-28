# Jira Extension

Agent-driven Jira workflows backed by the [Atlassian
MCP](https://developer.atlassian.com/) server. Owns slash commands, MCP
routing, and Jira-specific authoring conventions; stays composable on top
of the generic `tasks` extension's tracker-agnostic linkage features
(`:LINKED_ISSUES:` drawer property + `#+ISSUE_URL_BASE` keyword).

## Status

Read-only and write workflows implemented (clone / claim / comment /
create). Optional `autoTransition` on local TODO→STARTED→DONE cycles
still pending; depends on the `tasks` extension publishing a
status-change event on the pi event bus.

## Commands

| Command                                | Status      | Description                                            |
| -------------------------------------- | ----------- | ------------------------------------------------------ |
| `/jira`                                | Implemented | Print Atlassian MCP connection status.                 |
| `/jira status`                         | Implemented | Alias for `/jira`.                                     |
| `/jira clone KEY [KEY...]`             | Implemented | Pull issue(s) from Jira → create local task(s).        |
| `/jira claim`                          | Implemented | Set assignee on every Jira-shaped issue on the selected task. |
| `/jira comment <markdown>`             | Implemented | Add a comment to every Jira-shaped issue on the selected task. |
| `/jira create [PROJECT] [--type Type]` | Implemented | Promote the selected task to a new Jira issue.         |
| auto-transition (no command)           | Pending     | Mirror local TODO→STARTED→DONE on linked Jira issues.   |

All workflows are *agent-driven*: the slash command drafts a structured
prompt (using the conventions in the `org-jira` skill) and dispatches
it via `pi.sendUserMessage`. The agent then performs the actual MCP
calls and TASKS-file edits. The extension itself stays I/O-free for
write paths.

## Connection model

The extension itself is I/O-free. All Jira access is mediated by the
agent through the `atlassian` MCP server. To connect:

```
/mcp reconnect atlassian
```

After reconnect, `pi.getAllTools()` exposes a set of `atlassian_*` tools
(issue read/write, transitions, comments, JQL search, etc.). The
extension uses the presence of those tools as a connection-status proxy
without invoking them directly.

## Linkage to tasks

Jira keys live in the generic `:LINKED_ISSUES:` drawer property defined
by the `tasks` extension (see
`agents/pi/extensions/tasks/README.md#linked-external-issues`). Jira
keys are stored as **bare `PROJ-NNN` tokens**, not full org links — the
`tasks` extension resolves them to clickable URLs via
`#+ISSUE_URL_BASE`.

```org
* TODO Refactor stim driver
:PROPERTIES:
:ID: 01234567-…
:LINKED_ISSUES: MBFW-123 MBE-45
:END:
```

`tasks` renders these as cyan badges and opens them with `J`. This
extension's planned `/jira *` commands enumerate `:LINKED_ISSUES:`,
filter to Jira-shaped tokens (matching `^[A-Z][A-Z0-9_]+-\d+$` for
bare tokens or matching `#+JIRA_BASE_URL` host for org-link tokens),
and operate only on those. Tokens belonging to other trackers (GitHub,
Linear, Confluence pages) are ignored, so a single task can carry
multi-tracker references without confusing the Jira workflow.

## Configuration

Three optional `#+` keywords in `TASKS.org` (or override in
`TASKS.local.org`):

```org
#+JIRA_CLOUDID: 00000000-0000-4000-8000-000000000000
#+JIRA_PROJECT: MBFW
#+JIRA_BASE_URL: https://your-org.atlassian.net
```

| Keyword            | Purpose                                                       |
| ------------------ | ------------------------------------------------------------- |
| `#+JIRA_CLOUDID`   | Skip the `atlassian_getAccessibleAtlassianResources` round-trip on every call. |
| `#+JIRA_PROJECT`   | Default project for `/jira create`; disambiguates short keys. |
| `#+JIRA_BASE_URL`  | Identifies which `:LINKED_ISSUES:` org-link tokens are Jira links. |

When `#+JIRA_CLOUDID` is absent, the agent calls
`atlassian_getAccessibleAtlassianResources` and picks the resource whose
URL matches `#+JIRA_BASE_URL`.

## Skill

`agents/skills/org-jira/SKILL.md` (extending `org-tasks`) documents the
authoring conventions and agent prompts. Load it when the user wants to
work with Jira-shaped tasks.

## Tests

```sh
./test.sh
```

Structural sanity check only. The workflow commands (when implemented)
will use `SAND` as their sandbox project for live smoke tests.
