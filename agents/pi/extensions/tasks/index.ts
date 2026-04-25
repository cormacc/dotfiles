/**
 * Tasks Extension — track project tasks using org-mode TODO syntax.
 *
 * Reads TASKS.org from the project root and displays tasks in an expandable tree UI.
 *
 * Commands:
 *   /tasks — expand the tasks UI
 *   /tasks new — create a new top-level task
 *
 * Keybindings (via the keybindings extension):
 *   <leader> t t — expand the tasks UI
 *
 * Persistent UI:
 *   When a task is marked :selected: in TASKS.org, a compact widget above the
 *   editor shows that task plus a few subtasks. It is refreshed on startup and
 *   immediately as the expanded /tasks UI mutates task status/selection.
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
  type TUI,
} from "@mariozechner/pi-tui";
import { watch, type FSWatcher } from "node:fs";
import { randomUUID } from "node:crypto";
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { getExtensionName, suggestKeybindings } from "../lib/pi-utils.ts";
import { ensureEmacsServer } from "../emacsclient/emacsclient.ts";
import { TasksOverlay } from "./overlay.ts";
import {
  formatOrgTimestamp,
  parseTasks,
  serializeTasks,
  serializeTasksPreservingFile,
  taskHasId,
  type Task,
} from "./parser.ts";
import { colorPriority, colorStatus, colorTags } from "./status-colors.ts";

const EXT_NAME = getExtensionName(import.meta.url);
const TASKS_FILE = "TASKS.org";
const TASKS_ARCHIVE_FILE = "TASKS.ARCHIVE.org";
const SELECTED_TAG = "selected";
const CLOSED_STATUSES = new Set<string>(["DONE", "CANCELLED"]);
/** Hard cap so the compact selected-task widget never dominates the screen. */
const MAX_COMPACT_LINES = 6;
const COMPACT_WIDGET_ID = "tasks:selected";

/** Cleanup handle for keybinding suggestions. */
let cleanupKb: (() => void) | null = null;

/** Compact selected-task widget state. */
let compactWidgetComponent: CompactTasksWidget | null = null;
let compactWidgetTui: TUI | null = null;

/**
 * File-watcher state. The compact selected-task widget refreshes on external edits
 * (e.g. saving TASKS.org or a linked plan file in Emacs) without requiring
 * the /tasks modal to be reopened.
 */
const fileWatchers = new Map<string, FSWatcher>();
let watchDebounceTimer: ReturnType<typeof setTimeout> | null = null;
let activeCtx: ExtensionContext | null = null;

/** Collect every path whose changes should trigger a compact-widget refresh. */
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
    if (ctx) void refreshTaskUi(ctx, ctx.cwd);
  }, 150);
}

async function loadTasks(cwd: string): Promise<Task[]> {
  const sourcePath = join(cwd, TASKS_FILE);
  try {
    const content = await readFile(sourcePath, "utf-8");
    const tasks = parseTasks(content, { sourcePath });
    await loadLinkedPlans(tasks, sourcePath);
    try {
      await backfillMissingIds(cwd, tasks);
    } catch {
      // Keep the UI usable even if the automatic ID backfill cannot write.
    }
    return tasks;
  } catch {
    return [];
  }
}

async function loadLinkedPlans(
  tasks: Task[],
  sourcePath: string,
  cache = new Map<string, { tasks: Task[]; error: string | null }>(),
): Promise<void> {
  const sourceDir = dirname(sourcePath);
  for (const task of tasks) {
    if (task.planPath) {
      const planPath = isAbsolute(task.planPath)
        ? task.planPath
        : resolve(sourceDir, task.planPath);
      const cached = cache.get(planPath);
      if (cached) {
        task.planChildren = cached.tasks;
        task.planError = cached.error;
      } else {
        try {
          const content = await readFile(planPath, "utf-8");
          const planTasks = parseTasks(content, { sourcePath: planPath });
          const entry = { tasks: planTasks, error: null };
          cache.set(planPath, entry);
          await loadLinkedPlans(planTasks, planPath, cache);
          task.planChildren = planTasks;
          task.planError = null;
        } catch (err) {
          const error = (err as Error).message;
          task.planChildren = [];
          task.planError = error;
          cache.set(planPath, { tasks: task.planChildren, error });
        }
      }
    }
    await loadLinkedPlans(task.children, sourcePath, cache);
  }
}

