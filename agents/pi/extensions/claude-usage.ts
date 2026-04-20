/**
 * Claude Usage Monitor
 *
 * Scrapes https://claude.ai/settings/usage at regular intervals via the Chrome
 * DevTools Protocol (requires Chromium running with --remote-debugging-port=9222
 * and an active claude.ai session).
 *
 * Status bar: always-visible usage % (highest model utilisation).
 * Overlay:    full per-model breakdown, toggled with ctrl+shift+u or /usage.
 *
 * Poll interval: 15 minutes — weekly limits don't change fast enough to warrant
 * anything shorter, and this avoids hammering the page during active work.
 */

import type { ExtensionAPI, Theme } from "@mariozechner/pi-coding-agent";
import { matchesKey } from "@mariozechner/pi-tui";

// ─── Config ───────────────────────────────────────────────────────────────────

const POLL_MS = 15 * 60 * 1000; // 15 minutes
const CDP_BASE = "http://localhost:9222";
const USAGE_URL = "https://claude.ai/settings/usage";
const STATUS_KEY = "claude-usage";

// ─── Types ────────────────────────────────────────────────────────────────────

interface ModelStat {
  model: string;
  used: number;
  total: number | null;
  pct: number | null;
  resetsAt: string | null;
}

interface UsageData {
  stats: ModelStat[];
  plan: string | null;
  updatedAt: Date;
  error?: string;
}

// ─── CDP helpers ──────────────────────────────────────────────────────────────

async function cdpListTabs(): Promise<any[]> {
  try {
    const r = await fetch(`${CDP_BASE}/json/list`);
    return r.ok ? ((await r.json()) as any[]) : [];
  } catch {
    return [];
  }
}

async function cdpNewTab(url: string): Promise<{ wsUrl: string; id: string } | null> {
  try {
    const r = await fetch(`${CDP_BASE}/json/new?${encodeURIComponent(url)}`);
    if (!r.ok) return null;
    const tab = (await r.json()) as any;
    const wsUrl: string = tab.webSocketDebuggerUrl;
    const id: string = tab.id;
    return wsUrl && id ? { wsUrl, id } : null;
  } catch {
    return null;
  }
}

async function cdpCloseTab(id: string): Promise<void> {
  try {
    await fetch(`${CDP_BASE}/json/close/${id}`);
  } catch {}
}

/** Execute an async JS expression in a CDP tab and return the result value. */
function cdpEval(wsUrl: string, expression: string, timeoutMs = 20_000): Promise<any> {
  return new Promise((resolve, reject) => {
    let ws: WebSocket;
    const deadline = setTimeout(() => {
      try { ws.close(); } catch {}
      reject(new Error("CDP eval timeout"));
    }, timeoutMs);

    ws = new WebSocket(wsUrl);

    ws.addEventListener("open", () => {
      ws.send(JSON.stringify({
        id: 1,
        method: "Runtime.evaluate",
        params: { expression, awaitPromise: true, returnByValue: true, timeout: timeoutMs - 2000 },
      }));
    });

    ws.addEventListener("message", (evt) => {
      const msg = JSON.parse(evt.data as string) as any;
      if (msg.id !== 1) return;
      clearTimeout(deadline);
      try { ws.close(); } catch {}
      if (msg.error) {
        reject(new Error(String(msg.error.message ?? msg.error)));
      } else if (msg.result?.exceptionDetails) {
        reject(new Error(String(msg.result.exceptionDetails.text ?? "script exception")));
      } else {
        resolve(msg.result?.result?.value);
      }
    });

    ws.addEventListener("error", () => {
      clearTimeout(deadline);
      reject(new Error("CDP WebSocket error — is Chrome running with --remote-debugging-port=9222?"));
    });
  });
}

// ─── Scraping ─────────────────────────────────────────────────────────────────

/**
 * Runs inside the claude.ai/settings/usage page context.
 * Waits for React to render, then extracts usage data from the DOM.
 * Returns a JSON string.
 */
const EXTRACT_SCRIPT = `
(async () => {
  // Wait for meaningful content to appear (React render)
  const waitFor = (pred, ms = 12000) => new Promise((res) => {
    if (pred()) return res(undefined);
    const t = setTimeout(() => { obs.disconnect(); res(undefined); }, ms);
    const obs = new MutationObserver(() => { if (pred()) { clearTimeout(t); obs.disconnect(); res(undefined); } });
    obs.observe(document.body, { childList: true, subtree: true });
  });

  await waitFor(() => {
    const text = document.body.innerText;
    return text.length > 500 && (
      /usage/i.test(text) ||
      document.querySelector('[role="progressbar"], progress') !== null
    );
  });

  // Additional settle time for progress bars to populate
  await new Promise(r => setTimeout(r, 500));

  // Collect progress bar data
  const bars = Array.from(document.querySelectorAll('[role="progressbar"], progress')).map(el => {
    const val = el.getAttribute('aria-valuenow') ?? el.getAttribute('value');
    const max = el.getAttribute('aria-valuemax') ?? el.getAttribute('max');
    // Walk up to find a label
    let label = '';
    let node = el.parentElement;
    for (let i = 0; i < 6 && node; i++, node = node.parentElement) {
      const t = node.innerText?.trim();
      if (t && t.length > 2 && t.length < 120) { label = t; break; }
    }
    return { val, max, label };
  });

  const bodyText = document.body.innerText.substring(0, 6000);
  const plan = (bodyText.match(/\\b(Pro|Team|Enterprise|Free)\\b/i) ?? [])[1] ?? null;

  return JSON.stringify({ bars, bodyText, plan, url: location.href });
})()
`;

