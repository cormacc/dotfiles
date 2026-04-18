/**
 * Kitty backend for the term extension.
 *
 * Uses kitty's remote control protocol (`kitten @`) for window management,
 * text I/O, and capture. Signals via named pipe FIFOs (like the sway backend).
 * State is stored in temp files (UUID-scoped per session).
 *
 * Requirements:
 *   - Must run pi inside a kitty window with `allow_remote_control` enabled
 *     (detected via $KITTY_WINDOW_ID).
 *   - `kitten` CLI must be available.
 *   - The shell must be zsh or bash.
 *
 * Architecture:
 *   - The main mirror pane is a kitty window (hsplit) in the same tab as pi.
 *   - Process windows are launched as separate kitty tabs (`--type=tab`).
 *     When the user switches to a process, `detach-window` moves it into
 *     pi's tab (swapping with the current bottom window), so only one
 *     bottom window is ever visible at a time — no split accumulation.
 *     capture/sendText work cross-tab via `kitten @ ... --match id:X`.
 *   - Text injection via `kitten @ send-text`.
 *   - Capture via `kitten @ get-text --extent all`.
 *   - Signaling via named pipe FIFOs (zero CPU blocking, like sway).
 *   - Exit code tracking via temp file written by shell hook.
 */
import type { ExecFn, MirrorBackend } from "./types.js";
import {
  sq,
  sleep,
  unlinkAll,
  generateShellHook,
} from "./types.js";
import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";

export class KittyBackend implements MirrorBackend {
  readonly label = "kitty";

  private windowId = 0; // kitty window ID of the mirror pane
  private piWindowId = 0; // kitty window ID of pi's own window
  private piTabId = 0; // kitty tab ID containing pi
  private paneReady = false;
  private exec: ExecFn;
  private onReset?: () => void;

  private readonly sessionId: string;
  private readonly rcFile: string;
  private readonly signalFifo: string;
  private readonly agentSignalFifo: string;
  private readonly readyFifo: string;

  /** Managed process tabs keyed by targetId (string window ID). */
  private tabs = new Map<string, { windowId: number }>();

  /** Window ID of the currently active bottom-area window (mirror or process). */
  private activeBottomWindowId = 0;

  get mainTargetId(): string {
    return String(this.windowId);
  }

  constructor(exec: ExecFn, onReset?: () => void) {
    this.exec = exec;
    this.onReset = onReset;
    this.sessionId = randomUUID().slice(0, 8);
    this.rcFile = `/tmp/pi-mirror-rc-${this.sessionId}`;
    this.signalFifo = `/tmp/pi-mirror-signal-${this.sessionId}`;
    this.agentSignalFifo = `/tmp/pi-mirror-agent-signal-${this.sessionId}`;
    this.readyFifo = `/tmp/pi-mirror-ready-${this.sessionId}`;
    this.piWindowId = parseInt(process.env.KITTY_WINDOW_ID || "0", 10);
  }

  // ── kitty primitives ───────────────────────────────────

  private async kitten(
    ...args: string[]
  ): Promise<{ stdout: string; code: number }> {
    const r = await this.exec("kitten", ["@", ...args], { timeout: 5000 });
    return { stdout: r.stdout, code: r.code ?? 1 };
  }

  /**
   * Parse the kitty window tree from `kitten @ ls`.
   * Returns the full JSON array of OS windows.
   */
  private async lsTree(): Promise<any[]> {
    const r = await this.kitten("ls");
    if (r.code !== 0) return [];
    try {
      return JSON.parse(r.stdout);
    } catch {
      return [];
    }
  }

  /**
   * Find a kitty window object by its ID in the ls tree.
   * Returns { osWindow, tab, window } or null.
   */
  private async findWindowInTree(
    winId: number,
  ): Promise<{ osWindow: any; tab: any; window: any } | null> {
    const tree = await this.lsTree();
    for (const osWin of tree) {
      for (const tab of osWin.tabs || []) {
        for (const win of tab.windows || []) {
          if (win.id === winId) {
            return { osWindow: osWin, tab, window: win };
          }
        }
      }
    }
    return null;
  }

  // ── tab tracking helpers ────────────────────────────────