async function backfillMissingIds(cwd: string, tasks: Task[]): Promise<void> {
  const changedRoots = new Map<string, Task[]>();
  const visit = (taskList: Task[]) => {
    for (const task of taskList) {
      if (!taskHasId(task)) {
        task.propertyLines.unshift(`:ID: ${randomUUID()}`);
        const sourcePath = task.sourcePath ?? join(cwd, TASKS_FILE);
        changedRoots.set(sourcePath, task.sourceRoot ?? tasks);
      }
      visit(task.children);
      if (task.planChildren) visit(task.planChildren);
    }
  };
  visit(tasks);

  await Promise.all(
    [...changedRoots.entries()].map(([path, root]) =>
      writeTaskFilePreserving(path, root),
    ),
  );
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

function findTopLevelRoot(tasks: Task[], target: Task): Task | null {
  const contains = (task: Task): boolean => {
    if (task === target) return true;
    return taskChildren(task).some(contains);
  };
  return tasks.find(contains) ?? null;
}

function formatTaskLine(
  t: Task,
  indent: string,
  marker: string,
  width: number,
): string {
  const priority = colorPriority(t.priority);
  const visibleTags = t.tags.filter((tg) => tg !== SELECTED_TAG);
  const tags = colorTags(visibleTags);
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

function formatPlanLabel(planPath: string): string {
  if (isAbsolute(planPath) || planPath.startsWith(".")) return planPath;
  return `./${planPath}`;
}

/** Build the compact selected-task widget's pre-styled lines, or undefined if nothing is selected. */
function buildCompactLines(
  tasks: Task[],
  theme: Theme,
  width: number,
): string[] | undefined {
  const selected = findSelectedTask(tasks);
  if (!selected) return undefined;
  const selectionRoot = findTopLevelRoot(tasks, selected) ?? selected;

  const hasLinkedPlan = !!selectionRoot.planPath &&
    (selectionRoot.planChildren?.length ?? 0) > 0;
  const headerLines = [
    border(width, theme),
    formatTaskLine(
      selectionRoot,
      "",
      selectionRoot === selected ? "★ " : "• ",
      width,
    ),
  ];
  if (hasLinkedPlan) {
    headerLines.push(
      truncateToWidth(
        theme.fg("borderMuted", `  ${formatPlanLabel(selectionRoot.planPath!)}`),
        width,
      ),
    );
  }
  const maxSubtaskLines = Math.max(
    0,
    MAX_COMPACT_LINES - headerLines.length,
  );

  const flattened: { task: Task; depth: number }[] = [];
  const walk = (children: Task[], depth: number) => {
    for (const child of children) {
      flattened.push({ task: child, depth });
      walk(taskChildren(child), depth + 1);
    }
  };
  walk(taskChildren(selectionRoot), 1);

  const visible = [...flattened];
  let hiddenCompleted = 0;

  // If truncation is needed, reclaim space from completed subtasks first,
  // scanning from the head so the compact view favours the selected task's
  // next pending work over old completed history.
  while (
    visible.length + (hiddenCompleted > 0 ? 1 : 0) > maxSubtaskLines
  ) {
    const doneIdx = visible.findIndex((row) => CLOSED_STATUSES.has(row.task.status));
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
    lines.push(
      formatTaskLine(
        row.task,
        "  ".repeat(row.depth),
        row.task === selected ? "★ " : "• ",
        width,
      ),
    );
  }

  if (hiddenMore > 0) {
    const label = hiddenMore === 1 ? "subtask" : "subtasks";
    lines.push(theme.fg("dim", `  … ${hiddenMore} more ${label}`));
  }

  return lines;
}

class CompactTasksWidget implements Component {
  constructor(
    private tasks: Task[],
    private readonly theme: Theme,
  ) {}

  setTasks(tasks: Task[]): void {
    this.tasks = tasks;
  }

  render(width: number): string[] {
    const lines = buildCompactLines(this.tasks, this.theme, width) ?? [];
    return lines.map((l) => truncateToWidth(l, width));
  }

  invalidate(): void {}
}

function clearCompactWidget(ctx?: ExtensionContext): void {
  if (ctx?.hasUI) ctx.ui.setWidget(COMPACT_WIDGET_ID, undefined);
  compactWidgetComponent = null;
  compactWidgetTui = null;
}

function syncCompactWidget(
  ctx: ExtensionContext,
  tasks: Task[],
  hidden = false,
): void {
  if (!ctx.hasUI) return;
  const hasSelectedTask = findSelectedTask(tasks) !== null;
  if (hidden || !hasSelectedTask) {
    clearCompactWidget(ctx);
    return;
  }

  if (compactWidgetComponent) {
    compactWidgetComponent.setTasks(tasks);
    compactWidgetTui?.requestRender();
    return;
  }

  ctx.ui.setWidget(COMPACT_WIDGET_ID, (tui, theme) => {
    compactWidgetTui = tui;
    compactWidgetComponent = new CompactTasksWidget(tasks, theme);
    return compactWidgetComponent;
  });
}

async function refreshTaskUi(
  ctx: ExtensionContext,
  cwd: string,
): Promise<Task[]> {
  activeCtx = ctx;
  const tasks = await loadTasks(cwd);
  syncCompactWidget(ctx, tasks);
  updateFileWatchers(collectWatchPaths(tasks, cwd));
  return tasks;
}

export default function (pi: ExtensionAPI) {
  // ── Keybinding suggestions + startup compact widget restore ─────────

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
                n: { label: "New task", action: "command:/tasks new" },
              },
            },
          },
        },
      },
    });

    await refreshTaskUi(ctx, ctx.cwd);
  });

  pi.on("session_shutdown", async () => {
    cleanupKb?.();
    cleanupKb = null;
    closeAllFileWatchers();
    clearCompactWidget(activeCtx ?? undefined);
    activeCtx = null;
  });

  // ── /tasks command ──────────────────────────────────────────────────

  pi.registerCommand("tasks", {
    description: "Show project tasks from TASKS.org",
    handler: async (args, ctx) => {
      if (!ctx.hasUI) {
        ctx.ui.notify("/tasks requires interactive mode", "error");
        return;
      }

      // `/tasks new` — create a new top-level task without opening the overlay.
      if (args?.trim() === "new") {
        const tasks = await loadTasks(ctx.cwd);
        const created = await createTask(ctx, tasks, ctx.cwd, null, null);
        if (created) {
          await refreshTaskUi(ctx, ctx.cwd);
        }
        return;
      }

      type WorkflowRequest =
        | { type: "archive"; task: Task }
        | { type: "create"; parent: Task | null; insertAfter: Task | null }
        | { type: "edit"; task: Task }
        | { type: "plan"; task: Task };

      let reopen = true;
      let tasks = await loadTasks(ctx.cwd);
      while (reopen) {
        clearCompactWidget(ctx);
        const workflow: { request: WorkflowRequest | null } = { request: null };

        const onEdit = (task: Task) => {
          workflow.request = { type: "edit", task };
        };

        const onTasksChanged = (_updatedTasks: Task[]) => {
          // Compact state is intentionally hidden while expanded; refresh after close.
        };

        const onEditPlan = (task: Task) => {
          workflow.request = { type: "plan", task };
        };

        const onArchive = (topLevel: Task) => {
          workflow.request = { type: "archive", task: topLevel };
        };

        const onNewTask = (parent: Task | null, insertAfter: Task | null) => {
          workflow.request = { type: "create", parent, insertAfter };
        };

        await ctx.ui.custom(
          (_tui, theme, _kb, done) =>
            new TasksOverlay(
              tasks,
              ctx.cwd,
              theme,
              done,
              onEdit,
              onTasksChanged,
              onEditPlan,
              onArchive,
              onNewTask,
            ),
          {
            overlay: true,
            overlayOptions: {
              width: "100%",
              anchor: "center",
            },
          },
        );

        const request = workflow.request as WorkflowRequest | null;
        if (!request) {
          reopen = false;
          continue;
        }

        if (request.type === "edit") {
          await openTaskInEmacs(pi, ctx, request.task);
          reopen = false;
        } else if (request.type === "plan") {
          await handlePlanEdit(pi, ctx, request.task);
          reopen = false;
        } else if (request.type === "archive") {
          await archiveTopLevel(ctx, tasks, request.task);
          tasks = await loadTasks(ctx.cwd);
          reopen = true;
        } else if (request.type === "create") {
          await createTask(ctx, tasks, ctx.cwd, request.parent, request.insertAfter);
          tasks = await loadTasks(ctx.cwd);
          reopen = true;
        }
      }

      // Re-read from disk after close to converge with the saved file state.
      await refreshTaskUi(ctx, ctx.cwd);
    },
  });
}

