/**
 * Tasks Extension — track project tasks using org-mode TODO syntax.
 *
 * Reads TASKS.org from the project root and displays tasks in a tree overlay.
 *
 * Commands:
 *   /tasks  — open the tasks overlay
 *
 * Keybindings (via the keybindings extension):
 *   <leader> t t — open the tasks overlay
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { getExtensionName, suggestKeybindings } from "../lib/pi-utils.ts";
import { TasksOverlay } from "./overlay.ts";
import { parseTasks, type Task } from "./parser.ts";

const EXT_NAME = getExtensionName(import.meta.url);
const TASKS_FILE = "TASKS.org";

/** Cleanup handle for keybinding suggestions. */
let cleanupKb: (() => void) | null = null;

async function loadTasks(cwd: string): Promise<Task[]> {
  try {
    const content = await readFile(join(cwd, TASKS_FILE), "utf-8");
    return parseTasks(content);
  } catch {
    return [];
  }
}

export default function (pi: ExtensionAPI) {
  // ── Keybinding suggestions ──────────────────────────────────────────

  pi.on("session_start", async () => {
    cleanupKb = suggestKeybindings(pi, EXT_NAME, {
      menus: {
        tasks: {
          label: "Tasks",
          key: " ",
          items: {
            t: {
              label: "+tasks",
              items: {
                t: { label: "Show tasks", action: "command:/tasks" },
              },
            },
          },
        },
      },
    });
  });

  pi.on("session_shutdown", async () => {
    cleanupKb?.();
    cleanupKb = null;
  });

  // ── /tasks command ──────────────────────────────────────────────────

  pi.registerCommand("tasks", {
    description: "Show project tasks from TASKS.org",
    handler: async (_args, ctx) => {
      if (!ctx.hasUI) {
        ctx.ui.notify("/tasks requires interactive mode", "error");
        return;
      }

      const tasks = await loadTasks(ctx.cwd);

      const onEdit = (lineNumber: number) => {
        const filePath = join(ctx.cwd, TASKS_FILE);
        pi.events.emit("emacs:open", { file: filePath, line: lineNumber });
      };

      await ctx.ui.custom<undefined>(
        (_tui, theme, _kb, done) =>
          new TasksOverlay(tasks, ctx.cwd, theme, done, onEdit),
        {
          overlay: true,
          overlayOptions: {
            width: "90%",
            minWidth: 80,
            anchor: "center",
          },
        },
      );
    },
  });
}