  /** Refresh the kitty tab ID that contains pi's window. */
  private async refreshPiTabId(): Promise<void> {
    const tree = await this.lsTree();
    for (const osWin of tree) {
      for (const tab of osWin.tabs || []) {
        for (const win of tab.windows || []) {
          if (win.id === this.piWindowId) {
            this.piTabId = tab.id;
            return;
          }
        }
      }
    }
  }

  /** Check if a kitty window is currently in pi's tab. */
  private async isWindowInPiTab(winId: number): Promise<boolean> {
    if (!this.piTabId) await this.refreshPiTabId();
    const tree = await this.lsTree();
    for (const osWin of tree) {
      for (const tab of osWin.tabs || []) {
        if (tab.id === this.piTabId) {
          for (const win of tab.windows || []) {
            if (win.id === winId) return true;
          }
        }
      }
    }
    return false;
  }

  /**
   * Move a window into pi's tab via detach-window.
   * Uses --target-tab to place it in pi's tab.
   */
  private async bringWindowToPiTab(winId: number): Promise<void> {
    if (await this.isWindowInPiTab(winId)) return;
    if (!this.piTabId) await this.refreshPiTabId();
    if (!this.piTabId) return;

    // Focus pi first so the detached window splits relative to pi
    await this.kitten(
      "focus-window", "--match", `id:${this.piWindowId}`,
    ).catch(() => {});

    await this.kitten(
      "detach-window",
      "--match", `id:${winId}`,
      "--target-tab", `id:${this.piTabId}`,
    ).catch(() => {});
  }

  /**
   * Move a window out of pi's tab to its own tab.
   * Uses detach-window with no --target-tab (creates a new tab).
   */
  private async parkWindow(winId: number): Promise<void> {
    if (!(await this.isWindowInPiTab(winId))) return;
    await this.kitten(
      "detach-window",
      "--match", `id:${winId}`,
    ).catch(() => {});
  }

  /**
   * Resize the bottom window to ~25% of the terminal height.
   * Works because the target is the only non-pi window in pi's tab.
   */
  private async resizeBottomTo25(winId: number): Promise<void> {
    // Minimize first for a consistent starting point
    await this.kitten(
      "resize-window", "--match", `id:${winId}`,
      "--axis=vertical", "--increment=-10000",
    ).catch(() => {});

    let increment = 15;
    try {
      const piInfo = await this.findWindowInTree(this.piWindowId);
      if (piInfo?.window?.lines) {
        increment = Math.max(5, Math.floor(piInfo.window.lines * 0.25));
      }
    } catch {}

    await this.kitten(
      "resize-window", "--match", `id:${winId}`,
      "--axis=vertical", `--increment=${increment}`,
    ).catch(() => {});
  }

  // ── pane lifecycle ─────────────────────────────────────

  async paneAlive(): Promise<boolean> {
    if (this.windowId <= 0) return false;
    const found = await this.findWindowInTree(this.windowId);
    return found !== null;
  }

  isPaneReady(): boolean {
    return this.paneReady;
  }

  async resetState(): Promise<void> {
    this.paneReady = false;
    this.windowId = 0;
    this.piTabId = 0;
    this.activeBottomWindowId = 0;
    this.tabs.clear();
    unlinkAll(
      this.rcFile,
      this.signalFifo,
      this.agentSignalFifo,
      this.readyFifo,
    );
    this.onReset?.();
  }

  displayTarget(): string {
    return `kitty:${this.windowId}`;
  }

