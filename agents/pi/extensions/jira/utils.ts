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
