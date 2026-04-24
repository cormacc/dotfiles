/**
 * Tasks overlay component — split-pane: task tree (left) + description (right).
 */

import type { Theme } from "@mariozechner/pi-coding-agent";
import {
  matchesKey,
  truncateToWidth,
  visibleWidth,
  wrapTextWithAnsi,
} from "@mariozechner/pi-tui";
import type { Task } from "./parser.ts";
import { serializeTasks } from "./parser.ts";
import { colorStatus } from "./status-colors.ts";
import { writeFile } from "node:fs/promises";
import { join } from "node:path";

const STATUS_CYCLE = ["TODO", "STARTED", "WAITING", "DONE"] as const;

/** Reserved tag used to mark the currently-selected task. */
const SELECTED_TAG = "selected";

/** A flattened row for display & navigation. */
interface FlatRow {
  task: Task;
  depth: number;
  collapsed: boolean;
  hasChildren: boolean;
  /** True when this task carries the :selected: tag. */
  isSelectedTask: boolean;
  /** True when this task is the selected task or one of its descendants. */
  inSelection: boolean;
}

export class TasksOverlay {
  private theme: Theme;
  private done: (value: undefined) => void;
  private rows: FlatRow[] = [];
  /** Cursor index into `rows` — the user's current navigation position. */
  private cursor = 0;
  private scrollOffset = 0;
  private descScrollOffset = 0;
  private cachedWidth?: number;
  private cachedLines?: string[];

  private collapsedSet = new WeakSet<Task>();

  constructor(
    private tasks: Task[],
    private cwd: string,
    theme: Theme,
    done: (value: undefined) => void,
    private onEdit?: (task: Task) => void,
    private onTasksChanged?: (tasks: Task[]) => void,
  ) {
    this.theme = theme;
    this.done = done;
    // If the file already marks a selected task, reflect that view on open.
    this.applySelectionView();
    this.rebuildRows();
    this.focusSelectedTask();
  }

  // ── Flatten visible rows ────────────────────────────────────────────

  private rebuildRows(): void {
    this.rows = [];
    const selected = this.findSelectedTask();
    const inSelection = new WeakSet<Task>();
    if (selected) {
      const mark = (t: Task) => {
        inSelection.add(t);
        for (const c of this.taskChildren(t)) mark(c);
      };
      mark(selected);
    }

    const walk = (tasks: Task[], depth: number) => {
      for (const t of tasks) {
        const collapsed = this.collapsedSet.has(t);
        this.rows.push({
          task: t,
          depth,
          collapsed,
          hasChildren: this.taskChildren(t).length > 0,
          isSelectedTask: t === selected,
          inSelection: inSelection.has(t),
        });
        if (!collapsed) walk(this.taskChildren(t), depth + 1);
      }
    };
    walk(this.tasks, 0);
    if (this.cursor >= this.rows.length) {
      this.cursor = Math.max(0, this.rows.length - 1);
    }
  }

  /** Move the cursor onto the selected task, if any is visible. */
  private focusSelectedTask(): void {
    const idx = this.rows.findIndex((r) => r.isSelectedTask);
    if (idx >= 0) this.cursor = idx;
  }

  private taskChildren(task: Task): Task[] {
    return [...task.children, ...(task.planChildren ?? [])];
  }

  // ── Input ───────────────────────────────────────────────────────────

  handleInput(data: string): void {
    if (matchesKey(data, "escape") || matchesKey(data, "q")) {
      this.done(undefined);
      return;
    }

    if (matchesKey(data, "up") || matchesKey(data, "k")) {
      if (this.cursor > 0) {
        this.cursor--;
        this.descScrollOffset = 0;
        this.invalidate();
      }
      return;
    }

    if (matchesKey(data, "down") || matchesKey(data, "j")) {
      if (this.cursor < this.rows.length - 1) {
        this.cursor++;
        this.descScrollOffset = 0;
        this.invalidate();
      }
      return;
    }

    // Cycle status forward
    if (matchesKey(data, "right") || matchesKey(data, "l")) {
      this.cycleStatus(1);
      return;
    }

    // Cycle status backward
    if (matchesKey(data, "left") || matchesKey(data, "h")) {
      this.cycleStatus(-1);
      return;
    }

    // Scroll description pane
    if (matchesKey(data, "ctrl+d")) {
      this.descScrollOffset += 5;
      this.invalidate();
      return;
    }
    if (matchesKey(data, "ctrl+u")) {
      this.descScrollOffset = Math.max(0, this.descScrollOffset - 5);
      this.invalidate();
      return;
    }

    // Open in Emacs at the task under the cursor
    if (matchesKey(data, "e")) {
      const row = this.rows[this.cursor];
      if (row && this.onEdit) {
        this.onEdit(row.task);
        this.done(undefined);
      }
      return;
    }

    // Toggle :selected: on the task under the cursor
    if (matchesKey(data, "s")) {
      this.toggleSelect();
      return;
    }

    // Toggle collapse
    if (
      matchesKey(data, "return") ||
      matchesKey(data, "space") ||
      matchesKey(data, "tab")
    ) {
      const row = this.rows[this.cursor];
      if (row && row.hasChildren) {
        if (this.collapsedSet.has(row.task)) {
          this.collapsedSet.delete(row.task);
        } else {
          this.collapsedSet.add(row.task);
        }
        this.rebuildRows();
        this.invalidate();
      }
      return;
    }
  }

