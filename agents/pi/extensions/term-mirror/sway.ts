import type { ExecFn, MirrorBackend } from "./types.js";
import { sq, sleep } from "./types.js";
import {
  writeFileSync,
  readFileSync,
  unlinkSync,
  statSync,
} from "node:fs";
import { randomUUID } from "node:crypto";
import { readlink } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const APP_ID = "pi-mirror";
const SCROLLBACK_MAX = 500_000;

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
  private readonly readyFifo: string;
  private readonly inputFifo: string;
  private readonly outputLog: string;
  private readonly relayScript: string;

  constructor(exec: ExecFn, onReset?: () => void) {
    this.exec = exec;
    this.onReset = onReset;
    this.sessionId = randomUUID().slice(0, 8);
    this.rcFile = `/tmp/pi-mirror-rc-${this.sessionId}`;
    this.signalFifo = `/tmp/pi-mirror-signal-${this.sessionId}`;
    this.readyFifo = `/tmp/pi-mirror-ready-${this.sessionId}`;
    this.inputFifo = `/tmp/pi-mirror-input-${this.sessionId}`;
    this.outputLog = `/tmp/pi-mirror-log-${this.sessionId}`;
    this.relayScript = join(
      dirname(fileURLToPath(import.meta.url)),
      "sway-relay.py",
    );
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

    return this.findNode(
      tree,
      (n) => n.app_id === APP_ID && n.type === "con",
    );
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
    for (const f of [
      this.rcFile,
      this.signalFifo,
      this.readyFifo,
      this.inputFifo,
      this.outputLog,
    ]) {
      try {
        unlinkSync(f);
      } catch {}
    }
    this.onReset?.();
  }

  displayTarget(): string {
    return `sway:${this.conId}`;
  }

  private async findShellPid(): Promise<number> {
    const win = await this.findMirrorWindow();
    if (!win?.pid) return 0;

    // Walk: foot -> python3 (relay) -> shell
    const walkChildren = async (ppid: number, depth: number): Promise<number> => {
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

    // Check for existing mirror window
    const existing = await this.findMirrorWindow();
    if (existing) {
      this.conId = existing.id;
      if (await this.waitForShell()) {
        this.paneReady = true;
        return true;
      }
    }

    // Create FIFOs and log
    try {
      unlinkSync(this.inputFifo);
    } catch {}
    writeFileSync(this.outputLog, "");
    await this.exec("mkfifo", [this.inputFifo], { timeout: 2000 });

    // Launch foot with the relay script
    const cmd =
      `foot --app-id ${APP_ID}` +
      ` python3 ${sq(this.relayScript)} ${sq(this.inputFifo)} ${sq(this.outputLog)}`;

    const r = await this.exec("bash", ["-c", `swaymsg exec ${sq(cmd)}`], {
      timeout: 5000,
    });
    if (r.code !== 0 && r.code !== null) return false;

    // Wait for window
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

    if (!(await this.waitForShell())) {
      await this.swaymsg(`[con_id=${this.conId}]`, "kill");
      this.conId = 0;
      return false;
    }

    this.paneReady = true;
    return true;
  }

  async capturePane(lines = 2000): Promise<string> {
    try {
      const raw = readFileSync(this.outputLog, "utf-8");
      const clean = raw.replace(
        // eslint-disable-next-line no-control-regex
        /\x1b\[[0-9;]*[a-zA-Z]|\x1b\].*?(?:\x07|\x1b\\)|\x1b[()][0-9A-B]|\r/g,
        "",
      );
      const allLines = clean.split("\n");
      const result = allLines.slice(-lines).join("\n");

      try {
        const stat = statSync(this.outputLog);
        if (stat.size > SCROLLBACK_MAX) {
          const keep = raw.slice(-Math.floor(SCROLLBACK_MAX / 2));
          writeFileSync(this.outputLog, keep);
        }
      } catch {}

      return result;
    } catch {
      return "";
    }
  }

  async getPaneCwd(): Promise<string> {
    if (this.shellPid > 0) {
      try {
        return await readlink(`/proc/${this.shellPid}/cwd`);
      } catch {}
    }
    return process.cwd();
  }

  // Send text via the input FIFO — the relay forwards it to the shell's pty
  async sendText(text: string): Promise<void> {
    await this.exec(
      "bash",
      ["-c", `printf '%s' ${sq(text)} > ${sq(this.inputFifo)}`],
      { timeout: 5000 },
    );
  }

  async sendEnter(): Promise<void> {
    await this.exec(
      "bash",
      ["-c", `printf '\\r' > ${sq(this.inputFifo)}`],
      { timeout: 5000 },
    );
  }

  async sendCtrlC(): Promise<void> {
    await this.exec(
      "bash",
      ["-c", `printf '\\x03' > ${sq(this.inputFifo)}`],
      { timeout: 5000 },
    );
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
      this.inputFifo,
      this.outputLog,
    ]) {
      try {
        unlinkSync(f);
      } catch {}
    }
  }
}
