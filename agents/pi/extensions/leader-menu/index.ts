/**
 * leader-menu extension for pi — which-key-style leader chord discovery.
 *
 * Owns the Space and `,` leader menus, the `alt+space` / `alt+,` global
 * shortcuts, the `/leader-menu` slash command, and the cross-extension
 * registration API used by every other extension to contribute its own
 * sub-menus. Has no opinion on modal editing — the optional vim layer
 * lives in the sibling `vim-mode` extension and toggles via a pair of
 * cross-extension events documented below.
 *
 * Events:
 *   in   leader-menu:register   — extensions contribute leader entries
 *                                  (use `registerLeaderMenu()` from
 *                                   `lib/pi-utils.ts`, not raw events).
 *   in   leader-menu:open       — request the leader overlay open at
 *                                  a given root key. Used by vim-mode
 *                                  to delegate bare-Space/`,` handling
 *                                  in Normal mode. Payload:
 *                                  `{ rootKey: " " | "," }`.
 *   out  leader-menu:ready      — emitted once on session_start so
 *                                  consumers re-register after reload.
 *   out  vim-mode:enable        — emitted from `Space t E v`
 *                                  (or any `vim-mode:enable` action).
 *   out  vim-mode:disable       — emitted from `Space t E e`.
 *
 * Slash commands:
 *   /leader-menu bindings           — interactive overlay listing all
 *                                     registered leader chords.
 *   /leader-menu bindings --export  — print every chord as an org table
 *                                     suitable for pasting into a doc.
 *
 * Settings:
 *   This extension has no user settings of its own. Modal-editing
 *   preferences live in `vim-mode`. `defaults.json` is the immutable
 *   default leader-menu definition; do not write user state to it.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import type { KeybindingsManager } from "@mariozechner/pi-coding-agent";
import {
  matchesKey,
  truncateToWidth,
  type Component,
  type TUI,
} from "@mariozechner/pi-tui";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { ansiPad } from "../lib/pi-utils.js";

const EXT_DIR = dirname(fileURLToPath(import.meta.url));

// ─── Types ───────────────────────────────────────────────────────────

/** A node in the leader-menu tree. */
type LeaderNode = {
  key?: string;
  label: string;
} & (
  | { children: LeaderEntry[]; action?: never }
  | { action: () => void; children?: never }
);

type LeaderEntry = LeaderNode & { key: string };

interface MenuItemConfig {
  label: string;
  action?: string;
  items?: Record<string, MenuItemConfig>;
}

interface MenuConfig {
  label: string;
  key: string;
  items: Record<string, MenuItemConfig>;
}

/** JSON config shape shared by `defaults.json` and registrations. */
interface LeaderMenuConfig {
  menus?: Record<string, MenuConfig>;
}

/**
 * Payload accepted by the `leader-menu:register` event. Extensions
 * should use the `registerLeaderMenu()` helper from `lib/pi-utils.ts`
 * rather than emitting this directly.
 */
interface LeaderMenuRegistration extends LeaderMenuConfig {
  /** Originating extension name; used in clash warnings. */
  source?: string;
}

/** Bridge between menu actions and pi APIs. */
interface LeaderActionHost {
  submitCommand(command: string): void;
  passthrough(keyName: string, seq: string): void;
  emitEvent(eventName: string): void;
}

/** Map of `passthrough:` action key names to terminal escape sequences. */
const PASSTHROUGH_KEYS: Record<string, string> = {
  "ctrl+l": "\x0c",
  "ctrl+o": "\x0f",
  "ctrl+t": "\x14",
  "ctrl+g": "\x07",
  "shift+tab": "\x1b[Z",
};

/**
 * Keys consumed by the `vim-mode` extension's normal-mode dispatcher.
 *
 * Used solely to warn at registration time when a contributed leader
 * trigger key would be silently swallowed by the vim grammar. Keep in
 * sync with the modal extension's reserved-key set
 * (`agents/pi/extensions/vim-mode/index.ts`); they're duplicated by
 * design rather than imported so this extension stays usable in
 * insert-only configurations where vim-mode isn't loaded.
 */
