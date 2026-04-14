import type { ExecFn, MirrorBackend } from "./types.js";
import {
  sq,
  sleep,
  unlinkAll,
  readLogFile,
  generateShellHook,
  DEFAULT_PANE_HEIGHT_PCT,
} from "./types.js";
import { writeFileSync, readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { readlink } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const APP_ID = "pi-mirror";

/** Per-tab state for managed processes. */
interface TabState {
  conId: number;
  appId: string;
  inputFifo: string;
  outputLog: string;
}

export class SwayBackend implements MirrorBackend {
  readonly label = "sway";

  private conId = 0;
  private shellPid = 0;
  private paneReady = false;
  private exec: ExecFn;
  private onReset?: () => void;

  private readonly sessionId: string;
  private readonly rcFile: string;
  private readonly signalFifo: string;
  private readonly agentSignalFifo: string;
  private readonly readyFifo: string;
  private readonly inputFifo: string;
  private readonly outputLog: string;
  private readonly relayScript: string;

  /** Managed process tabs keyed by targetId (string con_id). */
  private tabs = new Map<string, TabState>();
  /** Whether the mirror area has been converted to tabbed layout. */
  private tabbedLayout = false;

  get mainTargetId(): string {
    return String(this.conId);
  }

  constructor(exec: ExecFn, onReset?: () => void) {
    this.exec = exec;
    this.onReset = onReset;
    this.sessionId = randomUUID().slice(0, 8);
    this.rcFile = `/tmp/pi-mirror-rc-${this.sessionId}`;
    this.signalFifo = `/tmp/pi-mirror-signal-${this.sessionId}`;
    this.agentSignalFifo = `/tmp/pi-mirror-agent-signal-${this.sessionId}`;
    this.readyFifo = `/tmp/pi-mirror-ready-${this.sessionId}`;
    this.inputFifo = `/tmp/pi-mirror-input-${this.sessionId}`;
    this.outputLog = `/tmp/pi-mirror-log-${this.sessionId}`;
    this.relayScript = join(
      dirname(fileURLToPath(import.meta.url)),
      "sway-relay.py",
    );
  }

  /** Get the log path and input FIFO for a target (main pane or tab). */
  private targetPaths(targetId: string): {
    inputFifo: string;
    outputLog: string;
  } {
    const tab = this.tabs.get(targetId);
    if (tab) return { inputFifo: tab.inputFifo, outputLog: tab.outputLog };
    return { inputFifo: this.inputFifo, outputLog: this.outputLog };
  }

  private async swaymsg(
    ...args: string[]
  ): Promise<{ stdout: string; code: number }> {
    const r = await this.exec("swaymsg", args, { timeout: 5000 });
    return { stdout: r.stdout, code: r.code ?? 1 };
  }

  private async getTree(): Promise<any> {
    const r = await this.swaymsg("-t", "get_tree");
    if (r.code !== 0) return null;
    try {
      return JSON.parse(r.stdout);
    } catch {
      return null;
    }
  }

  private findNode(tree: any, predicate: (n: any) => boolean): any | null {
    if (!tree) return null;
    if (predicate(tree)) return tree;
    for (const child of [
      ...(tree.nodes || []),
      ...(tree.floating_nodes || []),
    ]) {
      const found = this.findNode(child, predicate);
      if (found) return found;
    }
    return null;
  }

  private async findMirrorWindow(): Promise<any | null> {
    const tree = await this.getTree();
    if (!tree) return null;

    if (this.conId > 0) {
      const byId = this.findNode(tree, (n) => n.id === this.conId);
      if (byId) return byId;
    }

    return this.findNode(tree, (n) => n.app_id === APP_ID && n.type === "con");
  }

  async paneAlive(): Promise<boolean> {
    return (await this.findMirrorWindow()) !== null;
  }

  isPaneReady(): boolean {
    return this.paneReady;
  }

  async resetState(): Promise<void> {
    this.paneReady = false;
    this.conId = 0;
    this.shellPid = 0;
    this.tabbedLayout = false;
    unlinkAll(
      this.rcFile,
      this.signalFifo,
      this.agentSignalFifo,
      this.readyFifo,
      this.inputFifo,
      this.outputLog,
    );
    for (const [, tab] of this.tabs) {
      unlinkAll(tab.inputFifo, tab.outputLog);
    }
    this.tabs.clear();
    this.onReset?.();
  }

  displayTarget(): string {
    return `sway:${this.conId}`;
  }

  private async findShellPid(): Promise<number> {
    const win = await this.findMirrorWindow();
    if (!win?.pid) return 0;

    const walkChildren = async (
      ppid: number,
      depth: number,
    ): Promise<number> => {
      if (depth > 4) return 0;
      try {
        const r = await this.exec(
          "bash",
          ["-c", `ps --ppid ${ppid} -o pid=,comm= 2>/dev/null`],
          { timeout: 2000 },
        );
        for (const line of r.stdout.trim().split("\n")) {
          const parts = line.trim().split(/\s+/);
          if (parts.length < 2) continue;
          const [pid, comm] = parts;
          if (/sh$/.test(comm)) return parseInt(pid, 10);
          const child = await walkChildren(parseInt(pid, 10), depth + 1);
          if (child > 0) return child;
        }
      } catch {}
      return 0;
    };

    return walkChildren(win.pid, 0);
  }

  private async waitForShell(timeoutMs = 10000): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const pid = await this.findShellPid();
      if (pid > 0) {
        this.shellPid = pid;
        return true;
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

    const existing = await this.findMirrorWindow();
    if (existing) {
      this.conId = existing.id;
      if (await this.waitForShell()) {
        this.paneReady = true;
        return true;
      }
    }

    // Create FIFOs and log
    unlinkAll(this.inputFifo);
    writeFileSync(this.outputLog, "");
    await this.exec("mkfifo", [this.inputFifo], { timeout: 2000 });

    await this.swaymsg("splitv");

    const cmd =
      `foot --app-id ${APP_ID}` +
      ` python3 ${sq(this.relayScript)} ${sq(this.inputFifo)} ${sq(this.outputLog)}`;

    const r = await this.exec("bash", ["-c", `swaymsg exec ${sq(cmd)}`], {
      timeout: 5000,
    });
    if (r.code !== 0 && r.code !== null) return false;

    const deadline = Date.now() + 10000;
    while (Date.now() < deadline) {
      const win = await this.findMirrorWindow();
      if (win) {
        this.conId = win.id;
        break;
      }
      await sleep(300);
    }
    if (!this.conId) return false;

    await this.swaymsg(
      `[con_id=${this.conId}]`,
      "resize",
      "set",
      "height",
      String(DEFAULT_PANE_HEIGHT_PCT),
      "ppt",
    );
    await this.swaymsg("focus", "up");

    if (!(await this.waitForShell())) {
      await this.swaymsg(`[con_id=${this.conId}]`, "kill");
      this.conId = 0;
      return false;
    }

    this.paneReady = true;
    return true;
  }

  // ── unified I/O (main pane + tabs) ─────────────────────

  async capture(targetId: string, lines = 2000): Promise<string> {
    const { outputLog } = this.targetPaths(targetId);
    return readLogFile(outputLog, lines);
  }

  async getPaneCwd(): Promise<string> {
    if (this.shellPid > 0) {
      try {
        return await readlink(`/proc/${this.shellPid}/cwd`);
      } catch {}
    }
    return process.cwd();
  }

  async sendText(targetId: string, text: string): Promise<void> {
    const { inputFifo } = this.targetPaths(targetId);
    await this.exec(
      "bash",
      ["-c", `printf '%s' ${sq(text)} > ${sq(inputFifo)}`],
      { timeout: 5000 },
    );
  }

  async sendEnter(targetId: string): Promise<void> {
    const { inputFifo } = this.targetPaths(targetId);
    await this.exec("bash", ["-c", `printf '\\r' > ${sq(inputFifo)}`], {
      timeout: 5000,
    });
  }

  async sendCtrlC(targetId: string): Promise<void> {
    const { inputFifo } = this.targetPaths(targetId);
    await this.exec("bash", ["-c", `printf '\\x03' > ${sq(inputFifo)}`], {
      timeout: 5000,
    });
  }

  async getShellName(): Promise<string> {
    if (this.shellPid > 0) {
      try {
        const r = await this.exec(
          "bash",
          ["-c", `cat /proc/${this.shellPid}/comm`],
          { timeout: 2000 },
        );
        return r.stdout.trim();
      } catch {}
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
    if (this.conId > 0) {
      await this.swaymsg(`[con_id=${this.conId}]`, "kill").catch(() => {});
      this.conId = 0;
      this.paneReady = false;
    }
  }

  cleanup(): void {
    unlinkAll(
      this.rcFile,
      this.signalFifo,
      this.agentSignalFifo,
      this.readyFifo,
      this.inputFifo,
      this.outputLog,
    );
    for (const [, tab] of this.tabs) {
      unlinkAll(tab.inputFifo, tab.outputLog);
    }
    this.tabs.clear();
  }

  // ── tab management ─────────────────────────────────────

  private async findNodeById(conId: number): Promise<any | null> {
    const tree = await this.getTree();
    if (!tree) return null;
    return this.findNode(tree, (n) => n.id === conId);
  }

  async createTab(name: string): Promise<string | null> {
    if (!this.paneReady || this.conId === 0) return null;

    const appId = `pi-mirror-tab-${name}`;
    const inputFifo = `/tmp/pi-mirror-input-${this.sessionId}-${name}`;
    const outputLog = `/tmp/pi-mirror-log-${this.sessionId}-${name}`;

    unlinkAll(inputFifo);
    writeFileSync(outputLog, "");
    await this.exec("mkfifo", [inputFifo], { timeout: 2000 });

    await this.swaymsg(`[con_id=${this.conId}]`, "focus");

    if (!this.tabbedLayout) {
      await this.swaymsg("splith");
    }

    const cmd =
      `foot --app-id ${appId} --title ${sq(name)}` +
      ` python3 ${sq(this.relayScript)} ${sq(inputFifo)} ${sq(outputLog)}`;

    const r = await this.exec("bash", ["-c", `swaymsg exec ${sq(cmd)}`], {
      timeout: 5000,
    });
    if (r.code !== 0 && r.code !== null) {
      unlinkAll(inputFifo, outputLog);
      await this.swaymsg("focus", "up");
      return null;
    }

    let tabConId = 0;
    const deadline = Date.now() + 10000;
    while (Date.now() < deadline) {
      const tree = await this.getTree();
      const node = this.findNode(
        tree,
        (n: any) => n.app_id === appId && n.type === "con",
      );
      if (node) {
        tabConId = node.id;
        break;
      }
      await sleep(300);
    }

    if (!tabConId) {
      unlinkAll(inputFifo, outputLog);
      await this.swaymsg("focus", "up");
      return null;
    }

    if (!this.tabbedLayout) {
      await this.swaymsg("layout", "tabbed");
      this.tabbedLayout = true;
    }

    await this.swaymsg("focus", "up");

    const targetId = String(tabConId);
    this.tabs.set(targetId, { conId: tabConId, appId, inputFifo, outputLog });

    return targetId;
  }

  async closeTab(targetId: string): Promise<void> {
    const tab = this.tabs.get(targetId);
    if (!tab) return;
    await this.swaymsg(`[con_id=${tab.conId}]`, "kill").catch(() => {});
    unlinkAll(tab.inputFifo, tab.outputLog);
    this.tabs.delete(targetId);
  }

  async isTabAlive(targetId: string): Promise<boolean> {
    const tab = this.tabs.get(targetId);
    if (!tab) return false;
    const node = await this.findNodeById(tab.conId);
    return node !== null;
  }

  // ── visibility & focus ─────────────────────────────────

  async hide(): Promise<void> {
    // Hide process tabs first, then the main pane
    for (const [, tab] of this.tabs) {
      if (tab.conId > 0) {
        await this.swaymsg(`[con_id=${tab.conId}]`, "move", "scratchpad");
      }
    }
    if (this.conId > 0) {
      await this.swaymsg(`[con_id=${this.conId}]`, "move", "scratchpad");
    }
  }

  async show(tabTargetIds: string[] = []): Promise<void> {
    if (this.conId <= 0) return;

    await this.swaymsg("splitv");

    // Restore main mirror pane from scratchpad
    await this.swaymsg(`[con_id=${this.conId}]`, "scratchpad", "show");
    await this.swaymsg(`[con_id=${this.conId}]`, "floating", "disable");

    const tabConIds = tabTargetIds
      .map((id) => this.tabs.get(id)?.conId ?? 0)
      .filter((id) => id > 0);

    if (tabConIds.length > 0) {
      await this.swaymsg(`[con_id=${this.conId}]`, "focus");
      await this.swaymsg("splith");

      for (const tabId of tabConIds) {
        await this.swaymsg(`[con_id=${tabId}]`, "scratchpad", "show");
        await this.swaymsg(`[con_id=${tabId}]`, "floating", "disable");
      }

      await this.swaymsg("layout", "tabbed");
    }

    await this.swaymsg(
      `[con_id=${this.conId}]`,
      "resize",
      "set",
      "height",
      String(DEFAULT_PANE_HEIGHT_PCT),
      "ppt",
    );

    await this.swaymsg("focus", "up");
  }

  async switchTab(
    _fromTargetId: string | null,
    toTargetId: string | null,
  ): Promise<void> {
    // Sway manages tabbed layout natively — just focus the target container
    if (toTargetId === null) {
      // Focus main mirror pane
      if (this.conId > 0) {
        await this.swaymsg(`[con_id=${this.conId}]`, "focus");
        await this.swaymsg("focus", "up");
      }
    } else {
      const tab = this.tabs.get(toTargetId);
      if (tab) {
        await this.swaymsg(`[con_id=${tab.conId}]`, "focus");
        await this.swaymsg("focus", "up");
      }
    }
  }

  async recoverShellToMirror(): Promise<void> {
    // Sway: just focus the main mirror pane
    if (this.conId > 0) {
      await this.swaymsg(`[con_id=${this.conId}]`, "focus");
      await this.swaymsg("focus", "up");
    }
  }
}
