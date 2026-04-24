/**
 * Canonical ANSI colors for task metadata.
 *
 * Applied consistently in the /tasks overlay and the persistent pinned overlay.
 * Uses direct ANSI escape codes (not theme keys) so the palette is fixed
 * regardless of the active theme.
 */

const RESET = "\x1b[0m";
const DIM = "\x1b[2m";
const ITALIC = "\x1b[3m";

const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const BLUE = "\x1b[34m";
const MAGENTA = "\x1b[35m";
const ORANGE = "\x1b[38;5;208m";

export const STATUS_ANSI: Record<string, string> = {
  TODO: YELLOW,
  WAITING: ORANGE,
  STARTED: BLUE,
  DONE: GREEN,
};

export const PRIORITY_ANSI: Record<string, string> = {
  A: ORANGE,
  B: YELLOW,
  C: GREEN,
  D: BLUE,
};

function color(open: string | undefined, text: string): string {
  if (!open) return text;
  return `${open}${text}${RESET}`;
}

/**
 * Return a status token (padded to 7 chars) wrapped in its canonical color.
 * Pass `text` to color arbitrary content with the same hue.
 */
export function colorStatus(status: string, text?: string): string {
  return color(STATUS_ANSI[status], text ?? status.padEnd(7));
}

/** Return an org priority token wrapped in its canonical color. */
export function colorPriority(priority: string | null): string {
  if (!priority) return "";
  return color(PRIORITY_ANSI[priority], `[#${priority}]`);
}

/** Return a visibly tag-styled token, distinct from title text. */
export function colorTags(tags: string[]): string {
  if (tags.length === 0) return "";
  return `${DIM}${ITALIC}${MAGENTA}:${tags.join(":")}:${RESET}`;
}
