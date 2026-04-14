/**
 * Ghostty backend for the term-mirror extension (macOS only).
 *
 * Uses Ghostty's AppleScript API (`Ghostty.sdef`) for terminal control:
 *   - `split` to create a split pane
 *   - `input text` to send text (like paste)
 *   - `send key` for Enter, Ctrl+C, etc.
 *   - `perform action "write_screen_file:copy"` to capture terminal content
 *   - `focus` to switch focus between terminals
 *
 * Screen capture works by having Ghostty write scrollback to a temp file and
 * copy the path to the clipboard. The clipboard is saved/restored around each
 * capture to avoid losing user data.
 *
 * Signaling uses named pipes (FIFOs), same as the kitty backend.
 * State is stored in temp files scoped by session UUID.
 *
 * Requirements:
 *   - macOS (AppleScript is macOS-only)
 *   - Ghostty 1.1.0+ (for AppleScript support)
 */
import type { ExecFn, MirrorBackend } from "./types.js";
import { sq, sleep } from "./types.js";
import { writeFileSync, readFileSync, unlinkSync } from "node:fs";
import { randomUUID } from "node:crypto";

export class GhosttyBackend implements MirrorBackend {
  readonly label = "ghostty";

  private terminalId = ""; // the split (mirror) terminal
  private agentTerminalId = ""; // our own terminal
  private paneReady = false;
  private exec: ExecFn;
  private onReset?: () => void;

  private readonly sessionId: string;
  private readonly rcFile: string;
  private readonly signalFifo: string;
  private readonly readyFifo: string;
  private readonly paneIdFile: string;
  private readonly clipBackupFile: string;

  constructor(exec: ExecFn, onReset?: () => void) {
    this.exec = exec;
    this.onReset = onReset;
    this.sessionId = randomUUID().slice(0, 8);
    this.rcFile = `/tmp/pi-mirror-rc-${this.sessionId}`;
    this.signalFifo = `/tmp/pi-mirror-signal-${this.sessionId}`;
    this.readyFifo = `/tmp/pi-mirror-ready-${this.sessionId}`;
    this.paneIdFile = `/tmp/pi-mirror-ghostty-pane`;
    this.clipBackupFile = `/tmp/pi-mirror-clip-${this.sessionId}`;
  }

  // ── AppleScript helpers ────────────────────────────────

  private async osascript(
    script: string,
  ): Promise<{ stdout: string; code: number }> {
    const r = await this.exec("osascript", ["-e", script], { timeout: 10000 });
    return { stdout: r.stdout, code: r.code ?? 1 };
  }

  /** Run an AppleScript snippet inside `tell application "Ghostty"`. */
  private async ghostty(body: string): Promise<string> {
    const r = await this.osascript(
      `tell application "Ghostty"\n${body}\nend tell`,
    );
    return r.stdout.trim();
  }

  // ── pane lifecycle ─────────────────────────────────────

  private async checkTerminalAlive(id: string): Promise<boolean> {
    if (!id) return false;
    try {
      const r = await this.ghostty(`exists terminal id "${id}"`);
      return r === "true";
    } catch {
      return false;
    }
  }

  async paneAlive(): Promise<boolean> {
    return this.checkTerminalAlive(this.terminalId);
  }

  isPaneReady(): boolean {
    return this.paneReady;
  }

  async resetState(): Promise<void> {
    this.paneReady = false;
    this.terminalId = "";
    for (const f of [this.rcFile, this.signalFifo, this.readyFifo]) {
      try {
        unlinkSync(f);
      } catch {}
    }
    this.onReset?.();
  }

  displayTarget(): string {
    return `ghostty:${this.terminalId.slice(0, 12)}`;
  }

  /** Discover the agent's own terminal ID (the focused terminal at startup). */
  private async discoverAgentTerminal(): Promise<string> {
    if (this.agentTerminalId) return this.agentTerminalId;
    try {
      const id = await this.ghostty(
        `get id of focused terminal of selected tab of front window`,
      );
      if (id) this.agentTerminalId = id;
      return id;
    } catch {
      return "";
    }
  }