// ── Emacs / plan-edit flows ───────────────────────────────────────────

async function openTaskInEmacs(
  pi: ExtensionAPI,
  ctx: ExtensionContext,
  task: Task,
): Promise<void> {
  const filePath = task.sourcePath ?? join(ctx.cwd, TASKS_FILE);
  const ok = await ensureEmacsServer(getEmacsOptions(pi));
  if (!ok) {
    ctx.ui.notify("Could not reach or start Emacs server", "error");
    return;
  }
  pi.events.emit("emacs:open", { file: filePath, line: task.lineNumber });
}

/** Lowercase ASCII slug: letters/digits/hyphens, collapsed, trimmed, ≤ 40 chars. */
function slugify(summary: string): string {
  return summary
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40)
    .replace(/-+$/, "") || "plan";
}

async function pathExists(p: string): Promise<boolean> {
  try {
    await access(p);
    return true;
  } catch {
    return false;
  }
}

async function writeTaskFilePreserving(path: string, tasks: Task[]): Promise<void> {
  const cachedOriginal = tasks.find((t) => t.sourceContent)?.sourceContent;
  const original = cachedOriginal ?? ((await pathExists(path))
    ? await readFile(path, "utf-8")
    : "");
  const content = original
    ? serializeTasksPreservingFile(original, tasks)
    : serializeTasks(tasks);
  await writeFile(path, content, "utf-8");
}