function parseUsageData(raw: string): UsageData {
  try {
    const { bars, bodyText, plan } = JSON.parse(raw) as {
      bars: { val: string | null; max: string | null; label: string }[];
      bodyText: string;
      plan: string | null;
    };
    const stats: ModelStat[] = [];

    // 1. Progress bar elements
    for (const bar of bars) {
      if (bar.val == null || bar.max == null) continue;
      const used = parseFloat(bar.val);
      const total = parseFloat(bar.max);
      if (isNaN(used) || isNaN(total) || total <= 0) continue;
      const pct = Math.min(100, Math.round((used / total) * 100));
      // Extract model name from label (first non-empty line)
      const model = (bar.label.split("\n").map((s) => s.trim()).find((s) => s.length > 0) ?? "Usage").substring(0, 60);
      stats.push({ model, used, total, pct, resetsAt: null });
    }

    // 2. Text patterns ("X of Y messages", "X/Y")
    if (stats.length === 0) {
      const lines = bodyText.split("\n");
      let currentModel = "Claude";
      for (const raw of lines) {
        const line = raw.trim();
        if (/claude\s+(opus|sonnet|haiku|3|3\.5)/i.test(line)) currentModel = line.substring(0, 60);
        const m = line.match(/(\d[\d,]*)\s+(?:of|\/)\s+(\d[\d,]*)\s*(?:messages?|requests?|msg)?/i);
        if (m) {
          const used = parseInt(m[1].replace(/,/g, ""), 10);
          const total = parseInt(m[2].replace(/,/g, ""), 10);
          if (!isNaN(used) && !isNaN(total) && total > 0) {
            stats.push({ model: currentModel, used, total, pct: Math.min(100, Math.round((used / total) * 100)), resetsAt: null });
          }
        }
      }
    }

    // 3. Bare percentage fallback
    if (stats.length === 0) {
      const pctMatch = bodyText.match(/(\d{1,3})%/);
      if (pctMatch) {
        const pct = parseInt(pctMatch[1], 10);
        stats.push({ model: "Usage", used: pct, total: 100, pct, resetsAt: null });
      }
    }

    // Try to annotate reset time
    const resetMatch = bodyText.match(/resets?\s+(?:in|on|at)\s+([^\n.,(]{3,40})/i);
    if (resetMatch && stats.length > 0) {
      stats[stats.length - 1]!.resetsAt = resetMatch[1].trim();
    }

    return { stats, plan, updatedAt: new Date() };
  } catch (e: any) {
    return { stats: [], plan: null, updatedAt: new Date(), error: `Parse error: ${e.message}` };
  }
}

async function fetchUsageData(): Promise<UsageData> {
  try {
    const tabs = await cdpListTabs();
    const existing = tabs.find(
      (t: any) => t.type === "page" && (t.url as string)?.includes("claude.ai/settings/usage") && t.webSocketDebuggerUrl,
    );

    let wsUrl: string;
    let newTabId: string | null = null;

    if (existing) {
      wsUrl = existing.webSocketDebuggerUrl as string;
    } else {
      // Check for any authenticated claude.ai tab — use it to navigate
      const anyClaudeTab = tabs.find((t: any) => t.type === "page" && (t.url as string)?.includes("claude.ai") && t.webSocketDebuggerUrl);
      if (anyClaudeTab) {
        // Open settings/usage as a new tab (shares the session)
        const newTab = await cdpNewTab(USAGE_URL);
        if (!newTab) return { stats: [], plan: null, updatedAt: new Date(), error: "Failed to open CDP tab" };
        wsUrl = newTab.wsUrl;
        newTabId = newTab.id;
        // Give the page a head start loading
        await new Promise((r) => setTimeout(r, 2500));
      } else {
        return { stats: [], plan: null, updatedAt: new Date(), error: "No claude.ai tab found — open claude.ai in Chrome" };
      }
    }

    const raw = await cdpEval(wsUrl, EXTRACT_SCRIPT);

    if (newTabId) await cdpCloseTab(newTabId);

    if (!raw) return { stats: [], plan: null, updatedAt: new Date(), error: "Empty response from page" };
    return parseUsageData(raw as string);
  } catch (e: any) {
    return { stats: [], plan: null, updatedAt: new Date(), error: e.message };
  }
}

// ─── Overlay ──────────────────────────────────────────────────────────────────

class UsageOverlay {
  readonly width = 58;
  focused = false;

  constructor(
    private data: UsageData,
    private done: (v: undefined) => void,
    private theme: Theme,
  ) {}

  handleInput(data: string): void {
    if (matchesKey(data, "escape") || matchesKey(data, "return") || data === "q" || data === "u") {
      this.done(undefined);
    }
  }

  render(_width: number): string[] {
    const th = this.theme;
    const w = this.width;
    const inner = w - 2; // chars between │ and │
    const lines: string[] = [];

    const ansiStrip = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, "");
    const pad = (s: string, len: number) => s + " ".repeat(Math.max(0, len - ansiStrip(s).length));
    const row = (content: string) => th.fg("border", "│") + pad(` ${content}`, inner) + th.fg("border", "│");
    const div = th.fg("border", `├${"─".repeat(inner)}┤`);

    lines.push(th.fg("border", `╭${"─".repeat(inner)}╮`));
    lines.push(row(th.bold(th.fg("accent", "Claude.ai Usage"))));
    if (this.data.plan) lines.push(row(th.fg("dim", `Plan: ${this.data.plan}`)));
    lines.push(row(th.fg("dim", `Updated: ${this.data.updatedAt.toLocaleTimeString()}`)));
    lines.push(div);

    if (this.data.error) {
      lines.push(row(th.fg("error", `✗ ${this.data.error}`)));
    } else if (this.data.stats.length === 0) {
      lines.push(row(th.fg("muted", "No usage data found on page")));
    } else {
      const BAR = 36;
      for (const stat of this.data.stats) {
        lines.push(row(th.fg("text", stat.model)));
        const pct = stat.pct ?? 0;
        const color = pct >= 90 ? "error" : pct >= 70 ? "warning" : "success";
        const filled = Math.round((pct / 100) * BAR);
        const bar = th.fg(color, "█".repeat(filled)) + th.fg("dim", "░".repeat(BAR - filled));
        lines.push(row(`[${bar}]`));
        const countStr = stat.total != null ? `${stat.used} / ${stat.total}` : `${stat.used} used`;
        lines.push(row(`  ${th.fg(color, `${pct}%`)}  ${th.fg("dim", countStr)}`));
        if (stat.resetsAt) lines.push(row(th.fg("dim", `  Resets: ${stat.resetsAt}`)));
        lines.push(row(""));
      }
    }

    lines.push(div);
    lines.push(row(th.fg("dim", "Esc / Enter / q — close   u — close")));
    lines.push(th.fg("border", `╰${"─".repeat(inner)}╯`));
    return lines;
  }

  invalidate(): void {}
  dispose(): void {}
}