  private async waitForShell(timeoutMs = 10000): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      try {
        const cwd = await this.ghostty(
          `get working directory of terminal id "${this.terminalId}"`,
        );
        if (cwd && cwd !== "" && cwd !== "missing value") return true;
      } catch {}
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

    // Discover our own terminal ID
    const agentId = await this.discoverAgentTerminal();
    if (!agentId) return false;

    // Try to reuse a previously saved pane
    try {
      const saved = readFileSync(this.paneIdFile, "utf-8").trim();
      if (saved && (await this.checkTerminalAlive(saved))) {
        this.terminalId = saved;
        this.paneReady = true;
        return true;
      }
    } catch {}

    // Create a new split to the right of the agent terminal
    try {
      const newId = await this.ghostty(
        `set newTerm to split terminal id "${agentId}" direction right\nreturn id of newTerm`,
      );
      if (!newId || newId === "missing value") return false;
      this.terminalId = newId;
    } catch {
      return false;
    }

    // Focus back to the agent terminal
    try {
      await this.ghostty(`focus terminal id "${agentId}"`);
    } catch {}

    // Save pane ID for reuse across restarts
    writeFileSync(this.paneIdFile, this.terminalId);

    // Wait for the shell to start in the new split
    if (!(await this.waitForShell())) {
      try {
        await this.ghostty(`close terminal id "${this.terminalId}"`);
      } catch {}
      this.terminalId = "";
      return false;
    }