const VIM_NORMAL_RESERVED_KEYS = new Set([
  // motions
  "h", "l", "j", "k", "w", "W", "e", "E", "b", "B", "0", "$", "^",
  // mode switches
  "i", "a", "I", "A", "o", "O", "v", "V",
  // operators
  "d", "c", "y", ">", "<",
  // find character
  "f", "F", "t", "T",
  // repeat find
  ";", ",",
  // single-key commands
  "x", "X", "r", "s", "S", "p", "P", "u", ".", "J", "~", "D", "C", "Y",
]);

// ─── Helpers ─────────────────────────────────────────────────────────

function displayKey(key: string): string {
  if (key === " ") return "SPC";
  if (key === "\t") return "TAB";
  return key;
}

function keyMatches(data: string, configured: string): boolean {
  if (data === configured) return true;
  const keyName = configured === " " ? "space" : configured;
  return matchesKey(data, keyName);
}

function loadDefaults(): LeaderMenuConfig {
  const path = join(EXT_DIR, "defaults.json");
  if (!existsSync(path)) return {};
  try {
    return JSON.parse(readFileSync(path, "utf-8"));
  } catch {
    return {};
  }
}

/**
 * Warn for leader trigger keys that clash with vim-mode's normal-mode
 * grammar. Soft warning — registration still proceeds; the binding
 * just won't fire when modal editing is active.
 */
function warnClashingLeaderKeys(
  menus: Map<string, LeaderNode>,
  source: string,
  notify?: (msg: string, level: "info" | "warning" | "error") => void,
): void {
  if (!notify) return;
  for (const [triggerKey, node] of menus) {
    if (VIM_NORMAL_RESERVED_KEYS.has(triggerKey)) {
      const label = node.label ?? triggerKey;
      notify(
        `leader-menu: trigger key "${displayKey(triggerKey)}" ` +
          `("${label}" from ${source}) clashes with vim-mode's ` +
          `normal-mode grammar and will not fire while modal is on`,
        "warning",
      );
    }
  }
}

function buildAction(actionStr: string, host: LeaderActionHost): () => void {
  if (actionStr.startsWith("command:")) {
    const cmd = actionStr.slice("command:".length);
    return () => host.submitCommand(cmd);
  }
  if (actionStr.startsWith("passthrough:")) {
    const keyName = actionStr.slice("passthrough:".length);
    const seq = PASSTHROUGH_KEYS[keyName] ?? "";
    return () => host.passthrough(keyName, seq);
  }
  // Default: emit as event (with optional `event:` prefix for legacy
  // configs). Bare names are treated as event names — this is how
  // `vim-mode:enable` and `vim-mode:disable` reach the modal extension.
  if (!actionStr) return () => {};
  const eventName = actionStr.startsWith("event:")
    ? actionStr.slice("event:".length)
    : actionStr;
  return () => host.emitEvent(eventName);
}

function buildMenuNode(
  config: MenuItemConfig,
  key: string,
  host: LeaderActionHost,
): LeaderEntry {
  if (config.items) {
    const children = Object.entries(config.items).map(
      ([k, item]) => buildMenuNode(item, k, host),
    );
    return { key, label: config.label, children };
  }
  return { key, label: config.label, action: buildAction(config.action ?? "", host) };
}

function buildMenuTree(
  config: LeaderMenuConfig,
  host: LeaderActionHost,
): Map<string, LeaderNode> {
  const menus = new Map<string, LeaderNode>();
  if (!config.menus) return menus;
  for (const [_name, menuConfig] of Object.entries(config.menus)) {
    const children = Object.entries(menuConfig.items).map(
      ([k, item]) => buildMenuNode(item, k, host),
    );
    menus.set(menuConfig.key, { label: menuConfig.label, children });
  }
  return menus;
}

/**
 * Recursively merge incoming registration children into existing.
 * Same-key, same-label entries are deduped silently (re-register on
 * `leader-menu:ready` is idempotent). Conflicts log a warning and
 * keep the existing entry.
 */
