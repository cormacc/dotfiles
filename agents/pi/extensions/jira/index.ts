/**
 * Jira Extension for pi — agent-driven workflows against the Atlassian MCP.
 *
 * Status: scaffold. The full feature surface (clone / claim / comment /
 * create / transition) lands in subsequent tasks; this initial cut
 * establishes the extension shape and a `/jira` connection-status
 * command so other plan tasks have a place to attach.
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
 * MCP server. This extension stays I/O-free; slash-commands draft a
 * structured prompt that the agent then dispatches to MCP tools.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { getExtensionName } from "../lib/pi-utils.ts";

const EXT_NAME = getExtensionName(import.meta.url);

/** Prefix every tool the Atlassian MCP server registers shares. */
const ATLASSIAN_TOOL_PREFIX = "atlassian_";

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

export default function (pi: ExtensionAPI) {
  pi.registerCommand("jira", {
    description:
      "Jira integration via the Atlassian MCP server " +
      "(scaffold — clone/claim/comment/create land in follow-up tasks)",
    handler: async (args, ctx) => {
      const tools = listAtlassianTools(pi);
      const arg = args.trim().toLowerCase();

      if (arg === "" || arg === "status") {
        if (tools.length === 0) {
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

      // Unknown subcommand — surface the planned surface so users know
      // what's coming without guessing.
      ctx.ui.notify(
        `Unknown subcommand "${arg}". Planned: clone, claim, comment, create. ` +
          "Currently only /jira (status) is implemented.",
        "warn",
      );
    },
  });

  // Hook for follow-up tasks: the keybindings extension can be advised
  // here that this extension exists, but no menu entries are contributed
  // until the workflow commands themselves land.
  void EXT_NAME;
}
