/**
 * Shared Terminal Extension (tmux + sway)
 *
 * Overrides the built-in bash tool to run commands in a shared terminal split.
 * Supports two backends:
 *   - tmux: splits via tmux, signals via `tmux wait-for`
 *   - sway: splits via swaymsg + foot, PTY relay for I/O, signals via named pipe (FIFO)
 *
 * The actual command text is sent directly — no wrappers, no markers.
 *
 * Completion and exit code are detected via a shell hook (precmd for zsh,
 * PROMPT_COMMAND for bash). The hook writes a sequence number + $? and
 * signals completion (tmux wait-for or named pipe/FIFO for sway).
 * Both backends block with zero CPU until signaled.
 *
 * The user can also type commands in the pane. A background loop detects
 * new activity when the agent is idle and injects it into the conversation.
 *
 * Usage:
 *   pi              (auto-activates in tmux/sway)
 *   pi --no-mirror   (disable shared terminal)
 *
 * Setup:
 *   - tmux: run pi inside tmux. A split pane is auto-created.
 *   - sway: run pi under sway. A foot terminal is launched in a split.
 *
 * Environment variables:
 *   TMUX_MIRROR_TARGET  - tmux target pane (default: auto-created split)
 */
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import {
  truncateTail,
  DEFAULT_MAX_BYTES,
  DEFAULT_MAX_LINES,
  formatSize,
} from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { writeFileSync } from "node:fs";

import type { MirrorBackend, ManagedProcess } from "./types.js";
import { sq, sleep, sanitizeName, DEFAULT_PANE_HEIGHT_PCT } from "./types.js";
import { TmuxBackend } from "./tmux.js";
import { SwayBackend } from "./sway.js";