function getEmacsOptions(pi: ExtensionAPI) {
  const env = (globalThis as { [key: string]: unknown })["process"] as
    | { env?: Record<string, string | undefined> }
    | undefined;
  return {
    binary: env?.env?.EMACSCLIENT_BINARY || "emacsclient",
    daemonBinary: env?.env?.EMACS_BINARY || "emacs",
    exec: (cmd: string, args: string[], opts?: { signal?: AbortSignal; timeout?: number }) =>
      pi.exec(cmd, args, {
        signal: opts?.signal,
        timeout: opts?.timeout,
      }),
  };
}

/**
 * Suggest a plan path for a task that has no :PLAN: yet.
 * Prefers existing directories in this order:
 *   1. `design/log/` under cwd
 *   2. `plans/` under cwd
 *   3. directory containing the task's source file
 */
async function suggestPlanPath(task: Task, cwd: string): Promise<string> {
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
  const slug = slugify(task.summary);
  const filename = `${today}-${slug}.org`;

  const designLog = join(cwd, "design", "log");
  if (await pathExists(designLog)) return join("design", "log", filename);

  const plans = join(cwd, "plans");
  if (await pathExists(plans)) return join("plans", filename);

  const srcDir = task.sourcePath ? dirname(task.sourcePath) : cwd;
  const rel = relative(cwd, srcDir) || ".";
  return join(rel, filename);
}

/** Scaffold a minimal plan file body consistent with the plan skill. */
function scaffoldPlan(task: Task): string {
  return [
    `#+TITLE: ${task.summary}`,
    `#+DATE: ${formatOrgTimestamp()}`,
    "#+TODO: TODO(t) STARTED(s) WAITING(w) | DONE(d) CANCELLED(c)",
    "",
    "* Context",
    "",
    "* Plan",
    "",
    "",
  ].join("\n");
}

/**
 * Resolve or create a plan for the given task, then open it in Emacs.
 *
 * If the task has a `:PLAN:` property: open that file.
 * Otherwise: prompt for a filename (seeded from the task summary and today's
 * date), scaffold the file, attach `:PLAN:` to the task, save the source
 * org file, then open the new plan.
 */
