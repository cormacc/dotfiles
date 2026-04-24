/**
 * Tasks Extension — track project tasks using org-mode TODO syntax.
 *
 * Reads TASKS.org from the project root and displays tasks in a tree overlay.
 *
 * Commands:
 *   /tasks — open the tasks overlay
 *
 * Keybindings (via the keybindings extension):
 *   <leader> t t — open the tasks overlay
 *
 * Persistent UI:
 *   When a task is marked :selected: in TASKS.org, a non-capturing overlay is
 *   pinned to the top of the terminal viewport and shows that task plus its
 *   subtasks. It is refreshed on startup and immediately as the /tasks overlay
 *   mutates task status/selection.
 */

import type {
  ExtensionAPI,
  ExtensionContext,
  Theme,
} from "@mariozechner/pi-coding-agent";
import {
  truncateToWidth,
  type Component,
  type OverlayHandle,
  type TUI,
} from "@mariozechner/pi-tui";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { getExtensionName, suggestKeybindings } from "../lib/pi-utils.ts";
import { TasksOverlay } from "./overlay.ts";
import { parseTasks, type Task } from "./parser.ts";
import { colorStatus } from "./status-colors.ts";

const EXT_NAME = getExtensionName(import.meta.url);
const TASKS_FILE = "TASKS.org";
const SELECTED_TAG = "selected";
/** Hard cap so the pinned overlay never dominates the screen. */
const MAX_PINNED_LINES = 12;

/** Cleanup handle for keybinding suggestions. */
let cleanupKb: (() => void) | null = null;

/** Persistent top-pinned overlay state. */
let pinnedOverlayHandle: OverlayHandle | null = null;
let pinnedOverlayComponent: PinnedTasksOverlay | null = null;
let pinnedOverlayTui: TUI | null = null;

async function loadTasks(cwd: string): Promise<Task[]> {
  try {
    const content = await readFile(join(cwd, TASKS_FILE), "utf-8");
    return parseTasks(content);
  } catch {
    return [];
  }
}

function findSelectedTask(tasks: Task[]): Task | null {
  for (const t of tasks) {
    if (t.tags.includes(SELECTED_TAG)) return t;
    const child = findSelectedTask(t.children);
    if (child) return child;
  }
  return null;
}

function countAll(tasks: Task[]): number {
  let n = 0;
  for (const t of tasks) {
    n++;
    n += countAll(t.children);
  }
  return n;
}

function formatTaskLine(t: Task, indent: string, isHead: boolean): string {
  const prio = t.priority ? `[#${t.priority}] ` : "";
  const visibleTags = t.tags.filter((tg) => tg !== SELECTED_TAG);
  const tags = visibleTags.length > 0 ? ` :${visibleTags.join(":")}:` : "";
  const marker = isHead ? "★ " : "• ";
  return `${indent}${marker}${colorStatus(t.status)} ${prio}${t.summary}${tags}`;
}

/** Build the pinned overlay's pre-styled lines, or undefined if nothing is selected. */
function buildPinnedLines(tasks: Task[], theme: Theme): string[] | undefined {
  const selected = findSelectedTask(tasks);
  if (!selected) return undefined;

  const lines: string[] = [];
  lines.push(theme.fg("accent", theme.bold("── Selected task ──")));
  lines.push(formatTaskLine(selected, "", true));

  const walk = (children: Task[], depth: number) => {
    for (const c of children) {
      if (lines.length >= MAX_PINNED_LINES) return;
      lines.push(formatTaskLine(c, "  ".repeat(depth), false));
      walk(c.children, depth + 1);
      if (lines.length >= MAX_PINNED_LINES) return;
    }
  };
  walk(selected.children, 1);

  const total = countAll(selected.children);
  const shown = lines.length - 2; // minus header rule + selected-task line
  if (shown < total) {
    const more = theme.fg("dim", `  … ${total - shown} more subtask(s)`);
    if (lines.length >= MAX_PINNED_LINES) {
      lines[MAX_PINNED_LINES - 1] = more;
    } else {
      lines.push(more);
    }
  }

  return lines;
}

class PinnedTasksOverlay implements Component {
  constructor(
    private tasks: Task[],
    private readonly theme: Theme,
  ) {}

  setTasks(tasks: Task[]): void {
    this.tasks = tasks;
  }