export default function (pi: ExtensionAPI) {
  // ── CLI flag (registered before anything else) ───────────
  // Flags aren't available at init time, so everything else
  // is deferred to session_start where getFlag works.

  pi.registerFlag("no-mirror", {
    description: "Disable shared terminal split (tmux/sway)",
    type: "boolean",
    default: false,
  });

  pi.on("session_start", async (_event, ctx) => {
    if (pi.getFlag("no-mirror")) return;

    // ── shared state ───────────────────────────────────────

    let hookInstalled = false;
    let promptHeight = 2;
    let promptSymbol = "$ ";
    let agentRunning = false;
    let activityLoopRunning = false;
    let activityAbort: AbortController | null = null;
    let lastSnapshot = "";
    const processes = new Map<string, ManagedProcess>();
    const stoppedProcesses = new Set<string>();
    let watchLoopRunning = false;
    let watchAbort: AbortController | null = null;
    const WATCH_INTERVAL_MS = 4000; // check watch tabs every 4s
    let activeTabName: string | null = null; // null = main shell (tmux tab bar)
    let mirrorVisible = false; // whether the mirror pane is visible as a split
    const tabsWithActivity = new Set<string>(); // tabs with unseen activity

    // Callback invoked by backends when state is reset (pane lost/recreated)
    const onBackendReset = () => {
      hookInstalled = false;
    };

    // ── backend detection & creation ───────────────────────

    let backend: MirrorBackend;
    const exec = pi.exec.bind(pi);

    if (process.env.TMUX) {
      backend = new TmuxBackend(exec, onBackendReset);
    } else if (process.env.SWAYSOCK) {
      backend = new SwayBackend(exec, onBackendReset);
    } else {
      ctx.ui.notify("--mirror requires tmux or sway", "error");
      return;
    }

    const isTmux = backend instanceof TmuxBackend;
    const sessionUi = ctx.ui;

    // ── shell hook ─────────────────────────────────────────

    async function installHook(): Promise<boolean> {
      if (hookInstalled) return true;

      const shell = await backend.getShellName();
      const hook = backend.generateHookCode(shell);

      for (let attempt = 0; attempt < 2; attempt++) {
        await backend.prepareForHook();

        await backend.sendText(` ${hook} && clear`);
        await backend.sendEnter();

        // __pi_precmd fires first in the precmd chain (before direnv etc.)
        const signaled = await backend.waitForPrompt(60000);
        const { seq } = await backend.readRc();
        if (!(seq > 0 || signaled)) continue;

        // __pi_ready fires last in the precmd chain (after direnv etc.)
        // so the prompt is fully drawn when this returns
        await backend.waitForReady(60000);

        const pane = (await backend.capturePane(50)).trimEnd();
        const paneLines = pane.split("\n");
        let h = 0;
        for (let i = paneLines.length - 1; i >= 0; i--) {
          if (paneLines[i].trim()) h++;
          else break;
        }
        promptHeight = Math.min(Math.max(1, h), 4);
        const lastLine = paneLines[paneLines.length - 1].trim();
        const sym = lastLine.match(/^\S+/);
        if (sym) promptSymbol = sym[0];
        hookInstalled = true;
        return true;
      }

      return false;
    }

    // ── output extraction ──────────────────────────────────

    function isPromptLine(line: string): boolean {
      return line.trim().startsWith(promptSymbol);
    }

    function extractCommand(line: string): string {
      let cmd = line.trim().slice(promptSymbol.length).trim();
      cmd = cmd.replace(/\s*\[[\d:]+\]\s*$/, "").trim();
      return cmd;
    }

    function extractOutput(before: string, after: string): string {
      const bLines = before.split("\n");
      const aLines = after.split("\n");
      let d = 0;
      while (d < bLines.length && d < aLines.length && bLines[d] === aLines[d])
        d++;
      const lines = aLines.slice(d);

      let lastCmdIdx = -1;
      for (let i = 0; i < lines.length; i++) {
        if (isPromptLine(lines[i]) && extractCommand(lines[i])) {
          lastCmdIdx = i;
        }
      }

      if (lastCmdIdx === -1) return lines.join("\n").trim();

      const out: string[] = [];
      for (let i = lastCmdIdx + 1; i < lines.length; i++) {
        if (isPromptLine(lines[i])) break;
        if (
          i + promptHeight - 1 < lines.length &&
          isPromptLine(lines[i + promptHeight - 1])
        )
          break;
        out.push(lines[i]);
      }
      while (out.length && !out[out.length - 1].trim()) out.pop();

      return out.join("\n");
    }

    async function formatActivity(
      diff: string,
      exitCode: number,
    ): Promise<string | null> {
      const lines = diff.split("\n");

      let lastCmdIdx = -1;
      let lastCmd = "";
      for (let i = 0; i < lines.length; i++) {
        if (isPromptLine(lines[i])) {
          const cmd = extractCommand(lines[i]);
          if (cmd) {
            lastCmdIdx = i;
            lastCmd = cmd;
          }
        }
      }

      if (lastCmdIdx === -1) return null;

      const out: string[] = [];
      for (let i = lastCmdIdx + 1; i < lines.length; i++) {
        if (isPromptLine(lines[i])) break;
        if (
          i + promptHeight - 1 < lines.length &&
          isPromptLine(lines[i + promptHeight - 1])
        )
          break;
        out.push(lines[i]);
      }
      while (out.length && !out[out.length - 1].trim()) out.pop();

      const cwd = await backend.getPaneCwd();
      const home = process.env.HOME || "";
      const shortCwd =
        home && cwd.startsWith(home) ? "~" + cwd.slice(home.length) : cwd;

      let result = `${shortCwd} $ ${lastCmd}`;
      if (out.length) result += `\n${out.join("\n")}`;
      result += `\n[exit code: ${exitCode}]`;
      return result;
    }

    // ── run a command in the pane ──────────────────────────

    async function resetAll(): Promise<void> {
      hookInstalled = false;
      activeTabName = null;
      updateTabWidget();
      await backend.resetState();
    }

    async function runCommand(
      command: string,
      cwd: string,
      timeoutMs?: number,
      signal?: AbortSignal,
    ): Promise<{ output: string; exitCode: number }> {
      if (!(await installHook())) {
        return {
          output:
            "Failed to set up the shared terminal hook. The shell in the pane may not be ready.",
          exitCode: 1,
        };
      }

      const before = await backend.capturePane();
      const { seq: seqBefore } = await backend.readRc();

      const paneCwd = await backend.getPaneCwd();
      const needsCd = paneCwd !== cwd;
      let sendCmd = needsCd ? `cd ${sq(cwd)} && ${command}` : command;

      if (sendCmd.includes("\n")) {
        sendCmd = `{\n${sendCmd}\n}`;
      }

      await backend.sendText(` ${sendCmd}`);
      await backend.sendEnter();

      const timeout = timeoutMs || 120_000;
      const deadline = Date.now() + timeout;
      let exitCode = 0;
      let completed = false;

      while (Date.now() < deadline) {
        if (signal?.aborted) {
          await backend.sendCtrlC();
          return { output: "Cancelled", exitCode: 130 };
        }

        const remaining = Math.min(deadline - Date.now(), 5000);
        if (remaining <= 0) break;

        await backend.waitForAgentSignal(remaining);

        // Always check RC regardless of signal — handles cases where the
        // agent FIFO timed out (e.g. 5s polling window)
        const { seq, rc } = await backend.readRc();
        if (seq > seqBefore) {
          exitCode = rc;
          completed = true;
          break;
        }

        if (!(await backend.paneAlive())) {
          await resetAll();
          return {
            output: "Terminal pane was closed during execution.",
            exitCode: 1,
          };
        }
      }

      if (!completed) {
        await backend.sendCtrlC();
        await backend.waitForAgentSignal(5000);
      }

      const after = await backend.capturePane();
      let output = extractOutput(before, after);

      if (!completed) output += "\n[command timed out]";
      return { output, exitCode: completed ? exitCode : 124 };
    }

    // ── user activity detection ────────────────────────────

    function startActivityLoop() {
      if (activityLoopRunning || !backend.isPaneReady()) return;
      activityLoopRunning = true;
      activityAbort = new AbortController();

      (async () => {
        const { signal } = activityAbort!;
        let lastSeenSeq = (await backend.readRc()).seq;

        while (!signal.aborted && backend.isPaneReady()) {
          if (agentRunning) {
            await sleep(250);
            lastSeenSeq = (await backend.readRc()).seq;
            continue;
          }

          // Block until a command completes (zero CPU for both backends)
          const signaled = await backend.waitForPrompt(30000);
          if (signal.aborted || !backend.isPaneReady()) break;
          if (agentRunning) continue;
          if (!signaled) {
            if (!(await backend.paneAlive())) {
              await resetAll();
              break;
            }
            continue;
          }

          // Verify a new command actually completed (filters stale FIFO signals)
          const { seq: currentSeq } = await backend.readRc();
          if (currentSeq <= lastSeenSeq) continue;
          lastSeenSeq = currentSeq;

          if (agentRunning) continue;

          try {
            const dbg = (msg: string) => {
              try {
                writeFileSync(
                  "/tmp/pi-mirror-debug.log",
                  `${new Date().toISOString()} ${msg}\n`,
                  { flag: "a" },
                );
              } catch {}
            };

            dbg(
              `signaled, agentRunning=${agentRunning}, promptSymbol=${JSON.stringify(promptSymbol)}, promptHeight=${promptHeight}`,
            );

            const current = (await backend.capturePane(200)).trim();
            if (current === lastSnapshot) {
              dbg(`skip: same snapshot`);
              continue;
            }

            const bLines = lastSnapshot.split("\n");
            const aLines = current.split("\n");
            let i = 0;
            while (
              i < bLines.length &&
              i < aLines.length &&
              bLines[i] === aLines[i]
            )
              i++;
            const diff = aLines.slice(i).join("\n").trim();

            lastSnapshot = current;
            if (diff.length < 5) {
              dbg(`skip: diff too short (${diff.length})`);
              continue;
            }

            dbg(
              `diff (${diff.length} chars): ${JSON.stringify(diff.slice(0, 500))}`,
            );

            const { rc } = await backend.readRc();
            const message = await formatActivity(diff, rc);
            dbg(
              `formatActivity result: ${JSON.stringify(message?.slice(0, 300) ?? null)}`,
            );
            if (!message) continue;

            if (activeTabName !== null) {
              tabsWithActivity.add("pi-shell");
              updateTabWidget();
            }
            pi.sendMessage(
              {
                customType: "term-activity",
                content: `User activity in the shared terminal:\n\n${message}`,
                display: false,
              },
              { deliverAs: "followUp", triggerTurn: false },
            );

            while (agentRunning && !signal.aborted) await sleep(500);
            if (signal.aborted || !backend.isPaneReady()) break;

            const postAgent = (await backend.capturePane(200)).trim();
            if (postAgent !== lastSnapshot) {
              const pb = lastSnapshot.split("\n");
              const pa = postAgent.split("\n");
              let pi2 = 0;
              while (pi2 < pb.length && pi2 < pa.length && pb[pi2] === pa[pi2])
                pi2++;
              const postDiff = pa.slice(pi2).join("\n").trim();

              if (postDiff.length >= 5) {
                const { rc: postRc } = await backend.readRc();
                const postMsg = await formatActivity(postDiff, postRc);
                if (postMsg) {
                  if (activeTabName !== null) {
                    tabsWithActivity.add("pi-shell");
                    updateTabWidget();
                  }
                  pi.sendMessage(
                    {
                      customType: "term-activity",
                      content: `User activity in the shared terminal:\n\n${postMsg}`,
                      display: false,
                    },
                    { deliverAs: "followUp", triggerTurn: false },
                  );
                }
              }
            }
            lastSnapshot = (await backend.capturePane(200)).trim();
          } catch {}
        }

        activityLoopRunning = false;
      })();
    }

    function stopActivityLoop() {
      if (activityAbort) {
        activityAbort.abort();
        activityAbort = null;
      }
      backend.unblockWait().catch(() => {});
    }

    // ── process watch loop ─────────────────────────────────

    function startWatchLoop() {
      if (watchLoopRunning) return;
      watchLoopRunning = true;
      watchAbort = new AbortController();

      watchLoopDone = (async () => {
        const { signal } = watchAbort!;

        while (!signal.aborted) {
          await sleep(WATCH_INTERVAL_MS);
          if (signal.aborted) break;

          // Skip watch notifications while agent is running — followUp
          // messages queue in pi and get delivered after the turn ends,
          // potentially after the process has been stopped.
          if (agentRunning) {
            // Update snapshots so we don't send a huge accumulated diff later
            for (const [, p] of processes) {
              if (p.mode === "watch") {
                try {
                  p.lastSnapshot = (
                    await backend.captureTab(p.targetId, 200)
                  ).trim();
                } catch {}
              }
            }
            continue;
          }

          for (const [name, proc] of processes) {
            if (signal.aborted) break;
            if (stoppedProcesses.has(name)) continue;
            // Check alive for all processes (watch + quiet)
            const alive = await backend.isTabAlive(proc.targetId);
            if (!alive) {
              // If this was the active tab, recover the shell pane
              if (activeTabName === name) await recoverShellPane();

              // Process died — report and remove
              pi.sendMessage(
                {
                  customType: "term-activity",
                  content: `Process "${name}" (${proc.command}) has exited.`,
                  display: false,
                },
                { deliverAs: "followUp", triggerTurn: false },
              );
              processes.delete(name);
              updateTabWidget();
              continue;
            }

            // Only diff output for watch-mode processes
            if (proc.mode !== "watch") continue;

            const current = (
              await backend.captureTab(proc.targetId, 200)
            ).trim();
            if (current === proc.lastSnapshot) continue;

            // Re-check: process may have been stopped during captureTab
            if (!processes.has(name)) continue;

            const bLines = proc.lastSnapshot.split("\n");
            const aLines = current.split("\n");
            let i = 0;
            while (
              i < bLines.length &&
              i < aLines.length &&
              bLines[i] === aLines[i]
            )
              i++;
            const diff = aLines.slice(i).join("\n").trim();

            proc.lastSnapshot = current;
            if (diff.length < 5) continue;

            // Re-check: process may have been stopped during diff computation
            if (!processes.has(name) || stoppedProcesses.has(name)) continue;

            // Truncate very large diffs
            const maxDiffLen = 2000;
            const displayDiff =
              diff.length > maxDiffLen
                ? `[truncated: showing last ${maxDiffLen} chars of ${diff.length}]\n` +
                  diff.slice(-maxDiffLen)
                : diff;

            // Final guard: skip if process was stopped after diff was computed
            if (!processes.has(name) || stoppedProcesses.has(name)) continue;

            if (activeTabName !== name) {
              tabsWithActivity.add(name);
              updateTabWidget();
            }
            pi.sendMessage(
              {
                customType: "term-activity",
                content: `Output from process "${name}" (${proc.command}):\n\n${displayDiff}`,
                display: false,
              },
              { deliverAs: "followUp", triggerTurn: false },
            );
          }
        }

        watchLoopRunning = false;
      })();
    }

    let watchLoopDone: Promise<void> | null = null;

    function stopWatchLoop() {
      if (watchAbort) {
        watchAbort.abort();
        watchAbort = null;
      }
    }

    /** Stop the watch loop and wait for the current iteration to finish. */
    async function stopWatchLoopAndWait(): Promise<void> {
      stopWatchLoop();
      if (watchLoopDone) {
        await watchLoopDone;
        watchLoopDone = null;
      }
    }

    // ── tab switching ──────────────────────────────────────

    function updateTabWidget() {
      const tabNames = ["pi-shell", ...processes.keys()];
      const hasTabs = processes.size > 0;
      const visible = mirrorVisible;
      const theme = sessionUi.theme;

      const parts = tabNames.map((name) => {
        const isActive =
          (name === "pi-shell" && !activeTabName) || name === activeTabName;
        if (isActive) return theme.fg("accent", theme.bold(name));
        if (tabsWithActivity.has(name))
          return theme.fg("warning", theme.bold(name));
        return theme.fg("dim", name);
      });
      const tabList = parts.join(" ");

      const toggleHint = visible
        ? theme.fg("dim", "C-M-t hide")
        : theme.fg("warning", "C-M-t show");
      const tabHint = hasTabs ? theme.fg("dim", "C-M-← C-M-→") + "  " : "";
      const sep = theme.fg("border", " │ ");

      const status =
        " " +
        theme.fg("border", "[") +
        " " +
        theme.fg("dim", "Processes: ") +
        tabList +
        sep +
        tabHint +
        toggleHint +
        " " +
        theme.fg("border", "]") +
        " ";

      sessionUi.setStatus("mirror-tabs", status);
    }

    async function switchToTab(tabName: string | null): Promise<void> {
      if (tabName === activeTabName) return;
      tabsWithActivity.delete(tabName ?? "pi-shell");

      if (isTmux) {
        const tmuxBackend = backend as TmuxBackend;

        // If mirror is hidden, show it first with the target tab
        if (!mirrorVisible) {
          const targetId =
            tabName === null
              ? backend.displayTarget()
              : processes.get(tabName)?.targetId;
          if (targetId) {
            await tmuxBackend.joinPaneBelow(targetId);
            mirrorVisible = true;
            activeTabName = tabName;
            updateTabWidget();
          }
          return;
        }

        const currentId =
          activeTabName === null
            ? backend.displayTarget()
            : processes.get(activeTabName)?.targetId;
        const targetId =
          tabName === null
            ? backend.displayTarget()
            : processes.get(tabName)?.targetId;

        if (!currentId || !targetId || currentId === targetId) return;

        await tmuxBackend.swapPanes(currentId, targetId);
      } else {
        const swayBackend = backend as SwayBackend;

        // If mirror is hidden, show it first
        if (!mirrorVisible) {
          const tabIds = [...processes.values()]
            .map((p) => parseInt(p.targetId, 10))
            .filter((id) => id > 0);
          await swayBackend.showPaneFromScratchpad(tabIds);
          mirrorVisible = true;
        }

        // Focus the target container (sway manages tabbed layout natively)
        const targetId =
          tabName === null ? null : processes.get(tabName)?.targetId;

        if (tabName === null) {
          await swayBackend.focusMirrorPane();
        } else if (targetId) {
          await swayBackend.focusTab(targetId);
        }
      }

      activeTabName = tabName;
      updateTabWidget();
    }

    async function cycleTab(direction: 1 | -1): Promise<void> {
      const tabNames = ["pi-shell", ...processes.keys()];
      if (tabNames.length <= 1) return;
      const currentName = activeTabName ?? "pi-shell";
      const currentIdx = tabNames.indexOf(currentName);
      const nextIdx =
        (currentIdx + direction + tabNames.length) % tabNames.length;
      const nextName = tabNames[nextIdx];
      await switchToTab(nextName === "pi-shell" ? null : nextName);
    }

    /** Recover shell pane to mirror slot after a process pane dies in-place. */
    async function recoverShellPane(): Promise<void> {
      activeTabName = null;
      if (isTmux) {
        await (backend as TmuxBackend).rejoinMirrorPane();
      } else {
        // Sway: focus the main mirror pane
        await (backend as SwayBackend).focusMirrorPane();
      }
      updateTabWidget();
    }

    /** Toggle the mirror pane visibility (hide/show the split). */
    async function toggleMirror(): Promise<void> {
      if (isTmux) {
        const tmuxBackend = backend as TmuxBackend;

        if (mirrorVisible) {
          const paneId = activeTabName
            ? processes.get(activeTabName)?.targetId
            : backend.displayTarget();
          if (paneId) {
            await tmuxBackend.breakPaneOut(paneId);
            mirrorVisible = false;
          }
        } else {
          const paneId = activeTabName
            ? processes.get(activeTabName)?.targetId
            : backend.displayTarget();
          if (paneId) {
            await tmuxBackend.joinPaneBelow(paneId);
            mirrorVisible = true;
          }
        }
      } else {
        const swayBackend = backend as SwayBackend;

        if (mirrorVisible) {
          // Hide all mirror-related panes to scratchpad
          // Hide process tabs first, then the main pane
          for (const [, proc] of processes) {
            const tab = parseInt(proc.targetId, 10);
            if (tab > 0) {
              await swayBackend.hidePaneToScratchpad(tab);
            }
          }
          await swayBackend.hidePaneToScratchpad();
          mirrorVisible = false;
        } else {
          // Restore: bring back the main mirror pane, then tabs with tabbed layout
          const tabIds = [...processes.values()]
            .map((p) => parseInt(p.targetId, 10))
            .filter((id) => id > 0);
          await swayBackend.showPaneFromScratchpad(tabIds);
          mirrorVisible = true;
        }
      }
      updateTabWidget();
    }

    // ── register tools ─────────────────────────────────────

    pi.registerTool({
      name: "bash",
      label: `Bash (${backend.label})`,
      description:
        "Execute a bash command in a shared terminal split. The terminal is " +
        "shared with the user — they may also run commands there. Use " +
        "read_terminal to see recent terminal activity including user commands.",
      parameters: Type.Object({
        command: Type.String({ description: "Bash command to execute" }),
        timeout: Type.Optional(
          Type.Number({ description: "Timeout in seconds (default: 120)" }),
        ),
      }),
      async execute(_id, params, signal, onUpdate, ctx) {
        try {
          if (!(await backend.ensurePane())) {
            const hint =
              backend.label === "tmux"
                ? "Are you inside tmux?"
                : "Is SWAYSOCK set? Is foot available?";
            return {
              content: [
                {
                  type: "text",
                  text: `Error: could not create terminal pane. ${hint}`,
                },
              ],
              details: { command: params.command, exitCode: 1, cwd: ctx.cwd },
              isError: true,
            };
          }

          // Auto-switch to shell tab and show mirror if hidden
          if (activeTabName !== null || !mirrorVisible) await switchToTab(null);

          onUpdate?.({
            content: [
              {
                type: "text",
                text: `Running in ${backend.label} → ${backend.displayTarget()}…`,
              },
            ],
          });

          const ms = params.timeout ? params.timeout * 1000 : undefined;
          const { output, exitCode } = await runCommand(
            params.command,
            ctx.cwd,
            ms,
            signal,
          );

          if (backend.isPaneReady()) {
            lastSnapshot = (await backend.capturePane(200)).trim();
          }

          const t = truncateTail(output, {
            maxLines: DEFAULT_MAX_LINES,
            maxBytes: DEFAULT_MAX_BYTES,
          });
          let text = t.content;
          if (t.truncated) {
            text =
              `[Truncated: last ${t.outputLines} of ${t.totalLines} lines ` +
              `(${formatSize(t.outputBytes)} of ${formatSize(t.totalBytes)})]\n` +
              text;
          }
          if (!text) text = "(no output)";

          return {
            content: [{ type: "text", text }],
            details: { command: params.command, exitCode, cwd: ctx.cwd },
            isError: exitCode !== 0,
          };
        } catch (err) {
          await resetAll();
          return {
            content: [
              {
                type: "text",
                text: `term-mirror error: ${err instanceof Error ? err.message : String(err)}`,
              },
            ],
            details: { command: params.command, exitCode: 1, cwd: ctx.cwd },
            isError: true,
          };
        }
      },
    });

    pi.registerTool({
      name: "read_terminal",
      label: "Read Terminal",
      description:
        "Read recent content from the shared terminal split. Shows output " +
        "from both agent and user commands.",
      parameters: Type.Object({
        lines: Type.Optional(
          Type.Number({ description: "Lines of scrollback (default: 200)" }),
        ),
      }),
      async execute(_id, params) {
        if (!(await backend.ensurePane())) {
          return {
            content: [
              { type: "text", text: "Error: terminal pane not available" },
            ],
            isError: true,
          };
        }
        const text = (await backend.capturePane(params.lines || 200)).trim();
        return {
          content: [{ type: "text", text: text || "(terminal is empty)" }],
          details: {},
        };
      },
    });

    pi.registerTool({
      name: "start_process",
      label: "Start Process",
      description:
        "Launch a long-running process in a named tab (e.g. dev server, test watcher, REPL). " +
        "Returns immediately. Use read_process to check output, send_input to interact, " +
        "stop_process to kill it.",
      parameters: Type.Object({
        name: Type.String({
          description:
            'Short name for this process (e.g. "server", "tests", "repl")',
        }),
        command: Type.String({ description: "Command to run" }),
        mode: Type.Optional(
          Type.Union([Type.Literal("watch"), Type.Literal("quiet")], {
            description:
              'Activity reporting mode: "watch" auto-injects output changes into conversation (default), "quiet" only reports on read_process',
            default: "watch",
          }),
        ),
      }),
      async execute(_id, params, _signal, _onUpdate, ctx) {
        const name = sanitizeName(params.name);
        const mode = params.mode || "watch";

        // Check for name collision
        if (processes.has(name)) {
          const existing = processes.get(name)!;
          if (await backend.isTabAlive(existing.targetId)) {
            return {
              content: [
                {
                  type: "text",
                  text: `Process "${name}" is already running (${existing.command}). Stop it first or use a different name.`,
                },
              ],
              isError: true,
            };
          }
          // Dead process with same name — clean up
          processes.delete(name);
        }

        if (!(await backend.ensurePane())) {
          return {
            content: [
              { type: "text", text: "Error: could not create terminal pane." },
            ],
            isError: true,
          };
        }

        const targetId = await backend.createTab(name);
        if (!targetId) {
          return {
            content: [
              {
                type: "text",
                text: `Error: failed to create tab for "${name}".`,
              },
            ],
            isError: true,
          };
        }

        // Send the command.
        // New tabs start in the home directory (not the agent's cwd), so we
        // always prepend a `cd` to the correct working directory.
        // We also sleep briefly after tab creation to let the shell in the
        // new tab fully initialise — without this, tmux send-keys can hit a
        // race where the first character is duplicated (e.g. "bb foo" becomes
        // "bbb foo") because the shell isn't ready to receive input yet.
        await sleep(300);
        const fullCmd = `cd ${sq(ctx.cwd)} && ${params.command}`;

        await backend.sendTextToTab(targetId, fullCmd);
        await backend.sendEnterToTab(targetId);

        // Wait briefly for initial output
        await sleep(1000);
        const snapshot = (await backend.captureTab(targetId, 200)).trim();

        const proc: ManagedProcess = {
          name,
          command: params.command,
          targetId,
          mode,
          lastSnapshot: snapshot,
          startedAt: Date.now(),
        };
        processes.set(name, proc);
        updateTabWidget();

        // Ensure watch loop is running if we have watch processes
        if (mode === "watch" && !watchLoopRunning) {
          startWatchLoop();
        }

        return {
          content: [
            {
              type: "text",
              text: `Started "${name}" in tab (mode: ${mode}).\n\n${snapshot || "(no output yet)"}`,
            },
          ],
          details: { name, command: params.command, mode, targetId },
        };
      },
    });

    pi.registerTool({
      name: "send_input",
      label: "Send Input",
      description:
        "Send text input to a named running process (e.g. type into a REPL). " +
        "Appends Enter by default.",
      parameters: Type.Object({
        name: Type.String({ description: "Process name" }),
        text: Type.String({ description: "Text to send" }),
        enter: Type.Optional(
          Type.Boolean({
            description: "Send Enter after text (default: true)",
          }),
        ),
      }),
      async execute(_id, params) {
        const proc = processes.get(params.name);
        if (!proc) {
          return {
            content: [
              {
                type: "text",
                text: `No process named "${params.name}". Use list_processes to see active processes.`,
              },
            ],
            isError: true,
          };
        }

        if (!(await backend.isTabAlive(proc.targetId))) {
          processes.delete(params.name);
          return {
            content: [
              {
                type: "text",
                text: `Process "${params.name}" is no longer running.`,
              },
            ],
            isError: true,
          };
        }

        await backend.sendTextToTab(proc.targetId, params.text);
        if (params.enter !== false) {
          await backend.sendEnterToTab(proc.targetId);
        }

        // Wait briefly and capture output
        await sleep(500);
        const output = (await backend.captureTab(proc.targetId, 50)).trim();
        proc.lastSnapshot = (
          await backend.captureTab(proc.targetId, 200)
        ).trim();

        return {
          content: [{ type: "text", text: output || "(no output)" }],
          details: { name: params.name },
        };
      },
    });

    pi.registerTool({
      name: "read_process",
      label: "Read Process",
      description: "Read recent output from a named running process.",
      parameters: Type.Object({
        name: Type.String({ description: "Process name" }),
        lines: Type.Optional(
          Type.Number({ description: "Lines of scrollback (default: 200)" }),
        ),
      }),
      async execute(_id, params) {
        const proc = processes.get(params.name);
        if (!proc) {
          return {
            content: [
              {
                type: "text",
                text: `No process named "${params.name}". Use list_processes to see active processes.`,
              },
            ],
            isError: true,
          };
        }

        const alive = await backend.isTabAlive(proc.targetId);
        const output = (
          await backend.captureTab(proc.targetId, params.lines || 200)
        ).trim();

        const status = alive ? "running" : "exited";

        if (!alive) {
          // Clean up dead process
          processes.delete(params.name);
          const hasWatch = [...processes.values()].some(
            (p) => p.mode === "watch",
          );
          if (!hasWatch) stopWatchLoop();
        } else {
          proc.lastSnapshot = output;
        }

        return {
          content: [
            {
              type: "text",
              text: `[${proc.name}: ${status}]\n${output || "(no output)"}`,
            },
          ],
          details: { name: params.name, status },
        };
      },
    });

    pi.registerTool({
      name: "stop_process",
      label: "Stop Process",
      description:
        "Stop a named running process (sends Ctrl+C, then kills the tab).",
      parameters: Type.Object({
        name: Type.String({ description: "Process name" }),
      }),
      async execute(_id, params) {
        const proc = processes.get(params.name);
        if (!proc) {
          return {
            content: [
              { type: "text", text: `No process named "${params.name}".` },
            ],
            isError: true,
          };
        }

        // Mark as stopped immediately so the watch loop won't send any
        // more notifications, even for already-computed diffs.
        stoppedProcesses.add(params.name);
        processes.delete(params.name);
        updateTabWidget();

        // Switch to shell tab before closing (so mirror slot keeps the shell)
        if (activeTabName === params.name) await switchToTab(null);

        let finalOutput = "";
        if (await backend.isTabAlive(proc.targetId)) {
          await backend.sendCtrlCToTab(proc.targetId);
          await sleep(1000);
          finalOutput = (await backend.captureTab(proc.targetId, 50)).trim();
          await backend.closeTab(proc.targetId);
        }

        // Stop watch loop if no more watch processes, and wait for
        // the current iteration to finish so no stale messages leak.
        const hasWatch = [...processes.values()].some(
          (p) => p.mode === "watch",
        );
        if (!hasWatch) await stopWatchLoopAndWait();

        return {
          content: [
            {
              type: "text",
              text: `Stopped "${params.name}".${finalOutput ? "\n\n" + finalOutput : ""}`,
            },
          ],
          details: { name: params.name },
        };
      },
    });

    pi.registerTool({
      name: "list_processes",
      label: "List Processes",
      description: "List all managed background processes and their status.",
      parameters: Type.Object({}),
      async execute() {
        if (processes.size === 0) {
          return {
            content: [{ type: "text", text: "No managed processes running." }],
            details: {},
          };
        }

        const lines: string[] = [];
        for (const [name, proc] of processes) {
          const alive = await backend.isTabAlive(proc.targetId);
          const status = alive ? "running" : "exited";
          const age = Math.round((Date.now() - proc.startedAt) / 1000);
          lines.push(
            `  ${name}: ${proc.command} [${status}, ${proc.mode}, ${age}s]`,
          );
        }

        return {
          content: [
            { type: "text", text: `Managed processes:\n${lines.join("\n")}` },
          ],
          details: { count: processes.size },
        };
      },
    });

    // ── register shortcuts ─────────────────────────────────

    pi.registerShortcut("ctrl+alt+left", {
      description: "Previous mirror tab",
      handler: async () => {
        await cycleTab(-1);
      },
    });
    pi.registerShortcut("ctrl+alt+right", {
      description: "Next mirror tab",
      handler: async () => {
        await cycleTab(1);
      },
    });
    pi.registerShortcut("ctrl+alt+t", {
      description: "Toggle mirror pane",
      handler: async () => {
        await toggleMirror();
      },
    });

    // ── register event handlers ────────────────────────────

    pi.on("agent_start", async () => {
      agentRunning = true;
      // Release any pending activity loop FIFO reader so runCommand
      // is the sole reader. The await yields to the event loop,
      // letting the activity loop see agentRunning=true and stop.
      await backend.unblockWait();
    });

    pi.on("agent_end", () => {
      agentRunning = false;
    });

    pi.on("session_shutdown", async () => {
      stopActivityLoop();
      stopWatchLoop();
      // Swap shell back to mirror slot before closing process tabs
      if (activeTabName !== null) {
        try {
          await switchToTab(null);
        } catch {}
      }
      // Close all managed process tabs
      for (const [, proc] of processes) {
        await backend.closeTab(proc.targetId).catch(() => {});
      }
      processes.clear();
      await backend.killPane();
      sessionUi.setStatus("mirror-tabs", undefined);
      backend.cleanup();
    });

    // ── activate: set up pane, hook, activity loop ─────────

    const ok = await backend.ensurePane();
    if (ok) {
      await installHook();
      lastSnapshot = (await backend.capturePane(200)).trim();
      startActivityLoop();

      // Start with the mirror pane hidden
      if (isTmux) {
        const paneId = backend.displayTarget();
        if (paneId) {
          await (backend as TmuxBackend).breakPaneOut(paneId);
        }
      } else {
        await (backend as SwayBackend).hidePaneToScratchpad();
      }
      mirrorVisible = false;

      updateTabWidget();
      ctx.ui.notify(
        `Shared ${backend.label} pane → ${backend.displayTarget()}`,
        "info",
      );
    }
  });
}