async function handlePlanEdit(
  pi: ExtensionAPI,
  ctx: ExtensionContext,
  task: Task,
): Promise<void> {
  const sourcePath = task.sourcePath ?? join(ctx.cwd, TASKS_FILE);
  const sourceDir = dirname(sourcePath);

  // ── Open existing plan ──
  if (task.planPath) {
    const absPlan = isAbsolute(task.planPath)
      ? task.planPath
      : resolve(sourceDir, task.planPath);
    if (!(await ensureEmacsServer(getEmacsOptions(pi)))) {
      ctx.ui.notify("Could not reach or start Emacs server", "error");
      return;
    }
    pi.events.emit("emacs:open", { file: absPlan, line: 1 });
    return;
  }

  // ── Create new plan ──
  const suggested = await suggestPlanPath(task, ctx.cwd);
  const approved = await ctx.ui.input(
    `New plan for: ${task.summary}`,
    suggested,
  );
  if (!approved) return;
  const relPath = approved.trim();
  if (!relPath) return;

  const absPlan = isAbsolute(relPath) ? relPath : resolve(ctx.cwd, relPath);
  const planRelToSource = relative(sourceDir, absPlan);

  try {
    await mkdir(dirname(absPlan), { recursive: true });
    if (!(await pathExists(absPlan))) {
      await writeFile(absPlan, scaffoldPlan(task), "utf-8");
    }

    // Attach :PLAN: to the in-memory task and save its source file.
    // Write the link form so the property is clickable in Emacs (C-c C-o)
    // while remaining parseable by the extension. The parser preserves this
    // raw value on round-trip.
    task.planPath = planRelToSource;
    task.planRaw = `[[file:${planRelToSource}]]`;
    const root = task.sourceRoot;
    if (root) {
      await writeTaskFilePreserving(sourcePath, root);
    }
  } catch (err) {
    ctx.ui.notify(
      `Failed to create plan: ${(err as Error).message}`,
      "error",
    );
    return;
  }

  if (!(await ensureEmacsServer(getEmacsOptions(pi)))) {
    ctx.ui.notify("Plan created but could not reach Emacs server", "warning");
    return;
  }
  pi.events.emit("emacs:open", { file: absPlan, line: 1 });
}

// ── Create task flow ─────────────────────────────────────────────────────

/**
 * Prompt for a title and insert a new task into the live tree, then save.
 *
 * @param parentTask  null → insert at the top level of `tasks`.
 * @param insertAfterTask  null → append; otherwise insert immediately after
 *                         this task within its container (parent's children
 *                         or the top-level array).
 */
async function createTask(
  ctx: ExtensionContext,
  tasks: Task[],
  cwd: string,
  parentTask: Task | null,
  insertAfterTask: Task | null,
): Promise<Task | null> {
  const prompt = parentTask
    ? `Subtask of "${parentTask.summary}"`
    : "New task title";
  const title = await ctx.ui.input(prompt, "");
  if (!title?.trim()) return null;

  const level = parentTask ? parentTask.level + 1 : 1;
  const newTask: Task = {
    level,
    status: "TODO",
    priority: null,
    summary: title.trim(),
    tags: [],
    description: "",
    children: [],
    propertyLines: [`:ID: ${randomUUID()}`],
    planPath: null,
    planRaw: null,
    planChildren: undefined,
    closed: null,
    sourcePath: join(cwd, TASKS_FILE),
    sourceContent: tasks.find((t) => t.sourceContent)?.sourceContent,
    sourceRoot: tasks,
    lineNumber: 0,
    endLine: 0,
  };

  const container: Task[] = parentTask ? parentTask.children : tasks;
  if (insertAfterTask) {
    const idx = container.indexOf(insertAfterTask);
    if (idx >= 0) {
      container.splice(idx + 1, 0, newTask);
    } else {
      container.push(newTask);
    }
  } else {
    container.push(newTask);
  }

  const tasksPath = join(cwd, TASKS_FILE);
  try {
    await writeTaskFilePreserving(tasksPath, tasks);
  } catch (err) {
    ctx.ui.notify(`Failed to save: ${(err as Error).message}`, "error");
    const rollback = container.indexOf(newTask);
    if (rollback >= 0) container.splice(rollback, 1);
    return null;
  }

  ctx.ui.notify(`Created: ${newTask.summary}`, "info");
  return newTask;
}

// ── Archive flow ───────────────────────────────────────────────────────

/**
 * Produce a self-contained deep clone of `task` suitable for the archive.
 * Linked plan children are inlined so the archive file doesn't depend on
 * external plan files that may later move or be cleaned up. Heading levels
 * are recomputed from the archive root down.
 */
function flattenForArchive(task: Task, depth: number): Task {
  const children: Task[] = [];
  for (const c of task.children) children.push(flattenForArchive(c, depth + 1));
  for (const c of task.planChildren ?? [])
    children.push(flattenForArchive(c, depth + 1));
  return {
    level: depth,
    status: task.status,
    priority: task.priority,
    summary: task.summary,
    tags: [...task.tags],
    description: task.description,
    children,
    propertyLines: [...task.propertyLines],
    planPath: null,
    planChildren: undefined,
    closed: task.closed,
    sourcePath: task.sourcePath,
    sourceContent: task.sourceContent,
    lineNumber: task.lineNumber,
    endLine: task.endLine,
  };
}