  render(width: number): string[] {
    const lines = buildPinnedLines(this.tasks, this.theme) ?? [];
    return lines.map((l) => truncateToWidth(l, width));
  }

  invalidate(): void {}
}

function clearPinnedOverlay(): void {
  pinnedOverlayHandle?.hide();
  pinnedOverlayHandle = null;
  pinnedOverlayComponent = null;
  pinnedOverlayTui = null;
}

/**
 * Sync the persistent top-pinned selection overlay with a task tree.
 *
 * This intentionally uses a non-capturing overlay instead of ctx.ui.setHeader().
 * pi renders the header as part of the scrollback buffer, so it scrolls out of
 * the visible viewport in active sessions. An overlay is composited against the
 * current terminal viewport and can therefore stay pinned to row 0.
 *
 * If `createWhenUnselected` is true, a hidden overlay is created even with no
 * current selection. The /tasks command uses that before opening its modal
 * overlay so a later `s` key can reveal/update the pinned overlay immediately
 * without adding a newer overlay above the modal (which would confuse pi's
 * topmost-overlay close behavior).
 */
async function syncPinnedOverlay(
  ctx: ExtensionContext,
  tasks: Task[],
  createWhenUnselected = false,
): Promise<void> {
  if (!ctx.hasUI) return;

  const hasSelectedTask = findSelectedTask(tasks) !== null;
  if (!hasSelectedTask && !createWhenUnselected && !pinnedOverlayHandle) {
    return;
  }

  if (pinnedOverlayComponent && pinnedOverlayHandle) {
    pinnedOverlayComponent.setTasks(tasks);
    pinnedOverlayHandle.setHidden(!hasSelectedTask);
    pinnedOverlayTui?.requestRender();
    return;
  }

  if (!hasSelectedTask && !createWhenUnselected) return;

  await new Promise<void>((resolve) => {
    let resolved = false;
    const finish = () => {
      if (!resolved) {
        resolved = true;
        resolve();
      }
    };

    void ctx.ui
      .custom<undefined>(
        (tui, theme) => {
          pinnedOverlayTui = tui;
          pinnedOverlayComponent = new PinnedTasksOverlay(tasks, theme);
          return pinnedOverlayComponent;
        },
        {
          overlay: true,
          overlayOptions: {
            anchor: "top-center",
            width: "100%",
            maxHeight: MAX_PINNED_LINES,
            margin: 0,
            offsetY: 0,
            nonCapturing: true,
          },
          onHandle: (handle) => {
            pinnedOverlayHandle = handle;
            pinnedOverlayHandle.setHidden(!hasSelectedTask);
            finish();
          },
        },
      )
      .catch(() => {
        clearPinnedOverlay();
        finish();
      });
  });
}

async function refreshPinnedOverlay(
  ctx: ExtensionContext,
  cwd: string,
): Promise<void> {
  await syncPinnedOverlay(ctx, await loadTasks(cwd));
}

export default function (pi: ExtensionAPI) {
  // ── Keybinding suggestions + startup pinned overlay restore ─────────

  pi.on("session_start", async (_ev, ctx) => {
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

    await refreshPinnedOverlay(ctx, ctx.cwd);
  });

  pi.on("session_shutdown", async () => {
    cleanupKb?.();
    cleanupKb = null;
    clearPinnedOverlay();
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

      // Ensure the pinned overlay exists before the modal /tasks overlay is
      // pushed. That lets status/selection changes update it immediately while
      // keeping it below the modal in pi's overlay stack.
      await syncPinnedOverlay(ctx, tasks, true);

      const onEdit = (lineNumber: number) => {
        const filePath = join(ctx.cwd, TASKS_FILE);
        pi.events.emit("emacs:open", { file: filePath, line: lineNumber });
      };

      const onTasksChanged = (updatedTasks: Task[]) => {
        void syncPinnedOverlay(ctx, updatedTasks, false);
      };

      await ctx.ui.custom<undefined>(
        (_tui, theme, _kb, done) =>
          new TasksOverlay(
            tasks,
            ctx.cwd,
            theme,
            done,
            onEdit,
            onTasksChanged,
          ),
        {
          overlay: true,
          overlayOptions: {
            width: "90%",
            minWidth: 80,
            anchor: "center",
          },
        },
      );

      // Re-read from disk after close to converge with the saved file state.
      await refreshPinnedOverlay(ctx, ctx.cwd);
    },
  });
}
