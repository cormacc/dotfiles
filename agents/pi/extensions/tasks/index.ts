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
  visibleWidth,
  type Component,
  type OverlayHandle,
  type TUI,
} from "@mariozechner/pi-tui";
import { watch, type FSWatcher } from "node:fs";
import { readFile } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { getExtensionName, suggestKeybindings } from "../lib/pi-utils.ts";
import { TasksOverlay } from "./overlay.ts";
import { parseTasks, type Task } from "./parser.ts";
import { colorPriority, colorStatus, colorTags } from "./status-colors.ts";

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

/**
 * File-watcher state. The pinned overlay refreshes on external edits
 * (e.g. saving TASKS.org or a linked plan file in Emacs) without requiring
 * the /tasks modal to be reopened.
 */
const fileWatchers = new Map<string, FSWatcher>();
let watchDebounceTimer: ReturnType<typeof setTimeout> | null = null;
let activeCtx: ExtensionContext | null = null;

/** Collect every path whose changes should trigger a pinned-overlay refresh. */
function collectWatchPaths(tasks: Task[], cwd: string): Set<string> {
  const paths = new Set<string>();
  paths.add(join(cwd, TASKS_FILE));
  const walk = (ts: Task[]) => {
    for (const t of ts) {
      if (t.sourcePath) paths.add(t.sourcePath);
      walk(t.children);
      if (t.planChildren) walk(t.planChildren);
    }
  };
  walk(tasks);
  return paths;
}

function attachFileWatcher(path: string): void {
  if (fileWatchers.has(path)) return;
  try {
    const watcher = watch(path, (eventType) => {
      scheduleRefresh();
      // Editors that atomically rename-replace the file invalidate this
      // watcher after the first event. Close now and let the next refresh
      // re-attach against the new inode.
      if (eventType === "rename") {
        fileWatchers.get(path)?.close();
        fileWatchers.delete(path);
      }
    });
    watcher.on("error", () => {
      fileWatchers.delete(path);
    });
    fileWatchers.set(path, watcher);
  } catch {
    // File may not exist yet; next refresh will retry.
  }
}

function updateFileWatchers(paths: Set<string>): void {
  for (const [p, w] of fileWatchers) {
    if (!paths.has(p)) {
      w.close();
      fileWatchers.delete(p);
    }
  }
  for (const p of paths) attachFileWatcher(p);
}

function closeAllFileWatchers(): void {
  for (const w of fileWatchers.values()) w.close();
  fileWatchers.clear();
  if (watchDebounceTimer) {
    clearTimeout(watchDebounceTimer);
    watchDebounceTimer = null;
  }
}

function scheduleRefresh(): void {
  if (!activeCtx) return;
  if (watchDebounceTimer) clearTimeout(watchDebounceTimer);
  watchDebounceTimer = setTimeout(() => {
    watchDebounceTimer = null;
    const ctx = activeCtx;
    if (ctx) void refreshPinnedOverlay(ctx, ctx.cwd);
  }, 150);
}

async function loadTasks(cwd: string): Promise<Task[]> {
  const sourcePath = join(cwd, TASKS_FILE);
  try {
    const content = await readFile(sourcePath, "utf-8");
    const tasks = parseTasks(content, { sourcePath });
    await loadLinkedPlans(tasks, sourcePath);
    return tasks;
  } catch {
    return [];
  }
}

async function loadLinkedPlans(
  tasks: Task[],
  sourcePath: string,
  cache = new Map<string, Task[]>(),
): Promise<void> {
  const sourceDir = dirname(sourcePath);
  for (const task of tasks) {
    if (task.planPath) {
      const planPath = isAbsolute(task.planPath)
        ? task.planPath
        : resolve(sourceDir, task.planPath);
      const cached = cache.get(planPath);
      if (cached) {
        task.planChildren = cached;
      } else {
        try {
          const content = await readFile(planPath, "utf-8");
          const planTasks = parseTasks(content, { sourcePath: planPath });
          cache.set(planPath, planTasks);
          await loadLinkedPlans(planTasks, planPath, cache);
          task.planChildren = planTasks;
        } catch {
          task.planChildren = [];
          cache.set(planPath, task.planChildren);
        }
      }
    }
    await loadLinkedPlans(task.children, sourcePath, cache);
  }
}

function taskChildren(task: Task): Task[] {
  return [...task.children, ...(task.planChildren ?? [])];
}

function findSelectedTask(tasks: Task[]): Task | null {
  for (const t of tasks) {
    if (t.tags.includes(SELECTED_TAG)) return t;
    const child = findSelectedTask(taskChildren(t));
    if (child) return child;
  }
  return null;
}