  private cycleStatus(direction: 1 | -1): void {
    const row = this.rows[this.cursor];
    if (!row) return;
    const idx = STATUS_CYCLE.indexOf(
      row.task.status as (typeof STATUS_CYCLE)[number],
    );
    if (idx === -1) return;
    const next = (idx + direction + STATUS_CYCLE.length) % STATUS_CYCLE.length;
    row.task.status = STATUS_CYCLE[next];
    this.persistChange();
    this.invalidate();
  }

  // ── Selection (:selected: tag) ──────────────────────────────────────

  private findSelectedTask(tasks: Task[] = this.tasks): Task | null {
    for (const t of tasks) {
      if (t.tags.includes(SELECTED_TAG)) return t;
      const child = this.findSelectedTask(this.taskChildren(t));
      if (child) return child;
    }
    return null;
  }

  private clearSelectedTags(tasks: Task[] = this.tasks): void {
    for (const t of tasks) {
      if (t.tags.includes(SELECTED_TAG)) {
        t.tags = t.tags.filter((tag) => tag !== SELECTED_TAG);
      }
      this.clearSelectedTags(this.taskChildren(t));
    }
  }

  private toggleSelect(): void {
    const row = this.rows[this.cursor];
    if (!row) return;
    const target = row.task;
    const wasSelected = target.tags.includes(SELECTED_TAG);

    // Enforce single-selection: clear any existing :selected: first.
    this.clearSelectedTags();
    if (!wasSelected) {
      target.tags.push(SELECTED_TAG);
    }

    this.applySelectionView();
    this.rebuildRows();
    // Keep the cursor on the task the user just toggled, if still visible.
    const newIdx = this.rows.findIndex((r) => r.task === target);
    if (newIdx >= 0) this.cursor = newIdx;
    this.persistChange();
    this.invalidate();
  }

  /**
   * When a task is selected, collapse every task that is not either the
   * selected task itself, one of its ancestors, or one of its descendants.
   * When nothing is selected, drop all auto-collapses.
   */
  private applySelectionView(): void {
    this.collapsedSet = new WeakSet<Task>();
    const selected = this.findSelectedTask();
    if (!selected) return;

    const keepExpanded = new WeakSet<Task>();

    // Mark ancestors + selected along the discovered path.
    const markPath = (tasks: Task[], path: Task[]): boolean => {
      for (const t of tasks) {
        const next = [...path, t];
        if (t === selected) {
          for (const p of next) keepExpanded.add(p);
          return true;
        }
        if (markPath(this.taskChildren(t), next)) return true;
      }
      return false;
    };
    markPath(this.tasks, []);

    // Mark descendants.
    const markSubtree = (t: Task) => {
      keepExpanded.add(t);
      for (const c of this.taskChildren(t)) markSubtree(c);
    };
    markSubtree(selected);

    // Collapse anything outside that set with children.
    const collapseOthers = (tasks: Task[]) => {
      for (const t of tasks) {
        const children = this.taskChildren(t);
        if (!keepExpanded.has(t) && children.length > 0) {
          this.collapsedSet.add(t);
        }
        collapseOthers(children);
      }
    };
    collapseOthers(this.tasks);
  }

  private persistChange(): void {
    void this.save();
    this.onTasksChanged?.(this.tasks);
  }

  private async save(): Promise<void> {
    try {
      const roots = new Map<string, Task[]>();
      roots.set(join(this.cwd, "TASKS.org"), this.tasks);

      const collect = (tasks: Task[]) => {
        for (const task of tasks) {
          if (task.sourcePath && task.sourceRoot) {
            roots.set(task.sourcePath, task.sourceRoot);
          }
          collect(task.children);
          if (task.planChildren) collect(task.planChildren);
        }
      };
      collect(this.tasks);

      await Promise.all(
        [...roots.entries()].map(([path, tasks]) =>
          writeFile(path, serializeTasks(tasks), "utf-8"),
        ),
      );
    } catch {
      // Best-effort save; overlay stays usable
    }
  }

  // ── Render ──────────────────────────────────────────────────────────

