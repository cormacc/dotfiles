/**
 * Babashka Tasks Extension
 *
 * Detects `bb.edn` in the project root and registers a `/bb` slash command
 * with auto-completion for available babashka tasks.
 *
 * - Regular tasks run in the default pi-shell (via the `bash` tool).
 * - Tasks whose name starts with "watch" run in a dedicated process tab
 *   when the term-mirror extension is available (via `start_process`).
 */
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import type { AutocompleteItem } from "@mariozechner/pi-tui";
import { existsSync } from "node:fs";
import { join } from "node:path";

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => {
    const bbEdn = join(ctx.cwd, "bb.edn");
    if (!existsSync(bbEdn)) return;

    // ── parse available tasks from `bb tasks` ────────────

    let tasks: { name: string; description: string }[] = [];

    async function refreshTasks(): Promise<void> {
      try {
        const r = await pi.exec("bb", ["tasks"], { timeout: 10000 });
        if (r.code !== 0) return;

        // `bb tasks` outputs lines like:
        //   clean    Remove build artifacts
        //   watch    Start file watcher
        tasks = [];
        for (const line of r.stdout.split("\n")) {
          const match = line.match(/^(\S+)\s+(.*)/);
          if (match) {
            tasks.push({ name: match[1], description: match[2].trim() });
          }
        }
      } catch {}
    }

    await refreshTasks();

    if (tasks.length === 0) {
      ctx.ui.notify("bb-tasks: no tasks found in bb.edn", "warning");
      return;
    }

    ctx.ui.notify(`bb-tasks: ${tasks.length} tasks available`, "info");

    // ── detect term-mirror availability ──────────────────

    function hasTermMirror(): boolean {
      const allTools = pi.getAllTools();
      return allTools.some((t) => t.name === "start_process");
    }

    // ── register /bb command ─────────────────────────────

    pi.registerCommand("bb", {
      description: "Run a babashka task",

      getArgumentCompletions(prefix: string): AutocompleteItem[] | null {
        const items = tasks.map((t) => ({
          value: t.name,
          label: t.name,
          description: t.description || undefined,
        }));
        if (!prefix) return items.length > 0 ? items : null;
        const filtered = items.filter((i) =>
          i.value.toLowerCase().startsWith(prefix.toLowerCase()),
        );
        return filtered.length > 0 ? filtered : null;
      },

      handler: async (args, ctx) => {
        const taskName = args?.trim();
        if (!taskName) {
          // No argument — list tasks
          const listing = tasks
            .map((t) => `  ${t.name}  ${t.description}`)
            .join("\n");
          ctx.ui.notify(`Available tasks:\n${listing}`, "info");
          return;
        }

        const task = tasks.find((t) => t.name === taskName);
        if (!task) {
          ctx.ui.notify(`Unknown task: ${taskName}`, "error");
          return;
        }

        const isWatch = taskName.startsWith("watch");

        if (isWatch && hasTermMirror()) {
          // Run in a process tab via sendUserMessage so the agent
          // calls start_process with the right parameters.
          pi.sendUserMessage(
            `Run \`bb ${taskName}\` as a long-running watch process using start_process with name "${taskName}" and mode "watch".`,
            { deliverAs: "followUp" },
          );
        } else {
          // Run in the default shell
          pi.sendUserMessage(`Run \`bb ${taskName}\` in the terminal.`, {
            deliverAs: "followUp",
          });
        }
      },
    });
  });
}
