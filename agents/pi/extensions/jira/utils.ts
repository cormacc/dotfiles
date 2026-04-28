/**
 * Pure helpers for the jira extension. No external runtime imports so
 * the test runner can exercise them without pulling in `pi-tui` or other
 * packages that aren't installed in the test environment.
 */

/** Validation regex for bare Jira keys, e.g. `MBFW-123`. */
export const JIRA_KEY_RE = /^[A-Z][A-Z0-9_]+-\d+$/;
/** A bare integer (no project prefix) — resolves against `#+JIRA_PROJECT`. */
export const BARE_NUMBER_RE = /^\d+$/;

export interface JiraConfig {
  cloudId: string | null;
  project: string | null;
  baseUrl: string | null;
}

/**
 * Match a `#+KEYWORD:` line in raw org content.
 * Horizontal-whitespace only around the value so an empty line doesn't
 * bleed into the next line. Mirrors the helper of the same name in
 * `../tasks/parser.ts` — duplicated here to avoid a cross-extension
 * import cycle.
 */
export function getFileKeyword(
  content: string,
  name: string,
): string | null {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(
    `^[\\t ]*#\\+${escaped}[\\t ]*:[\\t ]*(.*?)[\\t ]*$`,
    "im",
  );
  const m = re.exec(content);
  return m?.[1] ?? null;
}

/**
 * Resolve a user-supplied key argument into a fully-qualified `PROJ-NNN`
 * key. Returns either `{ key }` on success or `{ error }` with a
 * human-readable message.
 */
export function resolveKey(
  arg: string,
  project: string | null,
): { key: string } | { error: string } {
  if (JIRA_KEY_RE.test(arg)) return { key: arg };
  if (BARE_NUMBER_RE.test(arg)) {
    if (!project) {
      return {
        error: `Bare number "${arg}" needs a project. Set #+JIRA_PROJECT in TASKS.org or pass the full key (e.g. SAND-${arg}).`,
      };
    }
    return { key: `${project}-${arg}` };
  }
  return {
    error: `"${arg}" is not a valid Jira key. Expected PROJ-NNN (e.g. SAND-42) or a bare number with #+JIRA_PROJECT set.`,
  };
}

/**
 * Compose the structured prompt that drives `/jira clone` end-to-end.
 *
 * Pure function — exported so tests can snapshot the prompt shape.
 */
export function buildClonePrompt(
  keys: string[],
  cfg: JiraConfig,
  cwd: string,
  tasksFile: string,
  tasksLocalFile: string,
): string {
  const cloudIdLine = cfg.cloudId
    ? `Use cloudId \`${cfg.cloudId}\` from #+JIRA_CLOUDID.`
    : "Resolve the cloudId by calling `atlassian_getAccessibleAtlassianResources`" +
      (cfg.baseUrl
        ? ` and selecting the resource whose \`url\` equals \`${cfg.baseUrl}\`.`
        : ".");
  const keyList = keys.map((k) => `\`${k}\``).join(", ");

  return [
    `Clone the following Jira issue${keys.length === 1 ? "" : "s"} into ${tasksFile} (or ${tasksLocalFile} if working in the local-drafts area): ${keyList}.`,
    "",
    "Use the **org-jira** skill for the full clone protocol; the steps below are a concise reminder, not a substitute.",
    "",
    "Steps for each key:",
    `1. ${cloudIdLine}`,
    "2. Call `atlassian_getJiraIssue` with the resolved cloudId and the issue key.",
    "3. Map the issue's priority name to an org priority:",
    "   - `Highest` → `[#A]`",
    "   - `High`    → `[#B]`",
    "   - `Medium`  → `[#C]`",
    "   - `Low`, `Lowest` → `[#D]`",
    "   - missing/unknown → no priority cookie",
    `4. Edit ${tasksFile} (preferred) or ${tasksLocalFile} (when the user is working on local drafts) to insert a new top-level task with:`,
    "   - heading: `** TODO [#X] <issue.fields.summary>` (TODO state; map priority per the table above; if the issue has labels you want to keep, append `:label1:label2:`).",
    "   - body: the issue description rendered as plain text (Jira ADF → markdown-ish; do not embed raw ADF JSON).",
    "   - properties drawer: `:ID: <new uuid>`, `:CREATED: <now via \\`date +\"%Y-%m-%d %a %H:%M\"\\`>`, `:LINKED_ISSUES: <KEY>`.",
    "5. Save the file. Do not invoke the tasks-extension UI; edit the org file directly.",
    "",
    `Project root: \`${cwd}\`.`,
    `Place new tasks under an existing semantic section (e.g. \`* Improvements\` or whichever section the user has been working in); do not create a new top-level section.`,
    "",
    "After cloning, summarise: one bullet per key with the new local task's heading and Jira URL.",
  ].join("\n");
}

