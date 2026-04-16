/**
 * Shared types and utilities for the term extension backends.
 */
import { unlinkSync, readFileSync, writeFileSync, statSync } from "node:fs";

export type ExecFn = (
  cmd: string,
  args: string[],
  opts?: { timeout?: number },
) => Promise<{
  stdout: string;
  stderr: string;
  code: number | null;
  killed?: boolean;
}>;

/**
 * Backend interface for terminal multiplexer integrations.
 * Implemented by TmuxBackend and SwayBackend.
 *
 * The main pane is exposed as `mainTargetId` — all I/O methods
 * (`capture`, `sendText`, `sendEnter`, `sendCtrlC`) accept a target ID,
 * unifying main-pane and tab operations.
 */
export interface MirrorBackend {
  readonly label: string;

  /** Target ID of the main shell pane. */
  readonly mainTargetId: string;

  /** Create or reuse a terminal pane. Returns true if pane is ready. */
  ensurePane(): Promise<boolean>;

  /** Check if the current pane is still alive. */
  paneAlive(): Promise<boolean>;

  /** Whether the pane is ready for commands. */
  isPaneReady(): boolean;

  /**
   * Reset backend-specific state (pane lost).
   * Also invokes the onReset callback to reset shared state (e.g. hookInstalled).
   */
  resetState(): Promise<void>;

  /** Human-readable pane identifier for display. */
  displayTarget(): string;

  /** Capture terminal content (scrollback) for any target. */
  capture(targetId: string, lines?: number): Promise<string>;

  /** Get the main pane's current working directory. */
  getPaneCwd(): Promise<string>;

  /** Send literal text to a target (no Enter). */
  sendText(targetId: string, text: string): Promise<void>;

  /** Send Enter key to a target. */
  sendEnter(targetId: string): Promise<void>;

  /** Send Ctrl+C to a target. */
  sendCtrlC(targetId: string): Promise<void>;

  /** Get the shell name running in the main pane. */
  getShellName(): Promise<string>;

  /**
   * Generate the shell hook code for the given shell.
   * Includes env setup, seq tracking, and precmd/PROMPT_COMMAND registration.
   */
  generateHookCode(shell: string): string;

  /** Clear RC state and prepare for hook installation (e.g. recreate FIFO). */
  prepareForHook(): Promise<void>;

  /** Read the current sequence number and exit code. */
  readRc(): Promise<{ seq: number; rc: number }>;

  /** Block until the shell signals prompt ready (activity loop channel). Returns true if signaled. */
  waitForPrompt(timeoutMs: number): Promise<boolean>;

  /** Block until the shell signals prompt ready (agent-exclusive channel). Returns true if signaled. */
  waitForAgentSignal(timeoutMs: number): Promise<boolean>;

  /** Block until all precmd functions (including direnv etc.) have completed. */
  waitForReady(timeoutMs: number): Promise<boolean>;

  /** Unblock pending waitForPrompt and waitForAgentSignal. */
  unblockWait(): Promise<void>;

  /** Kill the main mirror pane. */
  killPane(): Promise<void>;

  /** Clean up temp files etc. on shutdown. */
  cleanup(): void;

  // ── tab management (for long-running processes) ──────

  /** Create a new tab with the given name. Returns the tab target ID, or null on failure. */
  createTab(name: string): Promise<string | null>;

  /** Close/kill a tab. */
  closeTab(targetId: string): Promise<void>;

  /** Check if a tab is still alive. */
  isTabAlive(targetId: string): Promise<boolean>;

  // ── visibility & focus (eliminates backend casts) ────

  /** Hide the mirror area (pane + tabs). */
  hide(): Promise<void>;

  /** Show the mirror area. tabTargetIds are process tab IDs to also restore. */
  show(tabTargetIds?: string[]): Promise<void>;

  /** Switch the visible tab/pane in the mirror area. null = main shell. */
  switchTab(
    fromTargetId: string | null,
    toTargetId: string | null,
  ): Promise<void>;

  /** Recover the shell pane to the mirror slot (e.g. after a process tab dies). */
  recoverShellToMirror(): Promise<void>;
}

