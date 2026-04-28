# Jira Extension

Agent-driven Jira workflows backed by the [Atlassian
MCP](https://developer.atlassian.com/) server. Owns slash commands, MCP
routing, and Jira-specific authoring conventions; stays composable on top
of the generic `tasks` extension's tracker-agnostic linkage features
(`:LINKED_ISSUES:` drawer property + `#+ISSUE_URL_BASE` keyword).

## Status

**Scaffold.** Connection-status command implemented; clone / claim /
comment / create / transition workflows land in subsequent plan tasks
(see `design/log/2026-04-28-jira-integration.org`).

## Commands

| Command          | Status      | Description                                            |
| ---------------- | ----------- | ------------------------------------------------------ |
| `/jira`          | Implemented | Print Atlassian MCP connection status.                 |
| `/jira status`   | Implemented | Alias for `/jira`.                                     |
| `/jira clone`    | Planned     | Pull an issue from Jira → create a task locally.       |
| `/jira claim`    | Planned     | Set assignee on every Jira-shaped issue on a task.     |
| `/jira comment`  | Planned     | Add a comment to every Jira-shaped issue on a task.    |
| `/jira create`   | Planned     | Promote a task to a new Jira issue and link it back.   |

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