/**
 * Helper used by all selected-task workflows (claim/comment/transition):
 * compose the cloudId-resolution preamble for the prompt.
 */
function cloudIdInstruction(cfg: JiraConfig): string {
  return cfg.cloudId
    ? `Use cloudId \`${cfg.cloudId}\` from #+JIRA_CLOUDID.`
    : "Resolve the cloudId by calling `atlassian_getAccessibleAtlassianResources`" +
        (cfg.baseUrl
          ? ` and selecting the resource whose \`url\` equals \`${cfg.baseUrl}\`.`
          : ".");
}

/**
 * Compose the prompt that drives `/jira claim` against the selected
 * task's Jira-shaped `:LINKED_ISSUES:` tokens.
 */
export function buildClaimPrompt(
  cfg: JiraConfig,
  cwd: string,
  tasksFile: string,
  tasksLocalFile: string,
  selectedId: string | null,
): string {
  const selectedLine = selectedId
    ? `The selected task's :ID: is \`${selectedId}\` (from #+SELECTED: in ${tasksLocalFile}).`
    : `Identify the selected task from #+SELECTED: in ${tasksLocalFile}; refuse with a notification if none is set.`;
  return [
    "Claim every Jira-shaped issue linked from the **selected task** by setting its assignee to the current Atlassian user.",
    "",
    "Use the **org-jira** skill for the full claim protocol; the steps below are a concise reminder, not a substitute.",
    "",
    `Project root: \`${cwd}\`.`,
    selectedLine,
    "",
    "Steps:",
    `1. ${cloudIdInstruction(cfg)}`,
    `2. Read the selected task's \`:LINKED_ISSUES:\` drawer property from ${tasksFile} or its imports. Filter to Jira-shaped tokens:`,
    "   - Bare tokens matching `^[A-Z][A-Z0-9_]+-\\d+$`.",
    cfg.baseUrl
      ? `   - Org-link tokens whose target host equals \`${new URL(cfg.baseUrl).host}\`.`
      : "   - Org-link tokens are skipped when #+JIRA_BASE_URL is unset.",
    "3. Call `atlassian_atlassianUserInfo` once to obtain the current user's `accountId`.",
    "4. For each Jira-shaped key, call `atlassian_editJiraIssue` with `assignee.accountId` set to that value.",
    "5. Surface a one-line summary per key with success or error message.",
    "",
    "Sandbox-only during development: only run against project `SAND` until the workflow is signed off.",
  ].join("\n");
}

/**
 * Compose the prompt that drives `/jira comment <markdown>` against the
 * selected task's Jira-shaped `:LINKED_ISSUES:` tokens.
 */
export function buildCommentPrompt(
  body: string,
  cfg: JiraConfig,
  cwd: string,
  tasksFile: string,
  tasksLocalFile: string,
  selectedId: string | null,
): string {
  const selectedLine = selectedId
    ? `The selected task's :ID: is \`${selectedId}\` (from #+SELECTED: in ${tasksLocalFile}).`
    : `Identify the selected task from #+SELECTED: in ${tasksLocalFile}; refuse with a notification if none is set.`;
  return [
    "Add a comment to every Jira-shaped issue linked from the **selected task**.",
    "",
    "Use the **org-jira** skill for the full comment protocol; the steps below are a concise reminder, not a substitute.",
    "",
    `Project root: \`${cwd}\`.`,
    selectedLine,
    "",
    "Comment body (verbatim, in fenced markdown):",
    "```markdown",
    body,
    "```",
    "",
    "Steps:",
    `1. ${cloudIdInstruction(cfg)}`,
    `2. Read the selected task's \`:LINKED_ISSUES:\` drawer property from ${tasksFile} or its imports. Filter to Jira-shaped tokens (see the org-jira skill).`,
    "3. For each Jira-shaped key, call `atlassian_addCommentToJiraIssue` with the markdown body above. The MCP server handles markdown → ADF conversion.",
    "4. Surface a one-line summary per key with success or error message.",
    "",
    "Sandbox-only during development: only run against project `SAND` until the workflow is signed off.",
  ].join("\n");
}

export interface CreateOptions {
  /** Project key arg passed on the command line. Falls back to cfg.project. */
  project: string | null;
  /** Issue type override (e.g. `Story`, `Bug`). Defaults to `Task`. */
  type: string;
}

/**
 * Compose the prompt that drives `/jira create` — promote the selected
 * task to a new Jira issue and write the new key back to
 * `:LINKED_ISSUES:`.
 */