function formatTaskLine(
  t: Task,
  indent: string,
  isHead: boolean,
  width: number,
): string {
  const priority = colorPriority(t.priority);
  const visibleTags = t.tags.filter((tg) => tg !== SELECTED_TAG);
  const tags = colorTags(visibleTags);
  const marker = isHead ? "★ " : "• ";
  const left = `${indent}${marker}${colorStatus(t.status)} ${priority ? `${priority} ` : ""}${t.summary}`;
  if (!tags) return truncateToWidth(left, width);

  const tagText = ` ${tags}`;
  const tagWidth = visibleWidth(tagText);
  const leftWidth = Math.max(0, width - tagWidth - 1);
  const clippedLeft = truncateToWidth(left, leftWidth);
  const gap = Math.max(1, width - visibleWidth(clippedLeft) - tagWidth);
  return truncateToWidth(`${clippedLeft}${" ".repeat(gap)}${tagText}`, width);
}

function border(width: number, theme: Theme, fill = "─"): string {
  return theme.fg("border", fill.repeat(Math.max(0, width)));
}

function centeredBorder(label: string, width: number, theme: Theme): string {
  const text = ` ${label} `;
  const remaining = Math.max(0, width - visibleWidth(text));
  const left = Math.floor(remaining / 2);
  const right = remaining - left;
  return theme.fg(
    "borderMuted",
    `${"─".repeat(left)}${text}${"─".repeat(right)}`,
  );
}

/** Build the pinned overlay's pre-styled lines, or undefined if nothing is selected. */
function buildPinnedLines(
  tasks: Task[],
  theme: Theme,
  width: number,
): string[] | undefined {
  const selected = findSelectedTask(tasks);
  if (!selected) return undefined;

  const hasLinkedPlan = !!selected.planPath && (selected.planChildren?.length ?? 0) > 0;
  const headerLines = [
    theme.fg("accent", theme.bold("── Selected task ──")),
    formatTaskLine(selected, "", true, width),
  ];
  if (hasLinkedPlan) {
    headerLines.push(centeredBorder(basename(selected.planPath!), width, theme));
  }
  const maxSubtaskLines = Math.max(
    0,
    MAX_PINNED_LINES - headerLines.length - 1,
  );

  const flattened: { task: Task; depth: number }[] = [];
  const walk = (children: Task[], depth: number) => {
    for (const child of children) {
      flattened.push({ task: child, depth });
      walk(taskChildren(child), depth + 1);
    }
  };
  walk(taskChildren(selected), 1);

  const visible = [...flattened];
  let hiddenCompleted = 0;

  // If truncation is needed, reclaim space from completed subtasks first,
  // scanning from the head so the pinned view favours the selected task's
  // next pending work over old completed history.
  while (
    visible.length + (hiddenCompleted > 0 ? 1 : 0) > maxSubtaskLines
  ) {
    const doneIdx = visible.findIndex((row) => row.task.status === "DONE");
    if (doneIdx === -1) break;
    visible.splice(doneIdx, 1);
    hiddenCompleted++;
  }

  let hiddenMore = 0;
  const completedSummaryLines = hiddenCompleted > 0 ? 1 : 0;
  if (visible.length + completedSummaryLines > maxSubtaskLines) {
    const maxVisibleTasks = Math.max(0, maxSubtaskLines - completedSummaryLines - 1);
    hiddenMore = visible.length - maxVisibleTasks;
    visible.splice(maxVisibleTasks);
  }

  const lines = [...headerLines];
  if (hiddenCompleted > 0) {
    const label = hiddenCompleted === 1 ? "subtask" : "subtasks";
    lines.push(
      theme.fg("dim", `  … ${hiddenCompleted} completed ${label}`),
    );
  }

  for (const row of visible) {
    lines.push(formatTaskLine(row.task, "  ".repeat(row.depth), false, width));
  }

  if (hiddenMore > 0) {
    const label = hiddenMore === 1 ? "subtask" : "subtasks";
    lines.push(theme.fg("dim", `  … ${hiddenMore} more ${label}`));
  }

  lines.push(border(width, theme));

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
    const lines = buildPinnedLines(this.tasks, this.theme, width) ?? [];
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
            maxHeight: MAX_PINNED_LINES + 2,
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
  activeCtx = ctx;
  const tasks = await loadTasks(cwd);
  await syncPinnedOverlay(ctx, tasks);
  updateFileWatchers(collectWatchPaths(tasks, cwd));
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
    closeAllFileWatchers();
    activeCtx = null;
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

      const onEdit = (task: Task) => {
        const filePath = task.sourcePath ?? join(ctx.cwd, TASKS_FILE);
        pi.events.emit("emacs:open", { file: filePath, line: task.lineNumber });
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
