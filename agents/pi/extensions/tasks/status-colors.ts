/**
 * Canonical ANSI colors for task status.
 *
 * Applied consistently in the /tasks overlay and the persistent selection
 * header. Uses direct ANSI escape codes (not theme keys) so the palette is
 * fixed regardless of the active theme.
 *
 *   TODO     → yellow  (\x1b[33m)
 *   WAITING  → orange  (\x1b[38;5;208m, 256-color)
 *   STARTED  → blue    (\x1b[34m)
 *   DONE     → green   (\x1b[32m)
 *
 * Note: the codebase uses STARTED as the token for an in-progress task.
 * If it's later renamed to IN-PROGRESS, update the keys here in lockstep.
 */

const RESET = "\x1b[0m";

export const STATUS_ANSI: Record<string, string> = {
  TODO: "\x1b[33m",
  WAITING: "\x1b[38;5;208m",
  STARTED: "\x1b[34m",
  DONE: "\x1b[32m",
};

/**
 * Return a status token (padded to 7 chars) wrapped in its canonical color.
 * Pass `text` to color arbitrary content (e.g. a descriptive label) with the
 * same hue.
 */
export function colorStatus(status: string, text?: string): string {
  const body = text ?? status.padEnd(7);
  const open = STATUS_ANSI[status];
  if (!open) return body;
  return `${open}${body}${RESET}`;
}
