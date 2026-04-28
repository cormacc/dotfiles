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
import { existsSync, readFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { getExtensionName } from "../lib/pi-utils.ts";
import {
  buildClaimPrompt,
  buildClonePrompt,
  buildCommentPrompt,
  buildCreatePrompt,
  buildTransitionPrompt,
  getFileKeyword,
  parseCreateArgs,
  resolveKey,
  type JiraConfig,
} from "./utils.ts";

export { getFileKeyword, resolveKey } from "./utils.ts";

/** User-overridable settings file. */
const USER_SETTINGS_PATH = join(homedir(), ".pi", "agent", "jira-ext.json");

interface UserSettings {
  /** Mirror local TODO→STARTED→DONE on linked Jira issues. Default: false. */
  autoTransition: boolean;
}

function loadUserSettings(): UserSettings {
  const defaults: UserSettings = { autoTransition: false };
  try {
    if (!existsSync(USER_SETTINGS_PATH)) return defaults;
    const raw = readFileSync(USER_SETTINGS_PATH, "utf-8");
    const parsed = JSON.parse(raw) as Partial<UserSettings>;
    return {
      autoTransition:
        typeof parsed.autoTransition === "boolean"
          ? parsed.autoTransition
          : defaults.autoTransition,
    };
  } catch {
    return defaults;
  }
}

const EXT_NAME = getExtensionName(import.meta.url);

/** Prefix every tool the Atlassian MCP server registers shares (direct-tools mode). */
const ATLASSIAN_TOOL_PREFIX = "atlassian_";
/** Name of the unified MCP proxy tool (default pi-mcp-adapter mode). */
const MCP_PROXY_TOOL = "mcp";

/** File-name conventions matching the tasks extension. */
const TASKS_FILE = "TASKS.org";
const TASKS_LOCAL_FILE = "TASKS.local.org";

/**
 * Inspect the Atlassian MCP availability surface.
 *
 * pi-mcp-adapter operates in two modes:
 *   - direct-tools: each MCP tool is registered with pi (e.g. `atlassian_*`).
 *   - proxy (default): a single unified `mcp` tool is registered and the
 *     agent invokes underlying tools through it.
 *
 * We treat MCP as "available" if we see either direct `atlassian_*` tools
 * or the `mcp` proxy. The proxy alone doesn't *prove* the atlassian server
 * is configured, but it's a much better signal than the previous check
 * (which always reported disconnected under the default proxy mode).
 */
function getAtlassianAvailability(pi: ExtensionAPI): {
  direct: string[];
  proxy: boolean;
  isAvailable: boolean;
} {
  try {
    const names = pi.getAllTools().map((t) => t.name);
    const direct = names
      .filter((name) => name.startsWith(ATLASSIAN_TOOL_PREFIX))
      .sort();
    const proxy = names.includes(MCP_PROXY_TOOL);
    return { direct, proxy, isAvailable: direct.length > 0 || proxy };
  } catch {
    return { direct: [], proxy: false, isAvailable: false };
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

/**
 * Read `#+SELECTED:` from TASKS.local.org. Returns null when the file
 * is absent, the keyword is missing, or the value is empty.
 */
async function readSelectedId(cwd: string): Promise<string | null> {
  try {
    const content = await readFile(join(cwd, TASKS_LOCAL_FILE), "utf-8");
    const value = getFileKeyword(content, "SELECTED");
    return value && value.length > 0 ? value : null;
  } catch {
    return null;
  }
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("jira", {
    description:
      "Jira integration via the Atlassian MCP server (status, clone; more workflows coming)",
    handler: async (args, ctx) => {
      const trimmed = args.trim();
      const parts = trimmed.length === 0 ? [] : trimmed.split(/\s+/);
      const subcommand = (parts[0] ?? "status").toLowerCase();
      const rest = parts.slice(1);
      const availability = getAtlassianAvailability(pi);
      const isConnected = availability.isAvailable;

      if (subcommand === "status") {
        if (!isConnected) {
          ctx.ui.notify(
            "Atlassian MCP: disconnected. Run /mcp reconnect atlassian to enable Jira workflows.",
            "warn",
          );
          return;
        }
        if (availability.direct.length > 0) {
          const sample = availability.direct.slice(0, 3).join(", ");
          const more =
            availability.direct.length > 3
              ? `, +${availability.direct.length - 3} more`
              : "";
          ctx.ui.notify(
            `Atlassian MCP: connected via direct tools (${availability.direct.length} — ${sample}${more}).`,
            "info",
          );
        } else {
          ctx.ui.notify(
            "Atlassian MCP: connected via proxy tool (`mcp`). Run `/mcp` to inspect server status.",
            "info",
          );
        }
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

      if (subcommand === "claim") {
        if (!isConnected) {
          ctx.ui.notify(
            "Atlassian MCP: disconnected. Run /mcp reconnect atlassian first.",
            "warn",
          );
          return;
        }
        const cfg = await loadJiraConfig(ctx.cwd);
        const selectedId = await readSelectedId(ctx.cwd);
        if (!selectedId) {
          ctx.ui.notify(
            "No selected task. Press `s` on a task in /tasks first, or set #+SELECTED: in TASKS.local.org.",
            "warn",
          );
          return;
        }
        const prompt = buildClaimPrompt(
          cfg,
          ctx.cwd,
          TASKS_FILE,
          TASKS_LOCAL_FILE,
          selectedId,
        );
        pi.sendUserMessage(prompt);
        ctx.ui.notify(
          `Dispatched /jira claim for the selected task.`,
          "info",
        );
        return;
      }

      if (subcommand === "comment") {
        if (!isConnected) {
          ctx.ui.notify(
            "Atlassian MCP: disconnected. Run /mcp reconnect atlassian first.",
            "warn",
          );
          return;
        }
        const body = rest.join(" ").trim();
        if (!body) {
          ctx.ui.notify(
            "Usage: /jira comment <markdown body>   (operates on the selected task's :LINKED_ISSUES:)",
            "warn",
          );
          return;
        }
        const cfg = await loadJiraConfig(ctx.cwd);
        const selectedId = await readSelectedId(ctx.cwd);
        if (!selectedId) {
          ctx.ui.notify(
            "No selected task. Press `s` on a task in /tasks first, or set #+SELECTED: in TASKS.local.org.",
            "warn",
          );
          return;
        }
        const prompt = buildCommentPrompt(
          body,
          cfg,
          ctx.cwd,
          TASKS_FILE,
          TASKS_LOCAL_FILE,
          selectedId,
        );
        pi.sendUserMessage(prompt);
        ctx.ui.notify(
          `Dispatched /jira comment for the selected task.`,
          "info",
        );
        return;
      }

      if (subcommand === "create") {
        if (!isConnected) {
          ctx.ui.notify(
            "Atlassian MCP: disconnected. Run /mcp reconnect atlassian first.",
            "warn",
          );
          return;
        }
        const opts = parseCreateArgs(rest);
        const cfg = await loadJiraConfig(ctx.cwd);
        if (!opts.project && !cfg.project) {
          ctx.ui.notify(
            "Usage: /jira create [PROJECT] [--type Task|Story|Bug|Epic]   (or set #+JIRA_PROJECT in TASKS.org)",
            "warn",
          );
          return;
        }
        const selectedId = await readSelectedId(ctx.cwd);
        if (!selectedId) {
          ctx.ui.notify(
            "No selected task. Press `s` on a task in /tasks first, or set #+SELECTED: in TASKS.local.org.",
            "warn",
          );
          return;
        }
        const prompt = buildCreatePrompt(
          opts,
          cfg,
          ctx.cwd,
          TASKS_FILE,
          TASKS_LOCAL_FILE,
          selectedId,
        );
        pi.sendUserMessage(prompt);
        ctx.ui.notify(
          `Dispatched /jira create for project ${opts.project ?? cfg.project} (type ${opts.type}).`,
          "info",
        );
        return;
      }

      ctx.ui.notify(
        `Unknown subcommand "${subcommand}". Available: status, clone, claim, comment, create.`,
        "warn",
      );
    },
  });

  // ── Auto-transition ────────────────────────────────────────────────
  //
  // Listen for `tasks:status-changed` events from the `tasks` extension.
  // When the user toggles a task to STARTED or DONE and the
  // `autoTransition` setting is enabled, dispatch an agent prompt that
  // mirrors the change on every Jira-shaped issue linked from the task.
  //
  // Disabled by default — set `{ "autoTransition": true }` in
  // ~/.pi/agent/jira-ext.json to enable.

  pi.events.on(
    "tasks:status-changed",
    async (payload: {
      id: string | null;
      status: string;
      prevStatus: string;
      summary: string;
      closed: boolean;
    }) => {
      const settings = loadUserSettings();
      if (!settings.autoTransition) return;
      if (!payload || !payload.id) return;
      // Only mirror two transitions: TODO→STARTED and →DONE.
      const newStatus =
        payload.status === "STARTED"
          ? "STARTED"
          : payload.status === "DONE"
            ? "DONE"
            : null;
      if (!newStatus) return;
      // No-op when the MCP isn't connected; user surfaces a notification
      // via `/jira status` if they want to know.
      if (!getAtlassianAvailability(pi).isAvailable) return;

      // The `tasks` event payload doesn't include the cwd; fall back to
      // process.cwd() at the time of the event. The vast majority of pi
      // sessions run with a stable cwd, and cross-cwd auto-transition
      // would need a richer event.
      const proc = (globalThis as { [key: string]: unknown })["process"] as
        | { cwd?: () => string }
        | undefined;
      const cwd = proc?.cwd?.() ?? ".";
      const cfg = await loadJiraConfig(cwd);
      const prompt = buildTransitionPrompt(
        newStatus,
        payload.id,
        payload.summary,
        cfg,
        cwd,
        TASKS_FILE,
        TASKS_LOCAL_FILE,
      );
      pi.sendUserMessage(prompt);
    },
  );

  // Hook for follow-up tasks: the keybindings extension can be advised
  // here that this extension exists, but no menu entries are contributed
  // until the workflow commands themselves land.
  void EXT_NAME;
}