function mergeChildren(
  existing: LeaderEntry[],
  incoming: LeaderEntry[],
  pathPrefix: string,
  source: string,
  warn: (msg: string, level: "info" | "warning" | "error") => void,
): void {
  for (const child of incoming) {
    const idx = existing.findIndex((c) => c.key === child.key);
    if (idx < 0) {
      existing.push(child);
      continue;
    }
    const existingChild = existing[idx]!;
    const keyPath = `${pathPrefix} ${child.key}`;
    if (existingChild.children && child.children) {
      mergeChildren(existingChild.children, child.children, keyPath, source, warn);
    } else if (existingChild.label === child.label) {
      // Idempotent re-register — silent.
      continue;
    } else {
      warn(
        `leader-menu: ignoring contribution [${keyPath}] ` +
          `("${child.label}" from ${source}) — clashes with existing ` +
          `binding "${existingChild.label}"`,
        "warning",
      );
    }
  }
}

function applyRegistration(
  menus: Map<string, LeaderNode>,
  host: LeaderActionHost,
  config: LeaderMenuRegistration,
  notify?: (msg: string, level: "info" | "warning" | "error") => void,
): void {
  if (!config?.menus) return;
  const incoming = buildMenuTree(config, host);
  const source = config.source ?? "unknown";
  const warn = notify ?? ((_m: string, _l: "info" | "warning" | "error") => {});
  warnClashingLeaderKeys(incoming, source, warn);
  for (const [triggerKey, incomingNode] of incoming) {
    const current = menus.get(triggerKey);
    if (!current || !current.children) {
      menus.set(triggerKey, incomingNode);
    } else {
      mergeChildren(
        current.children,
        incomingNode.children ?? [],
        triggerKey,
        source,
        warn,
      );
    }
  }
  warn(`leader-menu: applied for ${source}`, "info");
}

// ─── Bindings export (org-format) ────────────────────────────────────

/**
 * Render every registered chord as an org-mode table, replacing the
 * hand-maintained `extensions/keybindings.org` file.
 *
 * Output groups by menu (`Space`, `,`) and produces one table per
 * menu, listing chord-path → label → action source where derivable.
 */
function exportBindingsAsOrg(menus: Map<string, LeaderNode>): string {
  const lines: string[] = [
    "#+TITLE: Pi Extension Leader Bindings",
    "",
    "Auto-generated by =/leader-menu bindings --export=. Do not edit by hand.",
    "",
  ];
  for (const [triggerKey, node] of menus) {
    const root = displayKey(triggerKey);
    lines.push(`* ${root} \u2014 ${node.label}`);
    lines.push("");
    lines.push("| Chord | Label |");
    lines.push("|-------+-------|");
    const walk = (entries: LeaderEntry[], path: string[]) => {
      for (const entry of entries) {
        const chord = [...path, displayKey(entry.key)].join(" ");
        const isMenu = !!entry.children;
        const label = isMenu ? `+${entry.label}` : entry.label;
        lines.push(`| =${chord}= | ${label} |`);
        if (entry.children) walk(entry.children, [...path, displayKey(entry.key)]);
      }
    };
    walk(node.children ?? [], [root]);
    lines.push("");
  }
  return lines.join("\n");
}

// ─── Overlays ────────────────────────────────────────────────────────

class LeaderMenuOverlay implements Component {
  private activeNode: LeaderNode | null = null;
  private path: string[] = [];

  constructor(
    private tui: TUI,
    private menus: Map<string, LeaderNode>,
    private theme: any,
    private done: () => void,
    initialRootKey?: string,
  ) {
    if (initialRootKey && menus.has(initialRootKey)) {
      this.activeNode = menus.get(initialRootKey)!;
      this.path = [displayKey(initialRootKey)];
    }
  }

  handleInput(data: string): boolean {
    if (matchesKey(data, "escape") || matchesKey(data, "ctrl+c")) {
      this.done();
      return true;
    }
    if (!this.activeNode) {
      const root = [...this.menus.entries()].find(([key]) => keyMatches(data, key));
      if (!root) return true;
      this.activeNode = root[1];
      this.path = [displayKey(root[0])];
      this.tui.requestRender();
      return true;
    }
    const match = this.activeNode.children?.find((entry) => keyMatches(data, entry.key));
    if (!match) {
      this.done();
      return true;
    }
    if ("children" in match && match.children) {
      this.activeNode = match;
      this.path.push(displayKey(match.key));
      this.tui.requestRender();
      return true;
    }
    if ("action" in match && match.action) {
      match.action();
    }
    this.done();
    return true;
  }

