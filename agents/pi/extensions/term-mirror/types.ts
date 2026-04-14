/**
 * Shared types and utilities for the term-mirror extension backends.
 */

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
 */
export interface MirrorBackend {
  readonly label: string;

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

  /** Capture terminal content (scrollback). */
  capturePane(lines?: number): Promise<string>;

  /** Get the pane's current working directory. */
  getPaneCwd(): Promise<string>;

  /** Send literal text to the pane (no Enter). */
  sendText(text: string): Promise<void>;

  /** Send Enter key to the pane. */
  sendEnter(): Promise<void>;

  /** Send Ctrl+C to the pane. */
  sendCtrlC(): Promise<void>;

  /** Get the shell name running in the pane. */
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

  /** Capture output from a tab. */
  captureTab(targetId: string, lines?: number): Promise<string>;

  /** Send literal text to a tab (no Enter). */
  sendTextToTab(targetId: string, text: string): Promise<void>;

  /** Send Enter key to a tab. */
  sendEnterToTab(targetId: string): Promise<void>;

  /** Send Ctrl+C to a tab. */
  sendCtrlCToTab(targetId: string): Promise<void>;

  /** Close/kill a tab. */
  closeTab(targetId: string): Promise<void>;

  /** Check if a tab is still alive. */
  isTabAlive(targetId: string): Promise<boolean>;
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