const ARCHIVED_PROPERTY_RE = /^\s*:ARCHIVED:\s*\[([^\]]+)\]\s*$/i;

function archiveSortTimestamp(task: Task): string {
  if (task.closed) return task.closed;
  for (const line of task.propertyLines) {
    const match = ARCHIVED_PROPERTY_RE.exec(line);
    if (match) return match[1]!.trim();
  }
  return "9999-12-31 Zzz 23:59";
}

function sortArchivedTasks(tasks: Task[]): Task[] {
  return tasks
    .map((task, index) => ({ task, index }))
    .sort((a, b) => {
      const aStamp = archiveSortTimestamp(a.task);
      const bStamp = archiveSortTimestamp(b.task);
      return aStamp.localeCompare(bStamp) || a.index - b.index;
    })
    .map(({ task }) => task);
}

/**
 * Archive a top-level TASKS.org task to TASKS.ARCHIVE.org.
 *
 * Rules (per the plan):
 *   - Only CLOSED-state (`DONE`/`CANCELLED`) top-level tasks can be archived.
 *     Other statuses are refused to avoid accidentally archiving active work.
 *   - Confirmation dialog via ctx.ui.confirm.
 *   - The whole subtree is archived. Linked plan children are inlined so the
 *     archive is self-contained.
 *   - An :ARCHIVED: [timestamp] property is added to the top-level heading.
 *   - Archived entries are sorted by CLOSED time, falling back to ARCHIVED
 *     time when CLOSED is absent.
 *
 * Returns true if the task was archived and the in-memory tree mutated.
 */
async function archiveTopLevel(
  ctx: ExtensionContext,
  tasks: Task[],
  topLevel: Task,
): Promise<boolean> {
  if (!CLOSED_STATUSES.has(topLevel.status)) {
    ctx.ui.notify(
      `Cannot archive '${topLevel.summary}': status is ${topLevel.status}, not DONE/CANCELLED.`,
      "warning",
    );
    return false;
  }

  const ok = await ctx.ui.confirm(
    "Archive task?",
    `Move '${topLevel.summary}' and all subtasks to ${TASKS_ARCHIVE_FILE}.`,
  );
  if (!ok) return false;

  const idx = tasks.indexOf(topLevel);
  if (idx === -1) {
    ctx.ui.notify("Task is not a top-level entry; cannot archive.", "error");
    return false;
  }

  // Build the archive copy: flatten plan children inline, strip :selected:,
  // stamp :ARCHIVED:. Uses CLOSED timestamp if present (fallback: now).
  const archiveCopy = flattenForArchive(topLevel, 1);
  archiveCopy.tags = archiveCopy.tags.filter((t) => t !== SELECTED_TAG);
  const stamp = topLevel.closed ?? formatOrgTimestamp();
  archiveCopy.propertyLines.push(`:ARCHIVED: [${stamp}]`);

  // Mutate the live task tree: remove from top-level.
  tasks.splice(idx, 1);

  const archivePath = join(ctx.cwd, TASKS_ARCHIVE_FILE);
  const tasksPath = join(ctx.cwd, TASKS_FILE);
  try {
    const existing = (await pathExists(archivePath))
      ? await readFile(archivePath, "utf-8")
      : "";
    const archivedTasks = existing.trim() === ""
      ? []
      : parseTasks(existing, { sourcePath: archivePath });
    archivedTasks.push(archiveCopy);
    const sortedArchive = sortArchivedTasks(archivedTasks);
    await writeFile(archivePath, serializeTasks(sortedArchive), "utf-8");
    await writeTaskFilePreserving(tasksPath, tasks);
  } catch (err) {
    // Roll back in-memory change so the overlay stays consistent with disk.
    tasks.splice(idx, 0, topLevel);
    ctx.ui.notify(`Archive failed: ${(err as Error).message}`, "error");
    return false;
  }

  ctx.ui.notify(`Archived: ${topLevel.summary}`, "info");
  await refreshTaskUi(ctx, ctx.cwd);
  return true;
}
