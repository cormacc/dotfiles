/**
 * Org-mode TASKS.org parser.
 *
 * Parses headings of the form:
 *   * STATUS [#PRIORITY] Summary text :tag1:tag2:
 *
 * Valid status tokens: TODO, STARTED, WAITING, DONE, CANCELLED
 * Priority is optional, e.g. [#A], [#B], [#C]
 * Tags are optional, colon-delimited at end of heading
 * Body text between headings becomes the task description.
 * Nested headings become subtasks (arbitrary depth).
 */

export interface Task {
  level: number;
  status: string;
  priority: string | null;
  summary: string;
  tags: string[];
  description: string;
  children: Task[];
  /** Non-PLAN org property drawer lines, preserved on save. */
  propertyLines: string[];
  /**
   * True when this task comes from the gitignored `TASKS.local.org`.
   * Set by the loader after parsing; not stored in the org file.
   */
  isLocal?: boolean;
  /** Path extracted from a `#+IMPORT:` keyword in the task body or file root. */
  importPath: string | null;
  /**
   * Raw `#+IMPORT:` value, preserved for round-trip serialization.
   * When the user writes an org-link form (e.g. `[[file:plans/foo.org][Plan]]`)
   * it's preserved verbatim so Emacs keeps treating it as a clickable link
   * while the extension still follows the extracted path.
   */
  importRaw?: string | null;
  /** Tasks loaded from the imported file, injected as children at render time. */
  importChildren?: Task[];
  /** Error encountered while loading `importPath`, if any. */
  importError?: string | null;
  /**
   * Org CLOSED timestamp body (without brackets), e.g. `2026-04-24 Fri 14:30`.
   * Present when the task has been closed, matching Emacs behaviour.
   */
  closed: string | null;
  /** Absolute path of the source org file this task came from. */
  sourcePath?: string;
  /** Original source content of sourcePath, used for preserving non-task org content on save. */
  sourceContent?: string;
  /** Root task tree for sourcePath, used to save linked plan files. */
  sourceRoot?: Task[];
  /** 1-indexed line number of the heading in the source file. */
  lineNumber: number;
  /** 1-indexed exclusive line number where this task subtree ended when parsed. */
  endLine: number;
}

/** Matches any org heading: `* ...`, `** ...`, etc. */
const ANY_HEADING_RE = /^(\*+)\s+(.*)$/;

const HEADING_RE =
  /^(\*+)\s+(TODO|STARTED|WAITING|DONE|CANCELLED)\s+(?:\[#([A-Z])\]\s+)?(.+)$/;

const PROPERTIES_START_RE = /^\s*:PROPERTIES:\s*$/i;
const PROPERTIES_END_RE = /^\s*:END:\s*$/i;
/** Matches a `#+IMPORT:` keyword anywhere in a file (task body or root level). */
const IMPORT_KEYWORD_RE = /^\s*#\+IMPORT:\s*(.*?)\s*$/i;
const ID_PROPERTY_RE = /^\s*:ID:\s*(\S+)\s*$/i;
const STARTED_PROPERTY_RE = /^\s*:STARTED:\s*\[([^\]]+)\]\s*$/i;
/**
 * Extract the target path from an org link expression:
 *   [[file:path]]                  → path
 *   [[file:path][description]]     → path
 *   [[path]]                       → path
 * Returns null when the value isn't an org link.
 */
const ORG_LINK_RE = /^\[\[(?:file:)?([^\]]+?)\](?:\[[^\]]*\])?\]$/;

/** Extract a target path from an org link expression, or null for non-link text. */
export function extractOrgLinkTarget(value: string): string | null {
  const match = ORG_LINK_RE.exec(value.trim());
  return match?.[1]?.trim() || null;
}

/** Matches an org CLOSED timestamp line, e.g. `CLOSED: [2026-04-24 Fri 14:30]`. */
const CLOSED_RE = /^\s*CLOSED:\s*\[([^\]]+)\]\s*$/;

/** Matches the #+SELECTED: keyword in TASKS.local.org. */
const SELECTED_KEYWORD_RE = /^#\+SELECTED:\s*(\S+)\s*$/im;

/**
 * Extract the selected task UUID from TASKS.local.org content.
 * Returns null when the file is empty or has no #+SELECTED: keyword.
 */
export function parseSelectedKeyword(content: string): string | null {
  const match = SELECTED_KEYWORD_RE.exec(content);
  return match?.[1]?.trim() ?? null;
}

const DAY_ABBR = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] as const;

/** Format a Date as an inactive org timestamp body, e.g. `2026-04-24 Fri 14:30`. */
export function formatOrgTimestamp(d: Date = new Date()): string {
  const pad = (n: number) => n.toString().padStart(2, "0");
  const y = d.getFullYear();
  const mo = pad(d.getMonth() + 1);
  const da = pad(d.getDate());
  const hh = pad(d.getHours());
  const mm = pad(d.getMinutes());
  const dow = DAY_ABBR[d.getDay()]!;
  return `${y}-${mo}-${da} ${dow} ${hh}:${mm}`;
}

