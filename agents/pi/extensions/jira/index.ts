/**
 * Jira Extension for pi — agent-driven workflows against the Atlassian MCP.
 *
 * Companion artefacts:
 * - `:LINKED_ISSUES:` drawer property + `#+ISSUE_URL_BASE` keyword are
 *   owned by the `tasks` extension (tracker-agnostic). This extension
 *   reads/writes those when interacting with Jira issues but does not
 *   define them.
 * - `agents/skills/org-jira/SKILL.md` documents the Jira-specific
 *   conventions (PROJ-NNN key shape, #+JIRA_* keywords, agent prompts).
 *
 * All Jira access is mediated by the agent via the existing `atlassian`
 * MCP server. This extension stays I/O-free for write paths; the slash
 * command drafts a structured prompt that the agent then dispatches to
 * MCP tools and TASKS-file edits.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { getExtensionName } from "../lib/pi-utils.ts";
import {
  buildClonePrompt,
  getFileKeyword,
  resolveKey,
  type JiraConfig,
} from "./utils.ts";

export { getFileKeyword, resolveKey } from "./utils.ts";

const EXT_NAME = getExtensionName(import.meta.url);

/** Prefix every tool the Atlassian MCP server registers shares. */
const ATLASSIAN_TOOL_PREFIX = "atlassian_";

/** File-name conventions matching the tasks extension. */
const TASKS_FILE = "TASKS.org";
const TASKS_LOCAL_FILE = "TASKS.local.org";

/**
 * Returns the list of currently configured Atlassian MCP tool names, or [].
 * Used as a cheap proxy for "is the MCP server connected?". When a user
 * has not run `/mcp reconnect atlassian` (or the server is down), no
 * `atlassian_*` tools are registered.
 */
function listAtlassianTools(pi: ExtensionAPI): string[] {
  try {
    return pi
      .getAllTools()
      .map((t) => t.name)
      .filter((name) => name.startsWith(ATLASSIAN_TOOL_PREFIX))
      .sort();
  } catch {
    return [];
  }
}

/**
 * Read Jira config from the project's TASKS.org, with TASKS.local.org
 * overriding any keyword present in both files (mirrors `#+SELECTED:`).
 */
async function loadJiraConfig(cwd: string): Promise<JiraConfig> {
  let shared = "";
  let local = "";
  try {
    shared = await readFile(join(cwd, TASKS_FILE), "utf-8");
  } catch {
    /* TASKS.org may not exist; fall through with empty config. */
  }
  try {
    local = await readFile(join(cwd, TASKS_LOCAL_FILE), "utf-8");
  } catch {
    /* TASKS.local.org is optional. */
  }

  const pick = (name: string): string | null => {
    const val = getFileKeyword(local, name);
    if (val !== null && val !== "") return val;
    const sharedVal = getFileKeyword(shared, name);
    if (sharedVal !== null && sharedVal !== "") return sharedVal;
    return null;
  };

  return {
    cloudId: pick("JIRA_CLOUDID"),
    project: pick("JIRA_PROJECT"),
    baseUrl: pick("JIRA_BASE_URL"),
  };
}

// `resolveKey`, `buildClonePrompt`, `getFileKeyword`, and the
// `JiraConfig` type live in `./utils.ts` so the test suite can import
// them without pulling in pi-tui via `../lib/pi-utils.ts`.

export default function (pi: ExtensionAPI) {
  pi.registerCommand("jira", {
    description:
      "Jira integration via the Atlassian MCP server (status, clone; more workflows coming)",
    handler: async (args, ctx) => {
      const trimmed = args.trim();
      const parts = trimmed.length === 0 ? [] : trimmed.split(/\s+/);
      const subcommand = (parts[0] ?? "status").toLowerCase();
      const rest = parts.slice(1);
      const tools = listAtlassianTools(pi);
      const isConnected = tools.length > 0;

      if (subcommand === "status") {
        if (!isConnected) {
          ctx.ui.notify(
            "Atlassian MCP: disconnected. Run /mcp reconnect atlassian to enable Jira workflows.",
            "warn",
          );
          return;
        }
        const sample = tools.slice(0, 3).join(", ");
        const more = tools.length > 3 ? `, +${tools.length - 3} more` : "";
        ctx.ui.notify(
          `Atlassian MCP: connected (${tools.length} tools available — ${sample}${more}).`,
          "info",
        );
        return;
      }

      if (subcommand === "clone") {
        if (rest.length === 0) {
          ctx.ui.notify(
            "Usage: /jira clone KEY [KEY...]   (KEY = PROJ-NNN or a bare number when #+JIRA_PROJECT is set)",
            "warn",
          );
          return;
        }
        if (!isConnected) {
          ctx.ui.notify(
            "Atlassian MCP: disconnected. Run /mcp reconnect atlassian first.",
            "warn",
          );
          return;
        }

        const cfg = await loadJiraConfig(ctx.cwd);
        const resolved: string[] = [];
        const errors: string[] = [];
        for (const arg of rest) {
          const r = resolveKey(arg, cfg.project);
          if ("key" in r) resolved.push(r.key);
          else errors.push(r.error);
        }
        if (errors.length > 0) {
          for (const e of errors) ctx.ui.notify(e, "error");
          return;
        }

        const prompt = buildClonePrompt(
          resolved,
          cfg,
          ctx.cwd,
          TASKS_FILE,
          TASKS_LOCAL_FILE,
        );
        pi.sendUserMessage(prompt);
        ctx.ui.notify(
          `Dispatched /jira clone for ${resolved.length} issue${resolved.length === 1 ? "" : "s"}: ${resolved.join(", ")}.`,
          "info",
        );
        return;
      }

      ctx.ui.notify(
        `Unknown subcommand "${subcommand}". Available: status, clone. Planned: claim, comment, create.`,
        "warn",
      );
    },
  });

  // Hook for follow-up tasks: the keybindings extension can be advised
  // here that this extension exists, but no menu entries are contributed
  // until the workflow commands themselves land.
  void EXT_NAME;
}
