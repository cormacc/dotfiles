/**
 * Org-mode TASKS.org parser.
 *
 * Parses headings of the form:
 *   * STATUS [#PRIORITY] Summary text :tag1:tag2:
 *
 * Valid status tokens: TODO, STARTED, WAITING, DONE
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
  /** Optional relative path to an org file containing a detailed plan. */
  planPath: string | null;
  /** Parsed plan tasks, injected at render time as children of this task. */
  planChildren?: Task[];
  /** Absolute path of the source org file this task came from. */
  sourcePath?: string;
  /** Root task tree for sourcePath, used to save linked plan files. */
  sourceRoot?: Task[];
  /** 1-indexed line number of the heading in the source file. */
  lineNumber: number;
}

/** Matches any org heading: `* ...`, `** ...`, etc. */
const ANY_HEADING_RE = /^(\*+)\s+(.*)$/;

const HEADING_RE =
  /^(\*+)\s+(TODO|STARTED|WAITING|DONE)\s+(?:\[#([A-Z])\]\s+)?(.+)$/;

const PROPERTIES_START_RE = /^\s*:PROPERTIES:\s*$/i;
const PROPERTIES_END_RE = /^\s*:END:\s*$/i;
const PLAN_PROPERTY_RE = /^\s*:PLAN:\s*(.*?)\s*$/i;

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

export interface ParseTasksOptions {
  /** Absolute path of the file being parsed. */
  sourcePath?: string;
}

/**
 * Parse the full content of a TASKS.org file into a task tree.
 */
export function parseTasks(
  content: string,
  options: ParseTasksOptions = {},
): Task[] {
  const lines = content.split("\n");
  const root: Task[] = [];

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

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;
    const heading = parseHeading(line);

    if (heading) {
      // Flush any accumulated description for the previous task
      flushDescription();

      const task: Task = {
        level: heading.level,
        status: heading.status,
        priority: heading.priority,
        summary: heading.summary,
        tags: heading.tags,
        description: "",
        children: [],
        propertyLines: [],
        planPath: null,
        sourcePath: options.sourcePath,
        lineNumber: i + 1,
      };

      // Pop stack until we find a parent with a lower level
      while (
        stack.length > 0 &&
        stack[stack.length - 1]!.level >= heading.level
      ) {
        stack.pop();
      }

      if (stack.length === 0) {
        // Top-level task
        root.push(task);
      } else {
        // Child of the task on top of stack
        stack[stack.length - 1]!.task.children.push(task);
      }

      stack.push({ task, level: heading.level });
      currentTask = task;
    } else if (currentTask && PROPERTIES_START_RE.test(line)) {
      // Org properties drawer immediately below a heading. Currently we
      // consume only :PLAN:, but skip the whole drawer so it doesn't become
      // part of the task description.
      for (i = i + 1; i < lines.length; i++) {
        const propLine = lines[i]!;
        if (PROPERTIES_END_RE.test(propLine)) break;
        const plan = PLAN_PROPERTY_RE.exec(propLine);
        if (plan) {
          currentTask.planPath = plan[1]!.trim() || null;
        } else {
          currentTask.propertyLines.push(propLine);
        }
      }
    } else if (ANY_HEADING_RE.test(line)) {
      // Non-task heading (e.g. `* Notes`) — flush the current task's
      // description and stop attributing subsequent lines to it, so
      // unrelated content below isn't swallowed into the previous task.
      flushDescription();
      currentTask = null;
    } else {
      // Non-heading line: accumulate as description for current task
      if (currentTask) {
        descriptionLines.push(line);
      }
    }
  }

  // Flush description for the last task
  flushDescription();

  const attachSourceRoot = (tasks: Task[]) => {
    for (const task of tasks) {
      if (options.sourcePath) {
        task.sourceRoot = root;
      }
      attachSourceRoot(task.children);
    }
  };
  attachSourceRoot(root);

  return root;
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
      const propertyLines = [...t.propertyLines];
      if (t.planPath) propertyLines.push(`:PLAN: ${t.planPath}`);
      if (propertyLines.length > 0) {
        lines.push(":PROPERTIES:");
        lines.push(...propertyLines);
        lines.push(":END:");
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