/**
 * Parse a single heading line into its components.
 * Returns null if the line is not a valid task heading.
 */
function parseHeading(line: string): {
  level: number;
  status: string;
  priority: string | null;
  summary: string;
  tags: string[];
} | null {
  const m = HEADING_RE.exec(line);
  if (!m) return null;

  const level = m[1]!.length;
  const status = m[2]!;
  let summary = m[4]!.trimEnd();
  const tags: string[] = [];

  // Extract trailing tags  :tag1:tag2:
  const tagMatch = /\s+:([\w:]+):\s*$/.exec(summary);
  if (tagMatch) {
    summary = summary.slice(0, tagMatch.index).trimEnd();
    for (const t of tagMatch[1]!.split(":")) {
      if (t) tags.push(t);
    }
  }

  return { level, status, priority: m[3] ?? null, summary, tags };
}

/**
 * Result returned by `parseTasks`.
 * `fileImports` collects paths from `#+IMPORT:` lines that appear before any
 * task heading (i.e. at the file root level, with no parent task).
 */
export interface ParseResult {
  tasks: Task[];
  fileImports: string[];
}

export interface ParseTasksOptions {
  /** Absolute path of the file being parsed. */
  sourcePath?: string;
  /** Original source content. Defaults to the parsed content. */
  sourceContent?: string;
}

/** Return the org `:ID:` property value for a task, if present. */
export function getTaskId(task: Task): string | null {
  for (const line of task.propertyLines) {
    const match = ID_PROPERTY_RE.exec(line);
    if (match) return match[1]!.trim();
  }
  return null;
}

/** True when a task already has an org `:ID:` property. */
export function taskHasId(task: Task): boolean {
  return getTaskId(task) !== null;
}

/**
 * Return the org `:STARTED:` property value (timestamp body without brackets,
 * matching the `closed` field convention), if present.
 * Used by the retrospective change-record flow to scope `git log`.
 */
export function getTaskStarted(task: Task): string | null {
  for (const line of task.propertyLines) {
    const match = STARTED_PROPERTY_RE.exec(line);
    if (match) return match[1]!.trim();
  }
  return null;
}

/** True when a task has a recorded `:STARTED:` first-transition timestamp. */
export function taskHasStartedProperty(task: Task): boolean {
  return getTaskStarted(task) !== null;
}

/**
 * Parse the full content of a TASKS.org file into a task tree.
 *
 * `#+IMPORT: [[file:path]]` lines are recognised anywhere in the file:
 * - Inside a task body: sets `importPath` on that task.
 * - Before any task heading (file root): collected in `ParseResult.fileImports`.
 */
export function parseTasks(
  content: string,
  options: ParseTasksOptions = {},
): ParseResult {
  const lines = content.split("\n");
  const root: Task[] = [];
  const fileImports: string[] = [];
  const sourceContent = options.sourceContent ?? content;

  // Stack tracks the current nesting path.
  // Each entry: { task, level } — the task and its heading level.
  const stack: { task: Task; level: number }[] = [];

  let currentTask: Task | null = null;
  const descriptionLines: string[] = [];

  const flushDescription = () => {
    if (currentTask) {
      // Trim leading/trailing blank lines from description
      let desc = descriptionLines.join("\n");
      desc = desc.replace(/^\n+/, "").replace(/\n+$/, "");
      currentTask.description = desc;
    }
    descriptionLines.length = 0;
  };

  const closeTasksAtOrAbove = (level: number, endLineExclusive: number) => {
    while (stack.length > 0 && stack[stack.length - 1]!.level >= level) {
      const closed = stack.pop()!.task;
      closed.endLine = endLineExclusive;
    }
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;
    const heading = parseHeading(line);
    const anyHeading = ANY_HEADING_RE.exec(line);

    if (heading) {
      // Flush any accumulated description for the previous task
      flushDescription();
      closeTasksAtOrAbove(heading.level, i + 1);

      const task: Task = {
        level: heading.level,
        status: heading.status,
        priority: heading.priority,
        summary: heading.summary,
        tags: heading.tags,
        description: "",
        children: [],
        propertyLines: [],
        importPath: null,
        importRaw: null,
        importError: null,
        closed: null,
        sourcePath: options.sourcePath,
        sourceContent,
        lineNumber: i + 1,
        endLine: lines.length + 1,
      };

      if (stack.length === 0) {
        // Top-level task
        root.push(task);
      } else {
        // Child of the task on top of stack
        stack[stack.length - 1]!.task.children.push(task);
      }

      stack.push({ task, level: heading.level });
      currentTask = task;
    } else if (currentTask && CLOSED_RE.test(line)) {
      // Emacs writes `CLOSED: [...]` immediately after a heading transitions
      // to a done state. Capture it as metadata rather than description.
      const m = CLOSED_RE.exec(line)!;
      currentTask.closed = m[1]!.trim();
    } else if (currentTask && PROPERTIES_START_RE.test(line)) {
      // Org properties drawer — collect all lines verbatim for round-trip.
      for (i = i + 1; i < lines.length; i++) {
        const propLine = lines[i]!;
        if (PROPERTIES_END_RE.test(propLine)) break;
        currentTask.propertyLines.push(propLine);
      }
    } else if (anyHeading) {
      // Non-task heading (e.g. `* Notes`) — flush the current task's
      // description and stop attributing subsequent lines to it, so
      // unrelated content below isn't swallowed into the previous task.
      flushDescription();
      closeTasksAtOrAbove(anyHeading[1]!.length, i + 1);
      currentTask = null;
    } else if (IMPORT_KEYWORD_RE.test(line)) {
      // #+IMPORT: keyword — extract path and attach to current task or collect
      // as a file-level import when no task heading is in scope.
      const raw = IMPORT_KEYWORD_RE.exec(line)![1]!.trim();
      if (raw) {
        const linkTarget = extractOrgLinkTarget(raw);
        const path = linkTarget ?? raw;
        if (currentTask) {
          currentTask.importPath = path;
          currentTask.importRaw = linkTarget ? raw : null;
        } else {
          fileImports.push(path);
        }
      }
    } else {
      // Non-heading line: accumulate as description for current task
      if (currentTask) {
        descriptionLines.push(line);
      }
    }
  }

  // Flush description for the last task and close any open task ranges.
  flushDescription();
  closeTasksAtOrAbove(1, lines.length + 1);

  const attachSourceRoot = (tasks: Task[]) => {
    for (const task of tasks) {
      if (options.sourcePath) {
        task.sourceRoot = root;
        task.sourceContent = sourceContent;
      }
      attachSourceRoot(task.children);
    }
  };
  attachSourceRoot(root);

  return { tasks: root, fileImports };
}