  render(width: number): string[] {
    if (this.cachedLines && this.cachedWidth === width) {
      return this.cachedLines;
    }

    const th = this.theme;
    const lines: string[] = [];

    // Split: left pane ~55%, right pane gets the rest
    // Subtract 3 for outer borders + divider
    const usable = width - 3;
    const leftW = Math.max(30, Math.floor(usable * 0.55));
    const rightW = Math.max(20, usable - leftW);

    const maxVisible = 20;

    // ── helpers ──
    const hBar = (n: number) => "─".repeat(Math.max(0, n));
    const pad = (content: string, w: number) => {
      const vis = visibleWidth(content);
      const p = Math.max(0, w - vis);
      return content + " ".repeat(p);
    };

    // ── Build left pane lines ──
    const leftLines: string[] = [];

    // Header
    leftLines.push(th.fg("accent", th.bold(" Tasks")));
    leftLines.push("");

    if (this.rows.length === 0) {
      leftLines.push(th.fg("dim", " No tasks found."));
      leftLines.push(th.fg("dim", " Create TASKS.org in project root."));
    } else {
      // Summary counts
      const counts = this.countStatuses(this.tasks);
      const summary = [
        counts.TODO > 0
          ? colorStatus("TODO", `TODO:${counts.TODO}`)
          : null,
        counts.STARTED > 0
          ? colorStatus("STARTED", `STARTED:${counts.STARTED}`)
          : null,
        counts.WAITING > 0
          ? colorStatus("WAITING", `WAITING:${counts.WAITING}`)
          : null,
        counts.DONE > 0
          ? colorStatus("DONE", `DONE:${counts.DONE}`)
          : null,
      ]
        .filter(Boolean)
        .join(th.fg("dim", " │ "));
      leftLines.push(" " + summary);
      leftLines.push("");

      // Task rows
      this.adjustScroll(maxVisible);
      const visibleRows = this.rows.slice(
        this.scrollOffset,
        this.scrollOffset + maxVisible,
      );

      // When anything is selected, non-selection rows are dimmed so the
      // selected subtree dominates the view.
      const hasSelection = this.rows.some((r) => r.isSelectedTask);

      for (let i = 0; i < visibleRows.length; i++) {
        const r = visibleRows[i]!;
        const globalIdx = this.scrollOffset + i;
        const isCursor = globalIdx === this.cursor;
        const dimmed = hasSelection && !r.inSelection;

        const indent = "  ".repeat(r.depth);
        const treeMark = r.hasChildren ? (r.collapsed ? "▶ " : "▼ ") : "• ";

        // Hide the :selected: tag from the tag list — it's conveyed by the
        // star marker and highlight instead.
        const visibleTags = r.task.tags.filter((t) => t !== SELECTED_TAG);
        const rawTags =
          visibleTags.length > 0 ? ` :${visibleTags.join(":")}:` : "";

        let statusStr: string;
        let prioStr: string;
        let selectMark: string;
        let summaryStr: string;
        let tagsStr: string;
        let indentStr: string;
        let treeStr: string;

        if (dimmed) {
          // Everything on this row is dimmed — background material.
          indentStr = indent;
          treeStr = th.fg("dim", treeMark);
          statusStr = th.fg("dim", r.task.status.padEnd(7));
          prioStr = r.task.priority
            ? th.fg("dim", `[#${r.task.priority}]`) + " "
            : "";
          selectMark = "";
          summaryStr = th.fg("dim", r.task.summary);
          tagsStr = rawTags ? th.fg("dim", rawTags) : "";
        } else {
          indentStr = indent;
          treeStr = treeMark;
          statusStr = this.renderStatus(r.task.status, th);
          prioStr = r.task.priority
            ? th.fg("warning", `[#${r.task.priority}]`) + " "
            : "";
          selectMark = r.isSelectedTask ? th.fg("accent", "★ ") : "";
          tagsStr = rawTags ? th.fg("dim", rawTags) : "";

          // Cursor > selected task > in-selection > plain.
          if (isCursor) {
            summaryStr = th.fg("accent", th.bold(r.task.summary));
          } else if (r.isSelectedTask) {
            summaryStr = th.fg("accent", th.bold(r.task.summary));
          } else if (r.inSelection) {
            summaryStr = th.fg("accent", r.task.summary);
          } else {
            summaryStr = th.fg("text", r.task.summary);
          }
        }

        const content = `${indentStr}${treeStr}${statusStr} ${prioStr}${selectMark}${summaryStr}${tagsStr}`;
        const pointer = isCursor
          ? th.fg("accent", "▌")
          : r.isSelectedTask
            ? th.fg("accent", "┃")
            : r.inSelection
              ? th.fg("accent", "│")
              : " ";
        leftLines.push(truncateToWidth(pointer + content, leftW));
      }

      // Scroll indicator
      if (this.rows.length > maxVisible) {
        const pct = Math.round(
          (this.scrollOffset / Math.max(1, this.rows.length - maxVisible)) *
            100,
        );
        leftLines.push(
          th.fg(
            "dim",
            ` ${this.scrollOffset + 1}-${Math.min(this.scrollOffset + maxVisible, this.rows.length)} of ${this.rows.length} (${pct}%)`,
          ),
        );
      }
    }

    // ── Build right pane lines ──
    const rightLines: string[] = [];
    const cursorRow = this.rows[this.cursor];

    // Right pane header
    rightLines.push(th.fg("accent", th.bold(" Description")));
    rightLines.push("");

    if (cursorRow) {
      const desc = cursorRow.task.description.trim();
      if (desc) {
        // Word-wrap the description to fit the right pane
        const wrapWidth = Math.max(10, rightW - 2);
        const rawLines = desc.split("\n");
        const wrapped: string[] = [];
        for (const raw of rawLines) {
          if (raw.trim() === "") {
            wrapped.push("");
          } else {
            const w = wrapTextWithAnsi(raw, wrapWidth);
            wrapped.push(...w);
          }
        }

        // Clamp desc scroll
        const maxDescScroll = Math.max(0, wrapped.length - maxVisible);
        if (this.descScrollOffset > maxDescScroll) {
          this.descScrollOffset = maxDescScroll;
        }

        const visibleDesc = wrapped.slice(
          this.descScrollOffset,
          this.descScrollOffset + maxVisible,
        );
        for (const l of visibleDesc) {
          rightLines.push(" " + th.fg("text", l));
        }

        if (wrapped.length > maxVisible) {
          rightLines.push("");
          rightLines.push(
            th.fg(
              "dim",
              ` Ctrl-d/u scroll (${this.descScrollOffset + 1}-${Math.min(this.descScrollOffset + maxVisible, wrapped.length)}/${wrapped.length})`,
            ),
          );
        }
      } else {
        rightLines.push(th.fg("dim", " No description."));
      }
    } else {
      rightLines.push(th.fg("dim", " No task selected."));
    }

    // ── Compose split pane ──
    // Calculate body height: max of both panes, capped
    const bodyHeight = Math.max(
      leftLines.length,
      rightLines.length,
      maxVisible + 4,
    );

    // Pad panes to equal height
    while (leftLines.length < bodyHeight) leftLines.push("");
    while (rightLines.length < bodyHeight) rightLines.push("");

    // Top border: ╭──...──┬──...──╮
    lines.push(th.fg("border", `╭${hBar(leftW)}┬${hBar(rightW)}╮`));

    // Body rows: │ left │ right │
    for (let i = 0; i < bodyHeight; i++) {
      const l = truncateToWidth(pad(leftLines[i] ?? "", leftW), leftW);
      const r = truncateToWidth(pad(rightLines[i] ?? "", rightW), rightW);
      lines.push(
        th.fg("border", "│") +
          l +
          th.fg("border", "│") +
          r +
          th.fg("border", "│"),
      );
    }

    // Help row: ├──...──┴──...──┤  then help text row
    lines.push(th.fg("border", `├${hBar(leftW)}┴${hBar(rightW)}┤`));
    const helpText = th.fg(
      "dim",
      " ↑↓/jk nav • ←→/hl status • Enter toggle • s select • e edit • Ctrl-d/u scroll • q close",
    );
    const helpInnerW = leftW + rightW + 1; // +1 for removed divider
    lines.push(
      th.fg("border", "│") +
        truncateToWidth(pad(helpText, helpInnerW), helpInnerW) +
        th.fg("border", "│"),
    );

    // Bottom border: ╰──...──╯
    lines.push(th.fg("border", `╰${hBar(leftW + rightW + 1)}╯`));

    this.cachedWidth = width;
    this.cachedLines = lines;
    return lines;
  }

  invalidate(): void {
    this.cachedWidth = undefined;
    this.cachedLines = undefined;
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  private adjustScroll(maxVisible: number): void {
    if (this.cursor < this.scrollOffset) {
      this.scrollOffset = this.cursor;
    } else if (this.cursor >= this.scrollOffset + maxVisible) {
      this.scrollOffset = this.cursor - maxVisible + 1;
    }
  }

  private renderStatus(status: string, _th: Theme): string {
    return colorStatus(status);
  }

  private countStatuses(tasks: Task[]): Record<string, number> {
    const counts: Record<string, number> = {
      TODO: 0,
      STARTED: 0,
      WAITING: 0,
      DONE: 0,
    };
    const walk = (ts: Task[]) => {
      for (const t of ts) {
        counts[t.status] = (counts[t.status] ?? 0) + 1;
        walk(this.taskChildren(t));
      }
    };
    walk(tasks);
    return counts;
  }
}