  private async waitForShell(
    winId: number,
    timeoutMs = 10000,
  ): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const found = await this.findWindowInTree(winId);
      if (found) {
        const fg = found.window.foreground_processes || [];
        for (const proc of fg) {
          const cmdline = (proc.cmdline || []).join(" ");
          if (/\b(ba|z|fi)sh\b/.test(cmdline)) return true;
        }
      }
      await sleep(500);
    }
    return false;
  }

  async ensurePane(): Promise<boolean> {
    if (this.paneReady && (await this.paneAlive())) return true;

    if (this.paneReady) {
      await this.resetState();
      await sleep(500);
    }

    // Check if pi's own window is still valid
    if (this.piWindowId <= 0) {
      this.piWindowId = parseInt(process.env.KITTY_WINDOW_ID || "0", 10);
    }

    // Check if our old mirror window still exists
    if (this.windowId > 0) {
      if (await this.paneAlive()) {
        if (await this.waitForShell(this.windowId)) {
          this.activeBottomWindowId = this.windowId;
          this.paneReady = true;
          return true;
        }
      }
      this.windowId = 0;
    }

    // Launch a new split window below the current window.
    // --location=hsplit creates a horizontal split (top/bottom layout).
    // Requires the "splits" layout to be enabled in kitty.conf, or we
    // fall back to a plain window launch (uses whatever layout is active).
    const r = await this.kitten(
      "launch",
      "--type=window",
      "--keep-focus",
      "--location=hsplit",
      "--title=pi-mirror",
      `--env=PI_MIRROR_SESSION=${this.sessionId}`,
    );

    let winId = 0;
    if (r.code === 0) {
      winId = parseInt(r.stdout.trim(), 10);
    }

    if (!winId || isNaN(winId)) {
      // Fallback: try without --location (works with any layout)
      const r2 = await this.kitten(
        "launch",
        "--type=window",
        "--keep-focus",
        "--title=pi-mirror",
        `--env=PI_MIRROR_SESSION=${this.sessionId}`,
      );
      // Note: fallback won't produce hsplit; placement depends on active layout
      if (r2.code !== 0) return false;
      winId = parseInt(r2.stdout.trim(), 10);
      if (!winId || isNaN(winId)) return false;
    }

    this.windowId = winId;

    if (!(await this.waitForShell(this.windowId))) {
      await this.kitten(
        "close-window",
        "--match",
        `id:${this.windowId}`,
      );
      this.windowId = 0;
      return false;
    }

    this.activeBottomWindowId = this.windowId;
    this.paneReady = true;

    // Record pi's tab ID for later detach-window operations
    await this.refreshPiTabId();

    return true;
  }

  // ── unified I/O (main pane + tabs) ─────────────────────

  async capture(targetId: string, lines = 2000): Promise<string> {
    // `kitten @ get-text` with --extent=all gets screen + scrollback.
    // We then take the last N lines.
    const r = await this.kitten(
      "get-text",
      "--match",
      `id:${targetId}`,
      "--extent",
      "all",
    );
    if (r.code !== 0) return "";
    const allLines = r.stdout.split("\n");
    return allLines.slice(-lines).join("\n");
  }

  async getPaneCwd(): Promise<string> {
    const found = await this.findWindowInTree(this.windowId);
    if (found?.window?.cwd) return found.window.cwd;
    return process.cwd();
  }

  async sendText(targetId: string, text: string): Promise<void> {
    // Use --stdin to send raw text, avoiding kitten's Python escape
    // interpretation which would mangle backslashes etc.
    await this.exec(
      "bash",
      [
        "-c",
        `printf '%s' ${sq(text)} | kitten @ send-text --match id:${targetId} --stdin`,
      ],
      { timeout: 5000 },
    );
  }

  async sendEnter(targetId: string): Promise<void> {
    // \r is interpreted as a Python escape by send-text (carriage return)
    await this.kitten(
      "send-text",
      "--match",
      `id:${targetId}`,
      "\\r",
    );
  }

  async sendCtrlC(targetId: string): Promise<void> {
    await this.kitten(
      "send-text",
      "--match",
      `id:${targetId}`,
      "\\x03",
    );
  }

  async getShellName(): Promise<string> {
    const found = await this.findWindowInTree(this.windowId);
    if (!found) return "";
    const fg = found.window.foreground_processes || [];
    for (const proc of fg) {
      const cmdline = (proc.cmdline || []).join(" ");
      const match = cmdline.match(/\b(bash|zsh|fish)\b/);
      if (match) return match[1];
    }
    return "";
  }

  // ── hook & signaling ───────────────────────────────────

  generateHookCode(shell: string): string {
    return generateShellHook(shell, {
      rcWrite: `echo "$((++__pi_seq)) $rc" > ${this.rcFile}`,
      signalPrompt: `(echo > ${this.signalFifo} &) 2>/dev/null`,
      signalAgent: `(echo > ${this.agentSignalFifo} &) 2>/dev/null`,
      signalReady: `(echo > ${this.readyFifo} &) 2>/dev/null`,
    });
  }

  async prepareForHook(): Promise<void> {
    unlinkAll(
      this.rcFile,
      this.signalFifo,
      this.agentSignalFifo,
      this.readyFifo,
    );
    await this.exec("mkfifo", [this.signalFifo], { timeout: 2000 });
    await this.exec("mkfifo", [this.agentSignalFifo], { timeout: 2000 });
    await this.exec("mkfifo", [this.readyFifo], { timeout: 2000 });
  }

  async readRc(): Promise<{ seq: number; rc: number }> {
    try {
      const val = readFileSync(this.rcFile, "utf-8").trim();
      if (!val) return { seq: 0, rc: 0 };
      const [s, r] = val.split(" ");
      return { seq: parseInt(s, 10) || 0, rc: parseInt(r, 10) || 0 };
    } catch {
      return { seq: 0, rc: 0 };
    }
  }

  private async waitForFifo(
    fifoPath: string,
    timeoutMs: number,
  ): Promise<boolean> {
    try {
      const r = await this.exec("cat", [fifoPath], { timeout: timeoutMs });
      return r.code === 0;
    } catch {
      return false;
    }
  }

  async waitForPrompt(timeoutMs: number): Promise<boolean> {
    return this.waitForFifo(this.signalFifo, timeoutMs);
  }

  async waitForAgentSignal(timeoutMs: number): Promise<boolean> {
    return this.waitForFifo(this.agentSignalFifo, timeoutMs);
  }

  async waitForReady(timeoutMs: number): Promise<boolean> {
    return this.waitForFifo(this.readyFifo, timeoutMs);
  }

  async unblockWait(): Promise<void> {
    await this.exec(
      "bash",
      [
        "-c",
        `(echo > ${this.signalFifo} &; echo > ${this.agentSignalFifo} &; echo > ${this.readyFifo} &) 2>/dev/null`,
      ],
      { timeout: 2000 },
    ).catch(() => {});
  }

  async killPane(): Promise<void> {
    if (this.windowId > 0) {
      await this.kitten(
        "close-window",
        "--match",
        `id:${this.windowId}`,
      ).catch(() => {});
      this.windowId = 0;
      this.paneReady = false;
    }
  }

  cleanup(): void {
    unlinkAll(
      this.rcFile,
      this.signalFifo,
      this.agentSignalFifo,
      this.readyFifo,
    );
  }

  // ── tab management ─────────────────────────────────────

  async createTab(name: string): Promise<string | null> {
    // Launch process in a separate kitty tab (not a split in pi's tab).
    // This avoids the split-accumulation problem where each new process
    // adds a visible sliver due to kitty's minimum window height.
    const r = await this.kitten(
      "launch",
      "--type=tab",
      "--keep-focus",
      `--title=${name}`,
    );
    if (r.code !== 0) return null;

    const winId = parseInt(r.stdout.trim(), 10);
    if (!winId || isNaN(winId)) return null;

    const targetId = String(winId);
    this.tabs.set(targetId, { windowId: winId });
    return targetId;
  }

  async closeTab(targetId: string): Promise<void> {
    const tab = this.tabs.get(targetId);
    if (!tab) return;
    await this.kitten(
      "close-window",
      "--match",
      `id:${tab.windowId}`,
    ).catch(() => {});
    this.tabs.delete(targetId);
    if (this.activeBottomWindowId === tab.windowId) {
      this.activeBottomWindowId = this.windowId;
    }
  }

  async isTabAlive(targetId: string): Promise<boolean> {
    const tab = this.tabs.get(targetId);
    if (!tab) return false;
    const found = await this.findWindowInTree(tab.windowId);
    return found !== null;
  }

  // ── visibility & focus ─────────────────────────────────

  async hide(): Promise<void> {
    // Minimize whichever bottom window is currently in pi's tab
    const activeId = this.activeBottomWindowId || this.windowId;
    if (activeId > 0) {
      await this.kitten(
        "resize-window",
        "--match",
        `id:${activeId}`,
        "--axis=vertical",
        "--increment=-10000",
      ).catch(() => {});
    }
  }

  async show(_tabTargetIds?: string[]): Promise<void> {
    const activeId = this.activeBottomWindowId || this.windowId;
    if (activeId <= 0) return;

    // Ensure the correct window is in pi's tab.
    // Park any stale non-pi, non-active windows first.
    if (this.piTabId) {
      const tree = await this.lsTree();
      for (const osWin of tree) {
        for (const tab of osWin.tabs || []) {
          if (tab.id === this.piTabId) {
            for (const win of tab.windows || []) {
              if (win.id !== this.piWindowId && win.id !== activeId) {
                await this.parkWindow(win.id);
              }
            }
          }
        }
      }
    }

    // Bring the active window into pi's tab if needed
    if (!(await this.isWindowInPiTab(activeId))) {
      await this.bringWindowToPiTab(activeId);
    }

    // Resize to ~25%
    await this.resizeBottomTo25(activeId);

    // Ensure pi stays focused
    await this.kitten(
      "focus-window", "--match", `id:${this.piWindowId}`,
    ).catch(() => {});
  }

  async switchTab(
    _fromTargetId: string | null,
    toTargetId: string | null,
  ): Promise<void> {
    const toWinId =
      toTargetId === null
        ? this.windowId
        : (this.tabs.get(toTargetId)?.windowId ?? this.windowId);

    // Always update tracking
    const prevActiveId = this.activeBottomWindowId;
    this.activeBottomWindowId = toWinId;

    if (toWinId === prevActiveId) return;

    // Check if the previous active window is in pi's tab (= mirror area is populated)
    const prevInPiTab = prevActiveId > 0 && (await this.isWindowInPiTab(prevActiveId));
    if (!prevInPiTab) {
      // Mirror is hidden or prev window isn't in pi's tab — just a tracking update.
      // The actual swap will happen when show() is called.
      return;
    }

    // Detect whether the current bottom area is visible or minimized
    const prevInfo = await this.findWindowInTree(prevActiveId);
    const isMinimized = prevInfo?.window?.lines != null && prevInfo.window.lines <= 2;

    // Swap: park the current bottom window, bring in the target
    await this.parkWindow(prevActiveId);
    await this.bringWindowToPiTab(toWinId);

    // Restore the same visibility state
    if (!isMinimized) {
      await this.resizeBottomTo25(toWinId);
    } else {
      await this.kitten(
        "resize-window", "--match", `id:${toWinId}`,
        "--axis=vertical", "--increment=-10000",
      ).catch(() => {});
    }

    // Ensure pi stays focused
    await this.kitten(
      "focus-window", "--match", `id:${this.piWindowId}`,
    ).catch(() => {});
  }

  async recoverShellToMirror(): Promise<void> {
    // If mirror is not in pi's tab, bring it back
    if (!(await this.isWindowInPiTab(this.windowId))) {
      // Park whatever is currently there
      const currentBottom = this.activeBottomWindowId;
      if (currentBottom > 0 && currentBottom !== this.windowId) {
        await this.parkWindow(currentBottom).catch(() => {});
      }
      await this.bringWindowToPiTab(this.windowId);
    }
    this.activeBottomWindowId = this.windowId;
    if (this.piWindowId > 0) {
      await this.kitten(
        "focus-window",
        "--match",
        `id:${this.piWindowId}`,
      );
    }
  }

  async focusPane(targetId?: string | null): Promise<void> {
    // Determine which window to focus
    let winId = this.windowId;
    if (targetId) {
      const tab = this.tabs.get(targetId);
      if (tab) winId = tab.windowId;
    }

    // Ensure it's in pi's tab before focusing
    if (!(await this.isWindowInPiTab(winId))) {
      const currentBottom = this.activeBottomWindowId || this.windowId;
      if (currentBottom !== winId && (await this.isWindowInPiTab(currentBottom))) {
        await this.parkWindow(currentBottom);
      }
      await this.bringWindowToPiTab(winId);
      await this.resizeBottomTo25(winId);
      this.activeBottomWindowId = winId;
    }

    if (winId > 0) {
      await this.kitten(
        "focus-window",
        "--match",
        `id:${winId}`,
      );
    }
  }
}