  render(width: number): string[] {
    const node = this.activeNode;
    const entries = node?.children ?? [...this.menus.entries()].map(([key, root]) => ({
      key,
      label: root.label ?? displayKey(key),
      children: root.children,
    } as LeaderEntry));
    const title = node?.label ?? "Leader";
    const path = this.path.length > 0 ? ` (${this.path.join(" ")})` : "";
    const innerW = Math.max(20, Math.min(width - 4, 72));
    const hBar = "─".repeat(innerW + 2);
    const lines = [`╭${hBar}╮`];
    lines.push(`│ ${ansiPad(this.theme.bold ? this.theme.bold(title + path) : title + path, innerW)} │`);
    lines.push(`│ ${ansiPad("", innerW)} │`);
    for (const entry of entries) {
      const suffix = entry.children ? " →" : "";
      const keyStr = this.theme.fg ? this.theme.fg("accent", displayKey(entry.key)) : displayKey(entry.key);
      const labelStr = this.theme.fg
        ? this.theme.fg("muted", entry.label + suffix)
        : entry.label + suffix;
      lines.push(`│ ${ansiPad(`${keyStr}  ${labelStr}`, innerW)} │`);
    }
    lines.push(`╰${hBar}╯`);
    return lines;
  }

  invalidate(): void {
    this.tui.requestRender();
  }
}

class BindingsOverlay {
  private flatLines: { prefix: string; label: string; depth: number }[] = [];
  private scrollOffset = 0;
  private selected = 0;
  private cachedWidth?: number;
  private cachedLines?: string[];

  constructor(
    menus: Map<string, LeaderNode>,
    private theme: any,
    private done: () => void,
  ) {
    this.flatten(menus);
  }

  private flatten(menus: Map<string, LeaderNode>): void {
    const walk = (entries: LeaderEntry[], path: string[], depth: number) => {
      for (const entry of entries) {
        const keyPath = [...path, displayKey(entry.key)];
        this.flatLines.push({ prefix: keyPath.join(" "), label: entry.label, depth });
        if (entry.children) walk(entry.children, keyPath, depth + 1);
      }
    };
    for (const [triggerKey, node] of menus) {
      const rootKey = displayKey(triggerKey);
      if (node.children) {
        this.flatLines.push({ prefix: rootKey, label: node.label ?? "Leader", depth: 0 });
        walk(node.children, [rootKey], 1);
      }
    }
  }

  handleInput(data: string): void {
    if (matchesKey(data, "escape") || matchesKey(data, "q")) {
      this.done();
      return;
    }
    if (matchesKey(data, "up") || matchesKey(data, "k")) {
      if (this.selected > 0) { this.selected--; this.invalidate(); }
      return;
    }
    if (matchesKey(data, "down") || matchesKey(data, "j")) {
      if (this.selected < this.flatLines.length - 1) { this.selected++; this.invalidate(); }
      return;
    }
  }

