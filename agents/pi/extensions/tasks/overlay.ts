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
import { writeFile } from "node:fs/promises";
import { join } from "node:path";

const STATUS_CYCLE = ["TODO", "STARTED", "WAITING", "DONE"] as const;

/** A flattened row for display & navigation. */
interface FlatRow {
  task: Task;
  depth: number;
  collapsed: boolean;
  hasChildren: boolean;
}

export class TasksOverlay {
  private theme: Theme;
  private done: (value: undefined) => void;
  private rows: FlatRow[] = [];
  private selected = 0;
  private scrollOffset = 0;
  private descScrollOffset = 0;
  private cachedWidth?: number;
  private cachedLines?: string[];

  private dirty = false;

  constructor(
    private tasks: Task[],
    private cwd: string,
    theme: Theme,
    done: (value: undefined) => void,
  ) {
    this.theme = theme;
    this.done = done;
    this.rebuildRows();
  }

  // ── Flatten visible rows ────────────────────────────────────────────

  private collapsedSet = new WeakSet<Task>();

  private rebuildRows(): void {
    this.rows = [];
    const walk = (tasks: Task[], depth: number) => {
      for (const t of tasks) {
        const collapsed = this.collapsedSet.has(t);
        this.rows.push({
          task: t,
          depth,
          collapsed,
          hasChildren: t.children.length > 0,
        });
        if (!collapsed) walk(t.children, depth + 1);
      }
    };
    walk(this.tasks, 0);
    if (this.selected >= this.rows.length) {
      this.selected = Math.max(0, this.rows.length - 1);
    }
  }

  // ── Input ───────────────────────────────────────────────────────────

  handleInput(data: string): void {
    if (matchesKey(data, "escape") || matchesKey(data, "q")) {
      this.done(undefined);
      return;
    }

    if (matchesKey(data, "up") || matchesKey(data, "k")) {
      if (this.selected > 0) {
        this.selected--;
        this.descScrollOffset = 0;
        this.invalidate();
      }
      return;
    }

    if (matchesKey(data, "down") || matchesKey(data, "j")) {
      if (this.selected < this.rows.length - 1) {
        this.selected++;
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

    // Toggle collapse
    if (
      matchesKey(data, "return") ||
      matchesKey(data, "space") ||
      matchesKey(data, "tab")
    ) {
      const row = this.rows[this.selected];
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
    const row = this.rows[this.selected];
    if (!row) return;
    const idx = STATUS_CYCLE.indexOf(
      row.task.status as (typeof STATUS_CYCLE)[number],
    );
    if (idx === -1) return;
    const next = (idx + direction + STATUS_CYCLE.length) % STATUS_CYCLE.length;
    row.task.status = STATUS_CYCLE[next];
    this.dirty = true;
    this.save();
    this.invalidate();
  }

  private async save(): Promise<void> {
    try {
      const content = serializeTasks(this.tasks);
      await writeFile(join(this.cwd, "TASKS.org"), content, "utf-8");
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
        counts.TODO > 0 ? th.fg("warning", `TODO:${counts.TODO}`) : null,
        counts.STARTED > 0
          ? th.fg("accent", `STARTED:${counts.STARTED}`)
          : null,
        counts.WAITING > 0 ? th.fg("error", `WAITING:${counts.WAITING}`) : null,
        counts.DONE > 0 ? th.fg("success", `DONE:${counts.DONE}`) : null,
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

      for (let i = 0; i < visibleRows.length; i++) {
        const r = visibleRows[i]!;
        const globalIdx = this.scrollOffset + i;
        const isSelected = globalIdx === this.selected;

        const indent = "  ".repeat(r.depth);
        const treeMark = r.hasChildren ? (r.collapsed ? "▶ " : "▼ ") : "• ";
        const statusStr = this.renderStatus(r.task.status, th);
        const prioStr = r.task.priority
          ? th.fg("warning", `[#${r.task.priority}]`) + " "
          : "";
        const tagsStr =
          r.task.tags.length > 0
            ? " " + th.fg("dim", `:${r.task.tags.join(":")}:`)
            : "";
        const summaryStr = isSelected
          ? th.fg("accent", r.task.summary)
          : th.fg("text", r.task.summary);

        const content = `${indent}${treeMark}${statusStr} ${prioStr}${summaryStr}${tagsStr}`;
        const pointer = isSelected ? th.fg("accent", "▌") : " ";
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
    const selectedRow = this.rows[this.selected];

    // Right pane header
    rightLines.push(th.fg("accent", th.bold(" Description")));
    rightLines.push("");

    if (selectedRow) {
      const desc = selectedRow.task.description.trim();
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
    const footerLines = 2; // help + bottom border
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
      " ↑↓/jk navigate • ←→/hl cycle status • Enter/Space toggle • Ctrl-d/u scroll desc • Esc/q close",
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
    if (this.selected < this.scrollOffset) {
      this.scrollOffset = this.selected;
    } else if (this.selected >= this.scrollOffset + maxVisible) {
      this.scrollOffset = this.selected - maxVisible + 1;
    }
  }

  private renderStatus(status: string, th: Theme): string {
    switch (status) {
      case "TODO":
        return th.fg("warning", "TODO   ");
      case "STARTED":
        return th.fg("accent", "STARTED");
      case "WAITING":
        return th.fg("error", "WAITING");
      case "DONE":
        return th.fg("success", "DONE   ");
      default:
        return th.fg("dim", status.padEnd(7));
    }
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
        walk(t.children);
      }
    };
    walk(tasks);
    return counts;
  }
}