    this.paneReady = true;
    return true;
  }

  // ── capture & cwd ──────────────────────────────────────

  /**
   * Capture terminal content using Ghostty's write_screen_file action.
   *
   * This works by:
   * 1. Saving the current clipboard to a temp file
   * 2. Asking Ghostty to write the visible screen to a temp file and copy
   *    the path to the clipboard
   * 3. Reading the path from the clipboard, then reading the file
   * 4. Restoring the original clipboard
   *
   * Note: Uses write_screen_file rather than write_scrollback_file because
   * the scrollback variant has a bug in Ghostty 1.3.0 where it returns true
   * but does not actually copy the filepath to the clipboard.
   *
   * This briefly clobbers the clipboard. If the clipboard contains non-text
   * data (e.g. images), it will be lost.
   */
  async capturePane(lines = 2000): Promise<string> {
    // Save clipboard to file
    await this.exec(
      "bash",
      ["-c", `pbpaste > ${sq(this.clipBackupFile)} 2>/dev/null || true`],
      { timeout: 2000 },
    );

    try {
      // Ask Ghostty to write screen content and copy path to clipboard
      await this.ghostty(
        `perform action "write_screen_file:copy" on terminal id "${this.terminalId}"`,
      );

      // Small delay to ensure clipboard is updated
      await sleep(50);

      // Read filepath from clipboard
      const { stdout } = await this.exec("pbpaste", [], { timeout: 2000 });
      const filepath = stdout.trim();

      if (!filepath || !filepath.startsWith("/")) return "";

      let content: string;
      try {
        content = readFileSync(filepath, "utf-8");
      } catch {
        return "";
      }

      // Clean up the temp file
      try {
        unlinkSync(filepath);
      } catch {}

      // Strip ANSI escape sequences if present
      content = stripAnsi(content);

      // Trim to requested number of lines
      const allLines = content.split("\n");
      if (allLines.length <= lines) return content;
      return allLines.slice(-lines).join("\n");
    } finally {
      // Restore clipboard from backup
      await this.exec(
        "bash",
        ["-c", `pbcopy < ${sq(this.clipBackupFile)} 2>/dev/null || true`],
        { timeout: 2000 },
      ).catch(() => {});
      try {
        unlinkSync(this.clipBackupFile);
      } catch {}
    }
  }

  async getPaneCwd(): Promise<string> {
    try {
      const cwd = await this.ghostty(
        `get working directory of terminal id "${this.terminalId}"`,
      );
      if (cwd && cwd !== "missing value") return cwd;
    } catch {}
    return process.cwd();
  }

  // ── send keys ──────────────────────────────────────────

  async sendText(text: string): Promise<void> {
    // Escape backslashes and double quotes for AppleScript string literal
    const escaped = text.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    await this.ghostty(
      `input text "${escaped}" to terminal id "${this.terminalId}"`,
    );
  }

  async sendEnter(): Promise<void> {
    await this.ghostty(`send key "enter" to terminal id "${this.terminalId}"`);
  }

  async sendCtrlC(): Promise<void> {
    await this.ghostty(
      `send key "c" modifiers "control" to terminal id "${this.terminalId}"`,
    );
  }

  // ── shell info ─────────────────────────────────────────

  async getShellName(): Promise<string> {
    // Ghostty doesn't expose the foreground process, so use $SHELL
    const shell = process.env.SHELL || "";
    return shell.split("/").pop() || "bash";
  }

  // ── hook & signaling ───────────────────────────────────

  generateHookCode(shell: string): string {
    const envSetup = `export PAGER=cat GIT_PAGER=cat`;

    if (shell.includes("zsh")) {
      return [
        envSetup,
        `typeset -gi __pi_seq=0`,
        `__pi_precmd() { local rc=$?; echo "$((++__pi_seq)) $rc" > ${this.rcFile}; (echo > ${this.signalFifo} &) 2>/dev/null; return $rc; }`,
        `__pi_ready() { (echo > ${this.readyFifo} &) 2>/dev/null; }`,
        `precmd_functions=(__pi_precmd $precmd_functions __pi_ready)`,
      ].join("; ");
    } else {
      return [
        envSetup,
        `__pi_seq=0`,
        `__pi_pcmd() { local rc=$?; echo "$((++__pi_seq)) $rc" > ${this.rcFile}; (echo > ${this.signalFifo} &) 2>/dev/null; return $rc; }`,
        `__pi_rdy() { (echo > ${this.readyFifo} &) 2>/dev/null; }`,
        `PROMPT_COMMAND="__pi_pcmd;\${PROMPT_COMMAND};__pi_rdy"`,
      ].join("; ");
    }
  }

  async prepareForHook(): Promise<void> {
    for (const f of [this.rcFile, this.signalFifo, this.readyFifo]) {
      try {
        unlinkSync(f);
      } catch {}
    }
    await this.exec("mkfifo", [this.signalFifo], { timeout: 2000 });
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

  async waitForPrompt(timeoutMs: number): Promise<boolean> {
    try {
      const r = await this.exec("cat", [this.signalFifo], {
        timeout: timeoutMs,
      });
      return r.code === 0;
    } catch {
      return false;
    }
  }

  async waitForReady(timeoutMs: number): Promise<boolean> {
    try {
      const r = await this.exec("cat", [this.readyFifo], {
        timeout: timeoutMs,
      });
      return r.code === 0;
    } catch {
      return false;
    }
  }

  async unblockWait(): Promise<void> {
    await this.exec(
      "bash",
      [
        "-c",
        `(echo > ${this.signalFifo} &; echo > ${this.readyFifo} &) 2>/dev/null`,
      ],
      { timeout: 2000 },
    ).catch(() => {});
  }

  cleanup(): void {
    for (const f of [
      this.rcFile,
      this.signalFifo,
      this.readyFifo,
      this.clipBackupFile,
    ]) {
      try {
        unlinkSync(f);
      } catch {}
    }
  }
}

/** Strip ANSI escape sequences from terminal output. */
function stripAnsi(text: string): string {
  return text.replace(
    // eslint-disable-next-line no-control-regex
    /\x1b\[[0-9;]*[a-zA-Z]|\x1b\].*?(?:\x07|\x1b\\)|\x1b[()][0-9A-B]|\r/g,
    "",
  );
}