// ─── Extension entry ──────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  let data: UsageData = { stats: [], plan: null, updatedAt: new Date(0) };
  let timer: ReturnType<typeof setInterval> | null = null;
  let overlayOpen = false;

  // Stored so the interval timer can update the status bar
  let cachedCtx: any = null;

  function statusText(theme: Theme, d: UsageData): string {
    if (d.error) return theme.fg("error", "usage:err");
    if (d.stats.length === 0) return d.updatedAt.getTime() === 0 ? theme.fg("dim", "usage:—") : theme.fg("muted", "usage:?");
    const top = d.stats.reduce((a, b) => ((b.pct ?? 0) > (a.pct ?? 0) ? b : a));
    const pct = top.pct ?? 0;
    const color = pct >= 90 ? "error" : pct >= 70 ? "warning" : "success";
    return theme.fg(color, `usage:${pct}%`);
  }

  async function refresh(): Promise<void> {
    if (!cachedCtx) return;
    data = await fetchUsageData();
    cachedCtx.ui.setStatus(STATUS_KEY, statusText(cachedCtx.ui.theme, data));
  }

  async function showOverlay(ctx: any): Promise<void> {
    if (overlayOpen) return;
    overlayOpen = true;
    try {
      await ctx.ui.custom<undefined>(
        (_tui: any, theme: Theme, _kb: any, done: (v: undefined) => void) => new UsageOverlay(data, done, theme),
        { overlay: true },
      );
    } finally {
      overlayOpen = false;
    }
  }

  pi.on("session_start", async (_event, ctx) => {
    cachedCtx = ctx;
    ctx.ui.setStatus(STATUS_KEY, statusText(ctx.ui.theme, data));
    // Initial fetch (non-blocking — don't delay session start)
    refresh().catch(() => {});
    timer = setInterval(() => refresh().catch(() => {}), POLL_MS);
  });

  pi.on("session_shutdown", async () => {
    if (timer) { clearInterval(timer); timer = null; }
    cachedCtx = null;
  });

  pi.registerShortcut("ctrl+shift+u", {
    description: "Toggle Claude usage overlay",
    handler: async (ctx) => {
      cachedCtx = ctx;
      await showOverlay(ctx);
    },
  });

  pi.registerCommand("usage", {
    description: "Refresh and show Claude usage stats",
    handler: async (_args, ctx) => {
      cachedCtx = ctx;
      ctx.ui.notify("Fetching usage data…", "info");
      await refresh();
      await showOverlay(ctx);
    },
  });
}