  render(width: number): string[] {
    if (this.cachedLines && this.cachedWidth === width) return this.cachedLines;
    const th = this.theme;
    const innerW = width - 4;
    const lines: string[] = [];
    const hBar = (n: number) => "─".repeat(Math.max(0, n));
    const topBorder = th.fg("border", `╭${hBar(width - 2)}╮`);
    const botBorder = th.fg("border", `╰${hBar(width - 2)}╯`);
    const row = (content: string) =>
      th.fg("border", "│") + " " + ansiPad(content, innerW) + " " + th.fg("border", "│");
    const emptyRow = () => row("");
    lines.push(topBorder);
    lines.push(row(th.fg("accent", th.bold("Leader bindings"))));
    lines.push(emptyRow());
    if (this.flatLines.length === 0) {
      lines.push(row(th.fg("dim", "No leader bindings registered.")));
      lines.push(emptyRow());
      lines.push(row(th.fg("dim", "Press Esc or q to close")));
      lines.push(botBorder);
      this.cachedWidth = width; this.cachedLines = lines;
      return lines;
    }
    const maxVisible = 20;
    if (this.selected < this.scrollOffset) this.scrollOffset = this.selected;
    if (this.selected >= this.scrollOffset + maxVisible)
      this.scrollOffset = this.selected - maxVisible + 1;
    const visible = this.flatLines.slice(this.scrollOffset, this.scrollOffset + maxVisible);
    for (let i = 0; i < visible.length; i++) {
      const entry = visible[i]!;
      const globalIdx = this.scrollOffset + i;
      const isSelected = globalIdx === this.selected;
      const indent = "  ".repeat(entry.depth);
      const keyStr = th.fg("accent", entry.prefix.padEnd(16));
      const labelStr = isSelected ? th.fg("text", entry.label) : th.fg("muted", entry.label);
      const pointer = isSelected ? th.fg("accent", "▌") : " ";
      lines.push(row(truncateToWidth(`${pointer}${indent}${keyStr} ${labelStr}`, innerW)));
    }
    if (this.flatLines.length > maxVisible) {
      const pos = Math.round(
        (this.scrollOffset / Math.max(1, this.flatLines.length - maxVisible)) * 100,
      );
      lines.push(row(th.fg("dim",
        `  ${this.scrollOffset + 1}-${Math.min(this.scrollOffset + maxVisible, this.flatLines.length)} of ${this.flatLines.length} (${pos}%)`,
      )));
    }
    lines.push(emptyRow());
    lines.push(row(th.fg("dim", "↑↓/jk navigate • Esc/q close")));
    lines.push(botBorder);
    this.cachedWidth = width; this.cachedLines = lines;
    return lines;
  }

  invalidate(): void {
    this.cachedWidth = undefined;
    this.cachedLines = undefined;
  }
}