export function buildCreatePrompt(
  opts: CreateOptions,
  cfg: JiraConfig,
  cwd: string,
  tasksFile: string,
  tasksLocalFile: string,
  selectedId: string | null,
): string {
  const project = opts.project ?? cfg.project;
  if (!project) {
    return [
      "Refuse the /jira create request: no project given on the command line and #+JIRA_PROJECT is not set in TASKS.org.",
      "Notify the user to either pass a PROJECT argument or set #+JIRA_PROJECT.",
    ].join("\n");
  }
  const selectedLine = selectedId
    ? `The selected task's :ID: is \`${selectedId}\` (from #+SELECTED: in ${tasksLocalFile}).`
    : `Identify the selected task from #+SELECTED: in ${tasksLocalFile}; refuse with a notification if none is set.`;
  return [
    `Promote the **selected task** to a new Jira issue in project \`${project}\` (issue type \`${opts.type}\`).`,
    "",
    "Use the **org-jira** skill for the full create protocol; the steps below are a concise reminder, not a substitute.",
    "",
    `Project root: \`${cwd}\`.`,
    selectedLine,
    "",
    "Steps:",
    `1. ${cloudIdInstruction(cfg)}`,
    `2. Verify the issue type \`${opts.type}\` exists in project \`${project}\` via \`atlassian_getJiraProjectIssueTypesMetadata\`. If not, surface the available types and stop.`,
    `3. Read the selected task's heading and body from ${tasksFile} (or its imports). The heading becomes the issue \`summary\`; the body becomes the issue \`description\` (markdown → ADF; the MCP server handles conversion).`,
    `4. Call \`atlassian_createJiraIssue\` with project \`${project}\`, issue type \`${opts.type}\`, summary, and description.`,
    "5. On success, append the returned key to the selected task's `:LINKED_ISSUES:` drawer property (whitespace-separated; preserve any existing tokens).",
    "6. Save the file. Confirm by surfacing the new key and Jira URL.",
    "",
    "Sandbox-only during development: only run against project `SAND` until the workflow is signed off.",
  ].join("\n");
}

/**
 * Compose the prompt that drives auto-transition on a task's
 * `tasks:status-changed` event.
 *
 * Pure function so it can be tested without a live event.
 */
export function buildTransitionPrompt(
  newStatus: "STARTED" | "DONE",
  taskId: string,
  taskSummary: string,
  cfg: JiraConfig,
  cwd: string,
  tasksFile: string,
  tasksLocalFile: string,
): string {
  const cloudIdLine = cfg.cloudId
    ? `Use cloudId \`${cfg.cloudId}\` from #+JIRA_CLOUDID.`
    : "Resolve the cloudId by calling `atlassian_getAccessibleAtlassianResources`" +
        (cfg.baseUrl
          ? ` and selecting the resource whose \`url\` equals \`${cfg.baseUrl}\`.`
          : ".");
  const targets =
    newStatus === "STARTED"
      ? ["Start Progress", "In Progress"]
      : ["Done", "Closed", "Resolved"];
  return [
    `Auto-transition: the local task \`${taskSummary}\` (:ID: \`${taskId}\`) just moved to \`${newStatus}\`. Mirror this on every Jira-shaped issue linked from the task's \`:LINKED_ISSUES:\`.`,
    "",
    "Use the **org-jira** skill for the full transition protocol; the steps below are a concise reminder.",
    "",
    `Project root: \`${cwd}\`.`,
    `Look up the task in ${tasksFile} (or its imports). Selected-task UUID is \`${taskId}\`.`,
    "",
    "Steps for each Jira-shaped key:",
    `1. ${cloudIdLine}`,
    `2. Call \`atlassian_getTransitionsForJiraIssue\` for the key.`,
    `3. Pick the first transition whose name matches one of (case-insensitive): ${targets.map((t) => `\`${t}\``).join(", ")}.`,
    "4. If no name matches, surface a chooser to the user instead of guessing.",
    "5. Call `atlassian_transitionJiraIssue` with the picked transition id.",
    "6. Surface a one-line summary per key with success or fall-back chooser.",
    "",
    "Sandbox-only during development: only run against project `SAND` until the workflow is signed off.",
  ].join("\n");
}

/**
 * Parse the `/jira create` argument string into project + type.
 * Accepts either positional or `--type` form:
 *   /jira create               → { project: null, type: "Task" }
 *   /jira create SAND          → { project: "SAND", type: "Task" }
 *   /jira create --type Story  → { project: null, type: "Story" }
 *   /jira create SAND --type Bug → { project: "SAND", type: "Bug" }
 */
export function parseCreateArgs(parts: string[]): CreateOptions {
  let project: string | null = null;
  let type = "Task";
  for (let i = 0; i < parts.length; i++) {
    const arg = parts[i]!;
    if (arg === "--type") {
      const next = parts[i + 1];
      if (next) {
        type = next;
        i++;
      }
      continue;
    }
    if (arg.startsWith("--type=")) {
      type = arg.slice("--type=".length);
      continue;
    }
    if (arg.startsWith("-")) continue; // ignore unknown flags for now
    if (project === null) project = arg;
  }
  return { project, type };
}