/**
 * Serialize a task tree back to org-mode text.
 *
 * Top-level tasks are separated by a blank line for readability.
 * Descriptions are emitted verbatim (preserving indentation/blanks the
 * parser stripped from the edges is acceptable: the parser trims only
 * leading and trailing blank lines).
 */
export function serializeTasks(tasks: Task[]): string {
  const lines: string[] = [];

  const write = (taskList: Task[], topLevel: boolean) => {
    for (let i = 0; i < taskList.length; i++) {
      const t = taskList[i]!;
      if (topLevel && i > 0) lines.push("");
      const stars = "*".repeat(t.level);
      const prio = t.priority ? ` [#${t.priority}]` : "";
      const tags = t.tags.length > 0 ? ` :${t.tags.join(":")}:` : "";
      lines.push(`${stars} ${t.status}${prio} ${t.summary}${tags}`);
      if (t.closed) {
        lines.push(`CLOSED: [${t.closed}]`);
      }
      const propertyLines = [...t.propertyLines];
      if (propertyLines.length > 0) {
        lines.push(":PROPERTIES:");
        lines.push(...propertyLines);
        lines.push(":END:");
      }
      if (t.importPath) {
        lines.push(`#+IMPORT: ${t.importRaw ?? t.importPath}`);
      }
      if (t.description) {
        lines.push(t.description);
      }
      write(t.children, false);
    }
  };

  write(tasks, true);
  return lines.join("\n") + "\n";
}

/** Serialize a single task subtree without forcing a trailing newline. */
function serializeTaskBlock(task: Task): string[] {
  return serializeTasks([task]).replace(/\n$/, "").split("\n");
}

/** Original line range occupied by a parsed task subtree. */
function taskRange(task: Task): { start: number; end: number } {
  const start = Math.max(0, task.lineNumber - 1);
  const end = Math.max(start + 1, task.endLine - 1);
  return { start, end };
}

/**
 * Serialize root tasks back into their original org file while preserving
 * content outside task subtrees: metadata/preamble, category headings, plan
 * sections, prose notes, and other non-task org content.
 *
 * Existing root tasks are replaced in-place by their original line number.
 * Existing root tasks omitted from `tasks` are removed (used by archiving).
 * New root tasks with no parsed line number are appended to the end of the file.
 */
export function serializeTasksPreservingFile(
  originalContent: string,
  tasks: Task[],
): string {
  const lines = originalContent.split("\n");
  const { tasks: originalRoots } = parseTasks(originalContent);
  const suppliedByLine = new Map<number, Task>();
  const newRoots: Task[] = [];

  for (const task of tasks) {
    if (task.lineNumber > 0) {
      suppliedByLine.set(task.lineNumber, task);
    } else {
      newRoots.push(task);
    }
  }

  const edits: { start: number; end: number; replacement: string[] }[] = [];

  for (const original of originalRoots) {
    const supplied = suppliedByLine.get(original.lineNumber);
    const range = taskRange(original);
    edits.push({
      ...range,
      replacement: supplied ? serializeTaskBlock(supplied) : [],
    });
  }

  // Apply from the bottom up so earlier line ranges remain stable.
  edits
    .sort((a, b) => b.start - a.start)
    .forEach(({ start, end, replacement }) => {
      lines.splice(start, end - start, ...replacement);
    });

  for (const task of newRoots) {
    while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
    if (lines.length > 0) lines.push("");
    lines.push(...serializeTaskBlock(task));
  }

  return lines.join("\n").replace(/\n*$/, "\n");
}