// ─── Entry point ─────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  let actionHost: LeaderActionHost | null = null;
  let leaderMenus: Map<string, LeaderNode> = new Map();
  let sessionNotify:
    | ((msg: string, level: "info" | "warning" | "error") => void)
    | null = null;
  /** Captured at session_start so event handlers (which receive no ctx)
   *  can reach the active UI for showing overlays. */
  let currentCtx: any = null;

  /** Registrations received before session_start. */
  const pendingRegistrations: LeaderMenuRegistration[] = [];

  /** Cleanup handles for pi event subscriptions. */
  const eventCleanups: (() => void)[] = [];

  function createActionHost(ctx: any): LeaderActionHost {
    return {
      submitCommand(command: string) {
        ctx.ui.setEditorText(command);
        ctx.ui.notify(`leader-menu: inserted ${command}; press Enter to run`, "info");
      },
      passthrough(keyName: string, _seq: string) {
        switch (keyName) {
          case "ctrl+o": {
            const expanded = ctx.ui.getToolsExpanded?.() ?? false;
            ctx.ui.setToolsExpanded?.(!expanded);
            return;
          }
          case "shift+tab": {
            const levels = ["off", "minimal", "low", "medium", "high", "xhigh"] as const;
            const current = pi.getThinkingLevel?.() ?? "off";
            const next = levels[
              (Math.max(0, levels.indexOf(current as any)) + 1) % levels.length
            ];
            pi.setThinkingLevel?.(next);
            return;
          }
          case "ctrl+l":
            ctx.ui.setEditorText("/model");
            ctx.ui.notify("leader-menu: inserted /model; press Enter to select model", "info");
            return;
          case "ctrl+g":
            ctx.ui.notify("Use the native external-editor shortcut (Ctrl+G) from the editor", "warning");
            return;
          case "ctrl+t":
            ctx.ui.notify("Thinking block visibility has no public extension API; use Ctrl+T", "warning");
            return;
          default:
            ctx.ui.notify(`Unsupported passthrough action: ${keyName}`, "warning");
        }
      },
      emitEvent(eventName: string) {
        pi.events.emit(eventName, {});
      },
    };
  }

  async function showLeaderOverlay(ctx: any, rootKey: string): Promise<void> {
    if (!ctx.hasUI) return;
    if (!leaderMenus.has(rootKey)) {
      ctx.ui.notify(`leader-menu: no ${displayKey(rootKey)} menu loaded`, "warning");
      return;
    }
    await ctx.ui.custom<undefined>(
      (tui: TUI, theme: any, _kb: KeybindingsManager, done: (value: undefined) => void) =>
        new LeaderMenuOverlay(tui, leaderMenus, theme, () => done(undefined), rootKey),
      { overlay: true },
    );
  }

  // ── Global shortcuts ────────────────────────────────────────────

  pi.registerShortcut("alt+space", {
    description: "Open Space leader menu",
    handler: async (ctx) => { await showLeaderOverlay(ctx, " "); },
  });

  pi.registerShortcut("alt+,", {
    description: "Open comma leader menu",
    handler: async (ctx) => { await showLeaderOverlay(ctx, ","); },
  });

  // ── Lifecycle ───────────────────────────────────────────────────

  pi.on("session_shutdown", () => {
    for (const cleanup of eventCleanups) cleanup();
    eventCleanups.length = 0;
    actionHost = null;
    leaderMenus = new Map();
    sessionNotify = null;
    currentCtx = null;
  });

  pi.on("session_start", (_event, ctx) => {
    sessionNotify = ctx.ui.notify.bind(ctx.ui);
    currentCtx = ctx;
    actionHost = createActionHost(ctx);

    const config = loadDefaults();
    leaderMenus = buildMenuTree(config, actionHost);
    warnClashingLeaderKeys(leaderMenus, "defaults.json", sessionNotify ?? undefined);

    for (const reg of pendingRegistrations) {
      applyRegistration(leaderMenus, actionHost, reg, sessionNotify ?? undefined);
    }
    pendingRegistrations.length = 0;

    pi.events.emit("leader-menu:ready", {});
  });

  // ── Cross-extension contribution API ─────────────────────────────

  eventCleanups.push(
    pi.events.on("leader-menu:register", (data: LeaderMenuRegistration) => {
      if (actionHost && sessionNotify) {
        applyRegistration(leaderMenus, actionHost, data, sessionNotify);
      } else {
        pendingRegistrations.push(data);
      }
    }),
  );

  // ── leader-menu:open — request from vim-mode ────────────────────
  //
  // vim-mode catches bare Space / , in Normal mode and emits this
  // event so leader-menu can show its standard centered overlay.
  // Replaces the legacy in-editor widget-hint flow that lived inside
  // VimEditor before the split.
  eventCleanups.push(
    pi.events.on(
      "leader-menu:open",
      async (data: { rootKey?: string }) => {
        if (!currentCtx) return;
        const rootKey = data?.rootKey ?? " ";
        await showLeaderOverlay(currentCtx, rootKey);
      },
    ),
  );

  // ── /leader-menu slash command ───────────────────────────────────

  pi.registerCommand("leader-menu", {
    description: "Leader-menu utilities: /leader-menu bindings [--export]",
    getArgumentCompletions: (prefix: string) => {
      const items = [
        { value: "bindings", label: "bindings", description: "List all registered chords" },
        { value: "bindings --export", label: "bindings --export", description: "Print chords as an org-mode table" },
      ];
      const filtered = items.filter((i) => i.value.startsWith(prefix));
      return filtered.length > 0 ? filtered : null;
    },
    handler: async (args, ctx) => {
      const parts = (args ?? "").trim().split(/\s+/).filter(Boolean);
      const sub = parts[0] ?? "";
      if (sub === "bindings") {
        const isExport = parts.includes("--export");
        if (isExport) {
          const text = exportBindingsAsOrg(leaderMenus);
          ctx.ui.notify(text, "info");
          return;
        }
        if (!ctx.hasUI) {
          ctx.ui.notify("/leader-menu bindings requires interactive mode", "error");
          return;
        }
        await ctx.ui.custom<undefined>(
          (_tui, theme, _kb, done) =>
            new BindingsOverlay(leaderMenus, theme, () => done(undefined)),
          { overlay: true },
        );
        return;
      }
      ctx.ui.notify("Usage: /leader-menu bindings [--export]", "info");
    },
  });
}
