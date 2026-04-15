/**
 * Tmux backend for the shell extension.
 *
 * Uses tmux split panes and `tmux wait-for` for instant signaling.
 * State is stored in tmux session environment variables (no temp files).
 */
import type { ExecFn, MirrorBackend } from "./types.js";
import { sleep, generateShellHook, DEFAULT_PANE_HEIGHT_PCT } from "./types.js";

const WAIT_CHANNEL = "pi-prompt";
const AGENT_WAIT_CHANNEL = "pi-agent-prompt";
const READY_CHANNEL = "pi-ready";
const ENV_PANE_ID = "PI_MIRROR_PANE";
const ENV_LAST_RC = "PI_LAST_RC";

export class TmuxBackend implements MirrorBackend {
  readonly label = "tmux";

  private target: string;
  private paneReady = false;
  private exec: ExecFn;
  private onReset?: () => void;

  get mainTargetId(): string {
    return this.target;
  }

  constructor(exec: ExecFn, onReset?: () => void) {
    this.exec = exec;
    this.onReset = onReset;
    this.target = process.env.TMUX_MIRROR_TARGET || "";
  }

  // ── tmux primitives ────────────────────────────────────

  private async tmux(
    ...args: string[]
  ): Promise<{ stdout: string; code: number }> {
    const r = await this.exec("tmux", args, { timeout: 5000 });
    return { stdout: r.stdout, code: r.code ?? 1 };
  }

  private async getEnv(name: string): Promise<string> {
    const r = await this.tmux("show-environment", name);
    if (r.code !== 0) return "";
    const line = r.stdout.trim();
    if (line.startsWith("-")) return "";
    const eq = line.indexOf("=");
    return eq >= 0 ? line.slice(eq + 1) : "";
  }

  private async setEnv(name: string, value: string): Promise<void> {
    await this.tmux("set-environment", name, value);
  }

  private async unsetEnv(name: string): Promise<void> {
    await this.tmux("set-environment", "-u", name);
  }

  // ── pane lifecycle ─────────────────────────────────────

  private async checkPaneAlive(paneId: string): Promise<boolean> {
    if (!paneId) return false;
    try {
      const r = await this.exec(
        "tmux",
        ["list-panes", "-s", "-F", "#{pane_id}"],
        { timeout: 2000 },
      );
      return r.stdout.trim().split("\n").includes(paneId);
    } catch {
      return false;
    }
  }

  /** Check if a pane is in the same tmux window as the pi pane. */
  private async isPaneInCurrentWindow(paneId: string): Promise<boolean> {
    if (!paneId) return false;
    try {
      const r = await this.exec("tmux", ["list-panes", "-F", "#{pane_id}"], {
        timeout: 2000,
      });
      return r.stdout.trim().split("\n").includes(paneId);
    } catch {
      return false;
    }
  }

  async paneAlive(): Promise<boolean> {
    return this.checkPaneAlive(this.target);
  }

  isPaneReady(): boolean {
    return this.paneReady;
  }

  async resetState(): Promise<void> {
    this.paneReady = false;
    this.target = process.env.TMUX_MIRROR_TARGET || "";
    await this.unsetEnv(ENV_LAST_RC).catch(() => {});
    this.onReset?.();
  }

  displayTarget(): string {
    return this.target;
  }

  private async waitForShell(timeoutMs = 10000): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const cmd = (
        await this.tmux(
          "display-message",
          "-t",
          this.target,
          "-p",
          "#{pane_current_command}",
        )
      ).stdout.trim();
      if (cmd && /sh$/.test(cmd)) return true;
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

    if ((await this.tmux("has-session")).code !== 0) return false;

    if (this.target) {
      if (await this.checkPaneAlive(this.target)) {
        if (!(await this.isPaneInCurrentWindow(this.target))) {
          await this.recoverShellToMirror();
        }
        this.paneReady = true;
        return true;
      }
      return false;
    }

    const savedId = await this.getEnv(ENV_PANE_ID);
    if (savedId && (await this.checkPaneAlive(savedId))) {
      this.target = savedId;
      if (!(await this.isPaneInCurrentWindow(savedId))) {
        await this.recoverShellToMirror();
      }
      this.paneReady = true;
      return true;
    }

    const split = await this.tmux(
      "split-window",
      "-v",
      "-d",
      "-l",
      `${DEFAULT_PANE_HEIGHT_PCT}%`,
      "-P",
      "-F",
      "#{pane_id}",
    );
    if (split.code !== 0) return false;

    this.target = split.stdout.trim();
    await this.setEnv(ENV_PANE_ID, this.target);

    if (!(await this.waitForShell())) {
      await this.tmux("kill-pane", "-t", this.target);
      this.target = "";
      return false;
    }