/** A long-running process managed in its own tab. */
export interface ManagedProcess {
  name: string;
  command: string;
  targetId: string; // backend-specific tab/window ID
  mode: "watch" | "quiet";
  lastSnapshot: string; // for diffing
  startedAt: number;
}

/** Default height of the mirror pane as a percentage of screen height. */
export const DEFAULT_PANE_HEIGHT_PCT = 25;

/** Shell-quote a string with single quotes. */
export const sq = (s: string): string => `'${s.replace(/'/g, "'\\''")}'`;

/** Sanitize a process/tab name to safe alphanumeric + dash/underscore. */
export function sanitizeName(name: string): string {
  return name.replace(/[^a-zA-Z0-9_-]/g, "-").slice(0, 32) || "process";
}

/** Promise-based sleep. */
export const sleep = (ms: number): Promise<void> =>
  new Promise<void>((r) => setTimeout(r, ms));

/** Silently unlink multiple files, ignoring errors. */
export function unlinkAll(...paths: string[]): void {
  for (const f of paths) {
    try {
      unlinkSync(f);
    } catch {}
  }
}

/**
 * Compute a line-level diff between two snapshots.
 * Returns the new lines after the common prefix, trimmed.
 */
export function diffSnapshots(before: string, after: string): string {
  const bLines = before.split("\n");
  const aLines = after.split("\n");
  let i = 0;
  while (i < bLines.length && i < aLines.length && bLines[i] === aLines[i]) i++;
  return aLines.slice(i).join("\n").trim();
}

/** ANSI escape stripping regex (shared between sway log readers). */
const ANSI_RE =
  // eslint-disable-next-line no-control-regex
  /\x1b\[[0-9;?]*[a-zA-Z><=]|\x1b[=>]|\x1b\].*?(?:\x07|\x1b\\)|\x1b[()][0-9A-B]|\r/g;

/**
 * Read a PTY output log file, strip ANSI escapes, return the last N lines.
 * Automatically trims the file if it exceeds maxSize bytes.
 */
export function readLogFile(
  logPath: string,
  lines: number,
  maxSize = 500_000,
): string {
  try {
    const raw = readFileSync(logPath, "utf-8");
    const clean = raw.replace(ANSI_RE, "");
    const allLines = clean.split("\n");
    const result = allLines.slice(-lines).join("\n");

    try {
      const stat = statSync(logPath);
      if (stat.size > maxSize) {
        const keep = raw.slice(-Math.floor(maxSize / 2));
        writeFileSync(logPath, keep);
      }
    } catch {}

    return result;
  } catch {
    return "";
  }
}

/**
 * Generate shell hook code for prompt detection.
 * Both backends use identical hook structure — only the signaling
 * mechanism differs (tmux wait-for vs FIFO echo).
 */
export function generateShellHook(
  shell: string,
  opts: {
    rcWrite: string; // e.g. 'tmux set-environment PI_LAST_RC "$((++__pi_seq)) $rc"'
    signalPrompt: string; // e.g. 'tmux wait-for -S pi-prompt 2>/dev/null'
    signalAgent: string; // e.g. 'tmux wait-for -S pi-agent-prompt 2>/dev/null'
    signalReady: string; // e.g. 'tmux wait-for -S pi-ready 2>/dev/null'
  },
): string {
  const envSetup = `export PAGER=cat GIT_PAGER=cat`;

  if (shell.includes("zsh")) {
    return [
      envSetup,
      `typeset -gi __pi_seq=0`,
      `__pi_precmd() { local rc=$?; ${opts.rcWrite}; ${opts.signalPrompt}; ${opts.signalAgent}; return $rc; }`,
      `__pi_ready() { ${opts.signalReady}; }`,
      `precmd_functions=(__pi_precmd $precmd_functions __pi_ready)`,
    ].join("; ");
  } else {
    return [
      envSetup,
      `__pi_seq=0`,
      `__pi_pcmd() { local rc=$?; ${opts.rcWrite}; ${opts.signalPrompt}; ${opts.signalAgent}; return $rc; }`,
      `__pi_rdy() { ${opts.signalReady}; }`,
      `PROMPT_COMMAND="__pi_pcmd;\${PROMPT_COMMAND};__pi_rdy"`,
    ].join("; ");
  }
}