    this.paneReady = true;
    return true;
  }

  // ── unified I/O (main pane + tabs) ─────────────────────

  async capture(targetId: string, lines = 2000): Promise<string> {
    const r = await this.tmux(
      "capture-pane",
      "-p",
      "-J",
      "-t",
      targetId,
      "-S",
      `-${lines}`,
    );
    return r.code === 0 ? r.stdout : "";
  }

  async getPaneCwd(): Promise<string> {
    return (
      await this.tmux(
        "display-message",
        "-t",
        this.target,
        "-p",
        "#{pane_current_path}",
      )
    ).stdout.trim();
  }

  async sendText(targetId: string, text: string): Promise<void> {
    await this.tmux("send-keys", "-t", targetId, "-l", text);
  }

  async sendEnter(targetId: string): Promise<void> {
    await this.tmux("send-keys", "-t", targetId, "Enter");
  }

  async sendCtrlC(targetId: string): Promise<void> {
    await this.tmux("send-keys", "-t", targetId, "C-c");
  }

  // ── shell info ─────────────────────────────────────────

  async getShellName(): Promise<string> {
    return (
      await this.tmux(
        "display-message",
        "-t",
        this.target,
        "-p",
        "#{pane_current_command}",
      )
    ).stdout.trim();
  }

  // ── hook & signaling ───────────────────────────────────

  generateHookCode(shell: string): string {
    return generateShellHook(shell, {
      rcWrite: `tmux set-environment ${ENV_LAST_RC} "$((++__pi_seq)) $rc"`,
      signalPrompt: `tmux wait-for -S ${WAIT_CHANNEL} 2>/dev/null`,
      signalAgent: `tmux wait-for -S ${AGENT_WAIT_CHANNEL} 2>/dev/null`,
      signalReady: `tmux wait-for -S ${READY_CHANNEL} 2>/dev/null`,
    });
  }

  async prepareForHook(): Promise<void> {
    await this.unsetEnv(ENV_LAST_RC).catch(() => {});
  }

  async readRc(): Promise<{ seq: number; rc: number }> {
    try {
      const val = await this.getEnv(ENV_LAST_RC);
      if (!val) return { seq: 0, rc: 0 };
      const [s, r] = val.split(" ");
      return { seq: parseInt(s, 10) || 0, rc: parseInt(r, 10) || 0 };
    } catch {
      return { seq: 0, rc: 0 };
    }
  }

  private async waitForChannel(
    channel: string,
    timeoutMs: number,
  ): Promise<boolean> {
    try {
      const r = await this.exec("tmux", ["wait-for", channel], {
        timeout: timeoutMs,
      });
      return r.code === 0;
    } catch {
      return false;
    }
  }

  async waitForPrompt(timeoutMs: number): Promise<boolean> {
    return this.waitForChannel(WAIT_CHANNEL, timeoutMs);
  }

  async waitForAgentSignal(timeoutMs: number): Promise<boolean> {
    return this.waitForChannel(AGENT_WAIT_CHANNEL, timeoutMs);
  }

  async waitForReady(timeoutMs: number): Promise<boolean> {
    return this.waitForChannel(READY_CHANNEL, timeoutMs);
  }

  async unblockWait(): Promise<void> {
    await this.tmux("wait-for", "-S", WAIT_CHANNEL).catch(() => {});
    await this.tmux("wait-for", "-S", AGENT_WAIT_CHANNEL).catch(() => {});
    await this.tmux("wait-for", "-S", READY_CHANNEL).catch(() => {});
  }

  async killPane(): Promise<void> {
    if (this.target) {
      await this.tmux("kill-pane", "-t", this.target).catch(() => {});
      await this.unsetEnv(ENV_PANE_ID).catch(() => {});
      this.target = "";
      this.paneReady = false;
    }
  }

  cleanup(): void {
    // tmux state lives in session env variables, nothing to clean up
  }

  // ── tab management ─────────────────────────────────────

  async createTab(name: string): Promise<string | null> {
    const r = await this.tmux(
      "new-window",
      "-d",
      "-P",
      "-F",
      "#{pane_id}",
      "-n",
      name,
    );
    if (r.code !== 0) return null;
    const paneId = r.stdout.trim();
    return paneId || null;
  }

  async closeTab(targetId: string): Promise<void> {
    await this.tmux("kill-pane", "-t", targetId).catch(() => {});
  }

  async isTabAlive(targetId: string): Promise<boolean> {
    return this.checkPaneAlive(targetId);
  }

  // ── visibility & focus ─────────────────────────────────

  async hide(): Promise<void> {
    // Break the visible pane out to a hidden window
    // Caller passes the active pane's target via switchTab context,
    // but hide always operates on whatever is in the mirror slot.
    // We break the current mirror-slot pane out.
    // The caller in index.ts tracks which pane ID is active.
    // For simplicity, we just break the mirror target out.
    // (index.ts calls hide() after ensuring the right pane is active)
    await this.tmux("break-pane", "-d", "-s", this.target).catch(() => {});
  }

  async show(tabTargetIds?: string[]): Promise<void> {
    // Join the main pane back below the current pane
    try {
      await this.tmux(
        "join-pane",
        "-v",
        "-d",
        "-l",
        `${DEFAULT_PANE_HEIGHT_PCT}%`,
        "-s",
        this.target,
      );
    } catch {}
  }

  async switchTab(
    fromTargetId: string | null,
    toTargetId: string | null,
  ): Promise<void> {
    const src = fromTargetId ?? this.target;
    const dst = toTargetId ?? this.target;
    if (src === dst) return;
    await this.tmux("swap-pane", "-s", src, "-t", dst);
    await this.tmux("select-pane", "-U");
  }

  async recoverShellToMirror(): Promise<void> {
    if (!this.target) return;
    try {
      await this.tmux(
        "join-pane",
        "-v",
        "-d",
        "-l",
        `${DEFAULT_PANE_HEIGHT_PCT}%`,
        "-s",
        this.target,
      );
    } catch {}
  }
}
