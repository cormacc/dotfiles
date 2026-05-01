/**
 * Keybindings Extension for pi — leader menus + optional vim modal editing
 *
 * Usage: pi --extension ~/dotfiles/agents/pi/extensions/keybindings/index.ts
 *
 * Primary role: which-key-style leader menu discovery and dispatch.
 * Modal (vim-style) editing is opt-in via user settings. In insert mode
 * the Space and comma leader menus are reached with `alt+space` and
 * `alt+,`; in normal mode (modal on) they are reached with bare leader keys.
 *
 * Modes: Insert (default), Normal, Visual, Visual-Line (normal/visual
 * only reachable when modal editing is enabled).
 *
 * Settings file: ~/.pi/agent/keybindings-ext.json
 * Defaults file: <ext dir>/defaults.json
 */

import { CustomEditor, type ExtensionAPI } from "@mariozechner/pi-coding-agent";
import {
  matchesKey,
  truncateToWidth,
  visibleWidth,
  type Component,
  type EditorTheme,
  type TUI,
} from "@mariozechner/pi-tui";
import type { KeybindingsManager } from "@mariozechner/pi-coding-agent";
import { readFileSync, existsSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";
import { ansiPad } from "../lib/pi-utils.js";

const EXT_DIR = dirname(fileURLToPath(import.meta.url));
const USER_SETTINGS_PATH = join(homedir(), ".pi", "agent", "keybindings-ext.json");

interface UserSettings {
  modal: boolean;
  /** When true, the keybindings extension logs every key press to the
   *  pi notification console. Temporary debugging aid — see AGENTS.md. */
  debug: boolean;
}

function loadUserSettings(): UserSettings {
  try {
    if (existsSync(USER_SETTINGS_PATH)) {
      const parsed = JSON.parse(readFileSync(USER_SETTINGS_PATH, "utf-8"));
      return { modal: !!parsed?.modal, debug: !!parsed?.debug };
    }
  } catch {}
  return { modal: false, debug: false };
}

function saveUserSettings(settings: Partial<UserSettings>): void {
  try {
    mkdirSync(dirname(USER_SETTINGS_PATH), { recursive: true });
    // Merge with existing on disk so partial updates (e.g. just `modal`)
    // don't clobber unrelated keys (e.g. `debug`).
    const existing = loadUserSettings();
    const merged: UserSettings = { ...existing, ...settings };
    writeFileSync(
      USER_SETTINGS_PATH,
      JSON.stringify(merged, null, 2) + "\n",
    );
  } catch {}
}

// ─── Types ───────────────────────────────────────────────────────────────────

type Mode = "normal" | "insert" | "visual" | "visual-line";

interface EditorState {
  lines: string[];
  cursorLine: number;
  cursorCol: number;
}

/** A position in the editor */
interface Pos {
  line: number;
  col: number;
}

/** A range defined by two positions (inclusive of start, exclusive of end for char ops) */
interface Range {
  start: Pos;
  end: Pos;
  linewise: boolean;
}

/** Describes a repeatable change */
interface Recordable {
  /** The raw key sequence that produced this change */
  keys: string;
}

/** A node in the leader key menu tree */
type LeaderNode = {
  key?: string;
  label: string;
} & (
  | { children: LeaderEntry[]; action?: never }
  | { action: () => void; children?: never }
);

type LeaderEntry = LeaderNode & { key: string };

/** JSON config types */
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

interface KeybindingsConfig {
  menus?: Record<string, MenuConfig>;
}

/** Payload for the keybindings:suggest event. */
interface KeybindingSuggestion extends KeybindingsConfig {
  /** Name of the extension suggesting these bindings (used in notifications). */
  source?: string;
}

interface LeaderActionHost {
  submitCommand(command: string): void;
  passthrough(keyName: string, seq: string): void;
  emitEvent(eventName: string): void;
}

/** Map of passthrough key names to escape sequences */
const PASSTHROUGH_KEYS: Record<string, string> = {
  "ctrl+l": "\x0c",
  "ctrl+o": "\x0f",
  "ctrl+t": "\x14",
  "ctrl+g": "\x07",
  "shift+tab": "\x1b[Z",
};

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

/**
 * Keys that are consumed by `dispatchNormal` before the leader-key fallback.
 * Any leader trigger key in this set will be silently swallowed by a vim
 * command and never reach the leader check.
 */
const NORMAL_MODE_KEYS = new Set([
  // motions (resolveMotion)
  "h", "l", "j", "k", "w", "W", "e", "E", "b", "B", "0", "$", "^",
  // mode switches
  "i", "a", "I", "A", "o", "O", "v", "V",
  // operators
  "d", "c", "y", ">", "<",
  // find character
  "f", "F", "t", "T",
  // repeat find
  ";",
  // single-key commands
  "x", "X", "r", "s", "S", "p", "P", "u", ".", "J", "~", "D", "C", "Y",
]);

/**
 * Warn about leader trigger keys that clash with normal-mode vim bindings.
 * These keys will be swallowed by vim commands and never reach the leader
 * fallback at the bottom of `dispatchNormal`.
 */
function warnClashingLeaderKeys(
  menus: Map<string, LeaderNode>,
  source: string,
  notify?: (msg: string, level: "info" | "warning" | "error") => void,
): void {
  if (!notify) return;
  for (const [triggerKey, node] of menus) {
    if (NORMAL_MODE_KEYS.has(triggerKey)) {
      const label = node.label ?? triggerKey;
      const displayKey = triggerKey === " " ? "SPC" : triggerKey;
      notify(
        `keybindings: leader key "${displayKey}" ("${label}" from ${source}) ` +
          `clashes with a normal-mode vim binding and will not work`,
        "warning",
      );
    }
  }
}

function loadKeybindingsConfig(): KeybindingsConfig {
  const configPath = join(EXT_DIR, "defaults.json");
  if (!existsSync(configPath)) return {};
  try {
    return JSON.parse(readFileSync(configPath, "utf-8"));
  } catch {
    return {};
  }
}

/** Convert a JSON menu item tree into a LeaderNode tree */
function buildMenuNode(
  config: MenuItemConfig,
  key: string | undefined,
  host: LeaderActionHost,
): LeaderEntry {
  if (config.items) {
    const children: LeaderEntry[] = Object.entries(config.items).map(
      ([k, item]) => buildMenuNode(item, k, host),
    );
    return { key: key!, label: config.label, children } as LeaderEntry;
  }
  const action = buildAction(config.action ?? "", host);
  return { key: key!, label: config.label, action } as LeaderEntry;
}

function buildAction(actionStr: string, host: LeaderActionHost): () => void {
  if (actionStr.startsWith("command:")) {
    const cmd = actionStr.slice("command:".length);
    return () => host.submitCommand(cmd);
  }
  if (actionStr.startsWith("passthrough:")) {
    const keyName = actionStr.slice("passthrough:".length);
    const seq = PASSTHROUGH_KEYS[keyName];
    if (seq) return () => host.passthrough(keyName, seq);
    return () => host.passthrough(keyName, "");
  }
  // Default: emit as event. "event:" prefix is accepted for backward
  // compatibility but not required — bare names are treated as events.
  if (!actionStr) return () => {};
  const eventName = actionStr.startsWith("event:") ? actionStr.slice("event:".length) : actionStr;
  return () => host.emitEvent(eventName);
}

function buildMenuTree(
  config: KeybindingsConfig,
  host: LeaderActionHost,
): Map<string, LeaderNode> {
  const menus = new Map<string, LeaderNode>();
  if (!config.menus) return menus;
  for (const [_name, menuConfig] of Object.entries(config.menus)) {
    const children: LeaderEntry[] = Object.entries(menuConfig.items).map(
      ([k, item]) => buildMenuNode(item, k, host),
    );
    const node: LeaderNode = { label: menuConfig.label, children };
    menus.set(menuConfig.key, node);
  }
  return menus;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function clamp(val: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, val));
}

/** Is the character a "word" character (alphanumeric or underscore)? */
function isWordChar(ch: string): boolean {
  return /[\w]/.test(ch);
}

/** Is the character whitespace? */
function isWhitespace(ch: string): boolean {
  return /\s/.test(ch);
}

/** Is the character a symbol/punctuation (not word and not whitespace)? */
function isSymbol(ch: string): boolean {
  return !isWordChar(ch) && !isWhitespace(ch);
}

/** Compare two positions: negative if a < b, 0 if equal, positive if a > b */
function comparePos(a: Pos, b: Pos): number {
  if (a.line !== b.line) return a.line - b.line;
  return a.col - b.col;
}

function minPos(a: Pos, b: Pos): Pos {
  return comparePos(a, b) <= 0 ? a : b;
}

function maxPos(a: Pos, b: Pos): Pos {
  return comparePos(a, b) >= 0 ? a : b;
}

// ─── The Modal Editor ────────────────────────────────────────────────────────

class VimEditor extends CustomEditor {
  private mode: Mode = "insert";
  /** When false (default), the editor behaves like pi's standard editor —
   *  no Normal/Visual modes and no escape-to-normal. */
  private modalEnabled: boolean = false;
  private _tui: TUI;
  private _theme: EditorTheme;

  // Operator-pending state
  private pendingOperator: string | null = null;

  // Numeric count accumulator
  private countStr: string = "";

  // f/t/F/T awaiting char
  private pendingFind: { type: "f" | "F" | "t" | "T" } | null = null;
  // Last f/t for ; and , repeat
  private lastFind: { type: "f" | "F" | "t" | "T"; char: string } | null = null;

  // r awaiting char
  private pendingReplace: boolean = false;

  // Leader key (Space) pending
  private leaderPending: boolean = false;
  private leaderPath: string[] = []; // tracks nested leader path, e.g. [] = root, ["g"] = git sub-menu
  private leaderOverlayDelay: number = 500;
  private leaderOverlayTimer: ReturnType<typeof setTimeout> | null = null;
  private leaderOverlayVisible: boolean = false;

  // Visual mode anchor
  private visualAnchor: Pos = { line: 0, col: 0 };

  // External width constraint (e.g. from git-diff side panel)
  private widthConstraintFraction: number = 0;
  private widthConstraintMinCols: number = 0;

  // Vim register (yank buffer)
  private register: string = "";
  private registerLinewise: boolean = false;

  // Dot-repeat
  private lastChange: string | null = null;
  private recording: boolean = false;
  private recordBuffer: string = "";
  private replaying: boolean = false;

  // Extension context for leader commands
  private ctx: any = null;

  constructor(tui: TUI, theme: EditorTheme, keybindings: KeybindingsManager) {
    super(tui, theme, keybindings);
    this._tui = tui;
    this._theme = theme;
  }

  setContext(ctx: any) {
    this.ctx = ctx;
    this.updateStatus();
  }

  setLeaderMenus(menus: Map<string, LeaderNode>): void {
    this.leaderMenus = menus;
  }

  private updateStatus(): void {
    if (!this.ctx?.ui) return;
    if (!this.modalEnabled) {
      this.ctx.ui.setStatus("keybindings", undefined);
      return;
    }
    const label = this.mode === "visual-line" ? "VISUAL-LINE" : this.mode.toUpperCase();
    this.ctx.ui.setStatus("keybindings", label);
  }

  setLeaderOverlayDelay(ms: number) {
    this.leaderOverlayDelay = ms;
  }

  /** [DEBUG] When true, every key press is reported via ctx.ui.notify. */
  private debugEnabled: boolean = false;

  /** [DEBUG] Toggle the per-keypress notification logger. */
  setDebugEnabled(enabled: boolean): void {
    this.debugEnabled = enabled;
  }

  /** Toggle modal (vim-style) editing. Default false. */
  setModalEnabled(enabled: boolean): void {
    this.modalEnabled = enabled;
    if (!enabled && this.mode !== "insert") {
      this.mode = "insert";
      this.pendingOperator = null;
      this.countStr = "";
      this.pendingFind = null;
      this.pendingReplace = false;
      this.leaderPending = false;
      this.leaderPath = [];
      this.activeLeaderMenu = null;
      this.clearLeaderOverlay();
    }
    this.updateStatus();
    this.invalidate();
  }

  isModalEnabled(): boolean {
    return this.modalEnabled;
  }

  /** Reserve a fraction of terminal width for side panels. */
  setWidthConstraint(fraction: number, minCols: number = 0) {
    this.widthConstraintFraction = Math.max(0, fraction);
    this.widthConstraintMinCols = Math.max(0, minCols);
    this.invalidate();
  }

  // ─── State access (private fields of parent Editor) ───────────────────

  private get st(): EditorState {
    return (this as any).state;
  }

  private pushUndo(): void {
    (this as any).pushUndoSnapshot();
  }

  private doSetCursorCol(col: number): void {
    (this as any).setCursorCol(col);
  }

  private triggerOnChange(): void {
    if ((this as any).onChange) {
      (this as any).onChange(this.getText());
    }
  }

  /** Set cursor position directly */
  private setCursor(line: number, col: number): void {
    const st = this.st;
    st.cursorLine = clamp(line, 0, st.lines.length - 1);
    const lineLen = st.lines[st.cursorLine]?.length ?? 0;
    // In normal mode, cursor can't be past last char (but can be at col 0 on empty line)
    const maxCol = this.mode === "insert" ? lineLen : Math.max(0, lineLen - 1);
    this.doSetCursorCol(clamp(col, 0, maxCol));
  }

  /** Ensure cursor is within bounds for current mode */
  private clampCursor(): void {
    this.setCursor(this.st.cursorLine, this.st.cursorCol);
  }

  private lineText(line: number): string {
    return this.st.lines[line] ?? "";
  }

  private curLine(): string {
    return this.lineText(this.st.cursorLine);
  }

  private curPos(): Pos {
    return { line: this.st.cursorLine, col: this.st.cursorCol };
  }

  // ─── Text mutation helpers ────────────────────────────────────────────

  /** Delete text in a range, return the deleted text. Caller must pushUndo first. */
  private deleteRange(range: Range): string {
    const st = this.st;
    let deleted: string;

    if (range.linewise) {
      const startLine = range.start.line;
      const endLine = range.end.line;
      const deletedLines = st.lines.splice(startLine, endLine - startLine + 1);
      deleted = deletedLines.join("\n") + "\n";
      if (st.lines.length === 0) st.lines = [""];
      st.cursorLine = clamp(startLine, 0, st.lines.length - 1);
      // Move to first non-blank
      const line = this.lineText(st.cursorLine);
      const firstNonBlank = line.search(/\S/);
      this.doSetCursorCol(firstNonBlank >= 0 ? firstNonBlank : 0);
    } else {
      const { start, end } = range;
      if (start.line === end.line) {
        const line = st.lines[start.line] ?? "";
        deleted = line.slice(start.col, end.col);
        st.lines[start.line] = line.slice(0, start.col) + line.slice(end.col);
      } else {
        const firstLine = st.lines[start.line] ?? "";
        const lastLine = st.lines[end.line] ?? "";
        const firstPart = firstLine.slice(0, start.col);
        deleted = firstLine.slice(start.col);
        for (let i = start.line + 1; i < end.line; i++) {
          deleted += "\n" + (st.lines[i] ?? "");
        }
        deleted += "\n" + lastLine.slice(0, end.col);
        const lastPart = lastLine.slice(end.col);
        st.lines[start.line] = firstPart + lastPart;
        st.lines.splice(start.line + 1, end.line - start.line);
      }
      st.cursorLine = start.line;
      this.doSetCursorCol(start.col);
    }

    if (st.lines.length === 0) st.lines = [""];
    this.triggerOnChange();
    this.invalidate();
    return deleted;
  }

  /** Insert text at a position. Returns the end position after insertion. */
  private insertTextAt(pos: Pos, text: string): Pos {
    const st = this.st;
    const line = st.lines[pos.line] ?? "";
    const before = line.slice(0, pos.col);
    const after = line.slice(pos.col);
    const insertLines = text.split("\n");

    if (insertLines.length === 1) {
      st.lines[pos.line] = before + insertLines[0] + after;
      return { line: pos.line, col: pos.col + insertLines[0].length };
    } else {
      st.lines[pos.line] = before + insertLines[0];
      const middleLines = insertLines.slice(1, -1);
      const lastInsert = insertLines[insertLines.length - 1];
      const newLines = [...middleLines, lastInsert + after];
      st.lines.splice(pos.line + 1, 0, ...newLines);
      return {
        line: pos.line + insertLines.length - 1,
        col: lastInsert.length,
      };
    }
  }

  /** Get the text within a range */
  private getTextInRange(range: Range): string {
    const st = this.st;
    if (range.linewise) {
      const lines = st.lines.slice(range.start.line, range.end.line + 1);
      return lines.join("\n") + "\n";
    }
    const { start, end } = range;
    if (start.line === end.line) {
      return (st.lines[start.line] ?? "").slice(start.col, end.col);
    }
    let text = (st.lines[start.line] ?? "").slice(start.col);
    for (let i = start.line + 1; i < end.line; i++) {
      text += "\n" + (st.lines[i] ?? "");
    }
    text += "\n" + (st.lines[end.line] ?? "").slice(0, end.col);
    return text;
  }

  /** Indent lines in range */
  private indentLines(
    startLine: number,
    endLine: number,
    dedent: boolean,
  ): void {
    const st = this.st;
    for (let i = startLine; i <= endLine && i < st.lines.length; i++) {
      if (dedent) {
        // Remove up to 2 leading spaces or 1 tab
        st.lines[i] = (st.lines[i] ?? "").replace(/^(\t| {1,2})/, "");
      } else {
        st.lines[i] = "  " + (st.lines[i] ?? "");
      }
    }
    this.triggerOnChange();
    this.invalidate();
  }

  // ─── Motion computation ──────────────────────────────────────────────
  // Each motion returns a Range from current cursor position to the target.

  /** Move left by count chars */
  private motionLeft(count: number): Range {
    const pos = this.curPos();
    const newCol = Math.max(0, pos.col - count);
    return {
      start: { line: pos.line, col: newCol },
      end: { line: pos.line, col: pos.col },
      linewise: false,
    };
  }

  /** Move right by count chars */
  private motionRight(count: number): Range {
    const pos = this.curPos();
    const lineLen = this.curLine().length;
    const maxCol = this.mode === "insert" ? lineLen : Math.max(0, lineLen - 1);
    const newCol = Math.min(maxCol, pos.col + count);
    return {
      start: { line: pos.line, col: pos.col },
      end: { line: pos.line, col: newCol },
      linewise: false,
    };
  }

  /** Move down by count lines */
  private motionDown(count: number): Range {
    const pos = this.curPos();
    const newLine = Math.min(this.st.lines.length - 1, pos.line + count);
    return {
      start: { line: pos.line, col: 0 },
      end: { line: newLine, col: 0 },
      linewise: true,
    };
  }

  /** Move up by count lines */
  private motionUp(count: number): Range {
    const pos = this.curPos();
    const newLine = Math.max(0, pos.line - count);
    return {
      start: { line: newLine, col: 0 },
      end: { line: pos.line, col: 0 },
      linewise: true,
    };
  }

  /** w motion: next word start */
  private motionWordForward(count: number, bigWord: boolean = false): Range {
    const start = this.curPos();
    let { line, col } = start;
    const st = this.st;

    for (let i = 0; i < count; i++) {
      const text = this.lineText(line);
      if (col >= text.length) {
        // Move to next line
        if (line < st.lines.length - 1) {
          line++;
          col = 0;
          // Skip leading whitespace on new line
          const newText = this.lineText(line);
          while (col < newText.length && isWhitespace(newText[col])) col++;
        }
        continue;
      }

      const ch = text[col];
      if (bigWord) {
        // WORD: skip non-whitespace, then whitespace
        while (col < text.length && !isWhitespace(text[col])) col++;
        while (col < text.length && isWhitespace(text[col])) col++;
      } else {
        // word: skip same-class chars, then whitespace
        if (isWordChar(ch)) {
          while (col < text.length && isWordChar(text[col])) col++;
        } else if (isSymbol(ch)) {
          while (col < text.length && isSymbol(text[col])) col++;
        } else {
          while (col < text.length && isWhitespace(text[col])) col++;
        }
        // Skip whitespace after word
        while (col < text.length && isWhitespace(text[col])) col++;
      }

      // If we're at end of line, move to start of next line
      if (col >= text.length && line < st.lines.length - 1) {
        line++;
        col = 0;
        const newText = this.lineText(line);
        while (col < newText.length && isWhitespace(newText[col])) col++;
      }
    }

    return {
      start: minPos(start, { line, col }),
      end: maxPos(start, { line, col }),
      linewise: false,
    };
  }

  /** e motion: end of word */
  private motionWordEnd(count: number, bigWord: boolean = false): Range {
    const start = this.curPos();
    let { line, col } = start;
    const st = this.st;

    for (let i = 0; i < count; i++) {
      // Move at least one char forward
      col++;
      let text = this.lineText(line);

      // Skip past end of line
      if (col >= text.length && line < st.lines.length - 1) {
        line++;
        col = 0;
        text = this.lineText(line);
      }

      // Skip whitespace
      while (col < text.length && isWhitespace(text[col])) {
        col++;
        if (col >= text.length && line < st.lines.length - 1) {
          line++;
          col = 0;
          text = this.lineText(line);
        }
      }

      if (col < text.length) {
        const ch = text[col];
        if (bigWord) {
          while (col + 1 < text.length && !isWhitespace(text[col + 1])) col++;
        } else if (isWordChar(ch)) {
          while (col + 1 < text.length && isWordChar(text[col + 1])) col++;
        } else if (isSymbol(ch)) {
          while (col + 1 < text.length && isSymbol(text[col + 1])) col++;
        }
      }
    }

    // For operator use, end is inclusive, so we add 1 for the range
    return {
      start: minPos(start, { line, col: col + 1 }),
      end: maxPos(start, { line, col: col + 1 }),
      linewise: false,
    };
  }

  /** b motion: previous word start */
  private motionWordBackward(count: number, bigWord: boolean = false): Range {
    const start = this.curPos();
    let { line, col } = start;

    for (let i = 0; i < count; i++) {
      // Move at least one char backward
      col--;
      let text = this.lineText(line);

      if (col < 0 && line > 0) {
        line--;
        text = this.lineText(line);
        col = text.length - 1;
      }
      if (col < 0) {
        col = 0;
        continue;
      }

      // Skip whitespace backward
      while (col >= 0 && isWhitespace(text[col])) {
        col--;
        if (col < 0 && line > 0) {
          line--;
          text = this.lineText(line);
          col = text.length - 1;
        }
      }

      if (col < 0) {
        col = 0;
        continue;
      }

      const ch = text[col];
      if (bigWord) {
        while (col > 0 && !isWhitespace(text[col - 1])) col--;
      } else if (isWordChar(ch)) {
        while (col > 0 && isWordChar(text[col - 1])) col--;
      } else if (isSymbol(ch)) {
        while (col > 0 && isSymbol(text[col - 1])) col--;
      }
    }

    return {
      start: minPos(start, { line, col }),
      end: maxPos(start, { line, col }),
      linewise: false,
    };
  }

  /** 0 motion: start of line */
  private motionLineStart(): Range {
    const pos = this.curPos();
    return { start: { line: pos.line, col: 0 }, end: pos, linewise: false };
  }

  /** $ motion: end of line */
  private motionLineEnd(count: number): Range {
    const pos = this.curPos();
    const targetLine = Math.min(this.st.lines.length - 1, pos.line + count - 1);
    const lineLen = this.lineText(targetLine).length;
    return {
      start: minPos(pos, { line: targetLine, col: lineLen }),
      end: maxPos(pos, { line: targetLine, col: lineLen }),
      linewise: false,
    };
  }

  /** ^ motion: first non-blank */
  private motionFirstNonBlank(): Range {
    const pos = this.curPos();
    const line = this.curLine();
    const idx = line.search(/\S/);
    const col = idx >= 0 ? idx : 0;
    return {
      start: minPos(pos, { line: pos.line, col }),
      end: maxPos(pos, { line: pos.line, col }),
      linewise: false,
    };
  }

  /** f/F/t/T motion: find char */
  private motionFindChar(
    type: "f" | "F" | "t" | "T",
    char: string,
    count: number,
  ): Range | null {
    const pos = this.curPos();
    const line = this.curLine();
    let col = pos.col;
    const forward = type === "f" || type === "t";
    const till = type === "t" || type === "T";

    for (let i = 0; i < count; i++) {
      if (forward) {
        let found = -1;
        for (let j = col + 1; j < line.length; j++) {
          if (line[j] === char) {
            found = j;
            break;
          }
        }
        if (found === -1) return null;
        col = found;
      } else {
        let found = -1;
        for (let j = col - 1; j >= 0; j--) {
          if (line[j] === char) {
            found = j;
            break;
          }
        }
        if (found === -1) return null;
        col = found;
      }
    }

    if (till) {
      col = forward ? col - 1 : col + 1;
    }

    // For operators, range needs to include the char for f, and be exclusive-end
    const target = { line: pos.line, col };
    if (forward) {
      return {
        start: pos,
        end: { line: pos.line, col: col + 1 },
        linewise: false,
      };
    } else {
      return { start: { line: pos.line, col }, end: pos, linewise: false };
    }
  }

  // ─── Text objects ────────────────────────────────────────────────────

  /** Inner/around word text object */
  private textObjectWord(
    inner: boolean,
    bigWord: boolean = false,
  ): Range | null {
    const pos = this.curPos();
    const line = this.curLine();
    if (line.length === 0) return null;

    const ch = line[pos.col];
    if (!ch) return null;

    let start = pos.col;
    let end = pos.col;

    const classify = bigWord
      ? (c: string) => (isWhitespace(c) ? "ws" : "word")
      : (c: string) =>
          isWordChar(c) ? "word" : isWhitespace(c) ? "ws" : "sym";

    const cls = classify(ch);

    // Expand to cover contiguous same-class chars
    while (start > 0 && classify(line[start - 1]) === cls) start--;
    while (end < line.length - 1 && classify(line[end + 1]) === cls) end++;

    if (!inner) {
      // "around" includes trailing whitespace (or leading if at end)
      if (end + 1 < line.length && isWhitespace(line[end + 1])) {
        while (end + 1 < line.length && isWhitespace(line[end + 1])) end++;
      } else if (start > 0 && isWhitespace(line[start - 1])) {
        while (start > 0 && isWhitespace(line[start - 1])) start--;
      }
    }

    return {
      start: { line: pos.line, col: start },
      end: { line: pos.line, col: end + 1 },
      linewise: false,
    };
  }

  /** Inner/around quoted string text object */
  private textObjectQuote(quote: string, inner: boolean): Range | null {
    const pos = this.curPos();
    const line = this.curLine();

    // Find opening quote at or before cursor
    let open = -1;
    for (let i = pos.col; i >= 0; i--) {
      if (line[i] === quote) {
        open = i;
        break;
      }
    }
    if (open === -1) {
      // Try forward from cursor
      for (let i = pos.col; i < line.length; i++) {
        if (line[i] === quote) {
          open = i;
          break;
        }
      }
    }
    if (open === -1) return null;

    // Find closing quote after opening
    let close = -1;
    for (let i = open + 1; i < line.length; i++) {
      if (line[i] === quote && (i === 0 || line[i - 1] !== "\\")) {
        close = i;
        break;
      }
    }
    if (close === -1) return null;

    // If cursor is outside the quotes, check if there's a pair starting at cursor
    if (pos.col > close) return null;

    if (inner) {
      return {
        start: { line: pos.line, col: open + 1 },
        end: { line: pos.line, col: close },
        linewise: false,
      };
    } else {
      return {
        start: { line: pos.line, col: open },
        end: { line: pos.line, col: close + 1 },
        linewise: false,
      };
    }
  }

  /** Inner/around bracket text object — searches across lines */
  private textObjectBracket(
    openBracket: string,
    closeBracket: string,
    inner: boolean,
  ): Range | null {
    const st = this.st;
    const pos = this.curPos();

    // Find matching open bracket (searching backward)
    let depth = 0;
    let openPos: Pos | null = null;

    outer_open: for (let l = pos.line; l >= 0; l--) {
      const line = this.lineText(l);
      const startCol = l === pos.line ? pos.col : line.length - 1;
      for (let c = startCol; c >= 0; c--) {
        if (line[c] === closeBracket && !(l === pos.line && c === pos.col))
          depth++;
        if (line[c] === openBracket) {
          if (depth === 0) {
            openPos = { line: l, col: c };
            break outer_open;
          }
          depth--;
        }
      }
    }
    if (!openPos) return null;

    // Find matching close bracket (searching forward)
    depth = 0;
    let closePos: Pos | null = null;

    outer_close: for (let l = openPos.line; l < st.lines.length; l++) {
      const line = this.lineText(l);
      const startCol = l === openPos.line ? openPos.col + 1 : 0;
      for (let c = startCol; c < line.length; c++) {
        if (line[c] === openBracket) depth++;
        if (line[c] === closeBracket) {
          if (depth === 0) {
            closePos = { line: l, col: c };
            break outer_close;
          }
          depth--;
        }
      }
    }
    if (!closePos) return null;

    if (inner) {
      // Inside the brackets
      let startPos = { line: openPos.line, col: openPos.col + 1 };
      let endPos = { line: closePos.line, col: closePos.col };
      return { start: startPos, end: endPos, linewise: false };
    } else {
      return {
        start: openPos,
        end: { line: closePos.line, col: closePos.col + 1 },
        linewise: false,
      };
    }
  }

  /** Inner/around paragraph text object */
  private textObjectParagraph(inner: boolean): Range | null {
    const st = this.st;
    const pos = this.curPos();

    const isBlank = (l: number) => (st.lines[l] ?? "").trim() === "";

    // Find paragraph boundaries
    let startLine = pos.line;
    let endLine = pos.line;

    if (isBlank(pos.line)) {
      // On a blank line: select the blank block
      while (startLine > 0 && isBlank(startLine - 1)) startLine--;
      while (endLine < st.lines.length - 1 && isBlank(endLine + 1)) endLine++;
    } else {
      // On a non-blank line: select the non-blank block
      while (startLine > 0 && !isBlank(startLine - 1)) startLine--;
      while (endLine < st.lines.length - 1 && !isBlank(endLine + 1)) endLine++;
    }

    if (!inner) {
      // "around": include trailing blank lines (or leading if at end)
      if (endLine < st.lines.length - 1) {
        while (endLine < st.lines.length - 1 && isBlank(endLine + 1)) endLine++;
      } else {
        while (startLine > 0 && isBlank(startLine - 1)) startLine--;
      }
    }

    return {
      start: { line: startLine, col: 0 },
      end: { line: endLine, col: this.lineText(endLine).length },
      linewise: true,
    };
  }

  /** Parse a text object key sequence: returns Range or null */
  private parseTextObject(modifier: string, obj: string): Range | null {
    const inner = modifier === "i";
    switch (obj) {
      case "w":
        return this.textObjectWord(inner, false);
      case "W":
        return this.textObjectWord(inner, true);
      case "p":
        return this.textObjectParagraph(inner);
      case '"':
        return this.textObjectQuote('"', inner);
      case "'":
        return this.textObjectQuote("'", inner);
      case "`":
        return this.textObjectQuote("`", inner);
      case "(":
      case ")":
      case "b":
        return this.textObjectBracket("(", ")", inner);
      case "[":
      case "]":
        return this.textObjectBracket("[", "]", inner);
      case "{":
      case "}":
      case "B":
        return this.textObjectBracket("{", "}", inner);
      default:
        return null;
    }
  }

  // ─── Resolve a motion key to a Range ─────────────────────────────────

  private resolveMotion(key: string, count: number): Range | null {
    switch (key) {
      case "h":
        return this.motionLeft(count);
      case "l":
        return this.motionRight(count);
      case "j":
        return this.motionDown(count);
      case "k":
        return this.motionUp(count);
      case "w":
        return this.motionWordForward(count, false);
      case "W":
        return this.motionWordForward(count, true);
      case "e":
        return this.motionWordEnd(count, false);
      case "E":
        return this.motionWordEnd(count, true);
      case "b":
        return this.motionWordBackward(count, false);
      case "B":
        return this.motionWordBackward(count, true);
      case "0":
        return this.motionLineStart();
      case "$":
        return this.motionLineEnd(count);
      case "^":
        return this.motionFirstNonBlank();
      default:
        return null;
    }
  }

  // ─── Apply operator to range ─────────────────────────────────────────

  private applyOperator(op: string, range: Range): void {
    this.pushUndo();

    switch (op) {
      case "d": {
        const deleted = this.deleteRange(range);
        this.register = deleted;
        this.registerLinewise = range.linewise;
        this.clampCursor();
        break;
      }
      case "c": {
        const deleted = this.deleteRange(range);
        this.register = deleted;
        this.registerLinewise = range.linewise;
        if (range.linewise) {
          // Open a line for insertion
          const st = this.st;
          const insertLine = Math.min(st.cursorLine, st.lines.length - 1);
          st.lines.splice(insertLine, 0, "");
          st.cursorLine = insertLine;
          this.doSetCursorCol(0);
        }
        this.switchMode("insert");
        break;
      }
      case "y": {
        this.register = this.getTextInRange(range);
        this.registerLinewise = range.linewise;
        // Cursor goes to start of range
        this.setCursor(range.start.line, range.start.col);
        break;
      }
      case ">": {
        const startLine = range.start.line;
        const endLine = range.linewise ? range.end.line : range.end.line;
        this.indentLines(startLine, endLine, false);
        this.clampCursor();
        break;
      }
      case "<": {
        const startLine = range.start.line;
        const endLine = range.linewise ? range.end.line : range.end.line;
        this.indentLines(startLine, endLine, true);
        this.clampCursor();
        break;
      }
    }
  }

  // ─── Visual mode ─────────────────────────────────────────────────────

  /** Get the visual selection as a Range */
  private getVisualRange(): Range {
    const cursor = this.curPos();
    if (this.mode === "visual-line") {
      const startLine = Math.min(this.visualAnchor.line, cursor.line);
      const endLine = Math.max(this.visualAnchor.line, cursor.line);
      return {
        start: { line: startLine, col: 0 },
        end: { line: endLine, col: this.lineText(endLine).length },
        linewise: true,
      };
    }
    // Character-wise visual
    const start = minPos(this.visualAnchor, cursor);
    let end = maxPos(this.visualAnchor, cursor);
    // Visual selection is inclusive of cursor char, so end.col + 1
    return {
      start,
      end: { line: end.line, col: end.col + 1 },
      linewise: false,
    };
  }

  // ─── Mode switching ──────────────────────────────────────────────────

  private switchMode(newMode: Mode): void {
    // When modal editing is disabled the editor stays in insert mode.
    if (!this.modalEnabled && newMode !== "insert") return;
    const oldMode = this.mode;
    this.mode = newMode;

    if (newMode === "normal") {
      // In normal mode, cursor can't be past last char
      this.clampCursor();
      this.pendingOperator = null;
      this.countStr = "";
      this.pendingFind = null;
      this.pendingReplace = false;
      this.leaderPending = false;
      this.leaderPath = [];
      this.activeLeaderMenu = null;
      this.clearLeaderOverlay();
    }

    if (newMode === "visual" || newMode === "visual-line") {
      this.visualAnchor = this.curPos();
    }

    if (newMode === "insert" && oldMode !== "insert") {
      this.startRecording();
    }

    if (oldMode === "insert" && newMode !== "insert") {
      this.stopRecording();
    }

    this.updateStatus();
    this.invalidate();
  }

  // ─── Dot repeat recording ────────────────────────────────────────────

  private startRecording(): void {
    if (this.replaying) return;
    this.recording = true;
    this.recordBuffer = "";
  }

  private stopRecording(): void {
    if (this.replaying) return;
    if (this.recording && this.recordBuffer.length > 0) {
      this.lastChange = this.recordBuffer;
    }
    this.recording = false;
  }

  private recordKey(key: string): void {
    if (this.recording && !this.replaying) {
      this.recordBuffer += key;
    }
  }

  // ─── Main input handler ──────────────────────────────────────────────

  handleInput(data: string): void {
    // [DEBUG] Temporary: log every key press to the pi console so we can
    // visually inspect what bytes the terminal is delivering. Remove once
    // the capital-letter leader-key issue is understood.
    this.debugLogKey(data);

    // When modal editing is enabled, alt+escape replaces bare escape as
    // the abort/interrupt key (bare escape switches to Normal / clears
    // pending state). When modal is disabled, bare escape falls through
    // to pi's default handling.
    if (this.modalEnabled && matchesKey(data, "alt+escape")) {
      super.handleInput("\x1b");
      return;
    }

    // Always pass through control sequences that pi needs
    if (this.shouldPassthrough(data)) {
      super.handleInput(data);
      return;
    }

    switch (this.mode) {
      case "insert":
        this.handleInsertMode(data);
        break;
      case "normal":
        this.handleNormalMode(data);
        break;
      case "visual":
      case "visual-line":
        this.handleVisualMode(data);
        break;
    }
  }

  /** [DEBUG] Render a key-press as "raw" + hex + length + mode and notify. */
  private debugLogKey(data: string): void {
    if (!this.debugEnabled) return;
    const escaped = data
      .split("")
      .map((ch) => {
        const code = ch.charCodeAt(0);
        if (ch === "\x1b") return "\\e";
        if (ch === "\r") return "\\r";
        if (ch === "\n") return "\\n";
        if (ch === "\t") return "\\t";
        if (ch === "\\") return "\\\\";
        if (code < 0x20 || code === 0x7f) return `\\x${code.toString(16).padStart(2, "0")}`;
        return ch;
      })
      .join("");
    const hex = Array.from(data)
      .map((ch) => ch.charCodeAt(0).toString(16).padStart(2, "0"))
      .join(" ");
    const msg = `kb: "${escaped}" [${hex}] len=${data.length} mode=${this.mode}`;
    this.ctx?.ui?.notify?.(msg, "info");
  }

  /** Keys that always pass through to pi regardless of mode */
  private shouldPassthrough(data: string): boolean {
    // Ctrl+key combinations that pi handles
    if (matchesKey(data, "ctrl+c")) return true;
    if (matchesKey(data, "ctrl+d")) return true;
    if (matchesKey(data, "ctrl+z")) return true;
    if (matchesKey(data, "ctrl+l")) return true;
    if (matchesKey(data, "ctrl+p")) return true;
    if (matchesKey(data, "ctrl+shift+p")) return true;
    if (matchesKey(data, "shift+tab")) return true;
    if (matchesKey(data, "ctrl+o")) return true;
    if (matchesKey(data, "ctrl+t")) return true;
    if (matchesKey(data, "ctrl+g")) return true;
    if (matchesKey(data, "ctrl+v")) return true;
    if (matchesKey(data, "alt+enter")) return true;
    if (matchesKey(data, "alt+up")) return true;
    return false;
  }

  // ─── Insert mode ─────────────────────────────────────────────────────

  private handleInsertMode(data: string): void {
    // Continue an active leader chain first.
    if (this.leaderPending) {
      this.handleLeader(data);
      return;
    }

    // Direct insert-mode leader roots. These intentionally avoid alt+m,
    // which is owned by pi-intercom on this machine.
    const directRoot = matchesKey(data, "alt+space")
      ? " "
      : matchesKey(data, "alt+,")
        ? ","
        : undefined;
    if (directRoot && this.leaderMenus.has(directRoot)) {
      this.leaderPending = true;
      this.activeLeaderMenu = this.leaderMenus.get(directRoot)!;
      this.leaderPath = [];
      this.scheduleLeaderOverlay();
      return;
    }

    // Escape switches to normal only when modal editing is enabled.
    // Otherwise escape falls through to pi (via shouldPassthrough + the
    // base editor) so that app.interrupt still works.
    if (this.modalEnabled && matchesKey(data, "escape")) {
      this.switchMode("normal");
      // Move cursor back one (vim behavior)
      if (this.st.cursorCol > 0) {
        this.doSetCursorCol(this.st.cursorCol - 1);
      }
      return;
    }

    // Record for dot-repeat
    this.recordKey(data);

    // Everything else goes to the underlying editor
    super.handleInput(data);
  }

  // ─── Normal mode ─────────────────────────────────────────────────────

  private handleNormalMode(data: string): void {
    // Escape: clear pending state and stay in Normal mode (does not abort).
    // Use alt+escape to abort (see handleInput).
    if (matchesKey(data, "escape")) {
      this.pendingOperator = null;
      this.countStr = "";
      this.pendingFind = null;
      this.pendingReplace = false;
      this.leaderPending = false;
      this.leaderPath = [];
      this.activeLeaderMenu = null;
      this.clearLeaderOverlay();
      this.invalidate();
      return;
    }

    // Handle Enter: submit message
    if (matchesKey(data, "enter")) {
      super.handleInput(data);
      // After submit, go back to insert mode
      this.mode = "insert";
      return;
    }

    // Leader key handling
    if (this.leaderPending) {
      this.handleLeader(data);
      return;
    }

    // f/t/F/T awaiting char
    if (this.pendingFind) {
      this.handlePendingFind(data);
      return;
    }

    // r awaiting char
    if (this.pendingReplace) {
      this.handlePendingReplace(data);
      return;
    }

    // Operator pending — waiting for motion or text object
    if (this.pendingOperator) {
      this.handleOperatorPending(data);
      return;
    }

    // Accumulate count digits (but "0" only if we already have digits)
    if (data >= "1" && data <= "9") {
      this.countStr += data;
      return;
    }
    if (data === "0" && this.countStr.length > 0) {
      this.countStr += data;
      return;
    }

    const count = this.consumeCount();
    this.dispatchNormal(data, count);
  }

  private consumeCount(): number {
    const count = this.countStr ? parseInt(this.countStr, 10) : 1;
    this.countStr = "";
    return count;
  }

  private dispatchNormal(key: string, count: number): void {
    // ── Motions (cursor movement only) ──
    const motion = this.resolveMotion(key, count);
    if (motion) {
      // Move cursor to the "other end" of the motion range
      const pos = this.curPos();
      const target =
        comparePos(pos, motion.start) === 0 ? motion.end : motion.start;
      if (motion.linewise) {
        if (key === "j") {
          this.setCursor(
            Math.min(this.st.lines.length - 1, pos.line + count),
            pos.col,
          );
        } else if (key === "k") {
          this.setCursor(Math.max(0, pos.line - count), pos.col);
        }
      } else {
        this.setCursor(target.line, target.col);
      }
      this.invalidate();
      return;
    }

    switch (key) {
      // ── Mode switches ──
      case "i":
        this.startRecording();
        this.recordBuffer = "i";
        this.switchMode("insert");
        return;
      case "a":
        this.startRecording();
        this.recordBuffer = "a";
        if (this.curLine().length > 0) {
          this.doSetCursorCol(this.st.cursorCol + 1);
        }
        this.switchMode("insert");
        return;
      case "I":
        this.startRecording();
        this.recordBuffer = "I";
        const fnb = this.curLine().search(/\S/);
        this.doSetCursorCol(fnb >= 0 ? fnb : 0);
        this.switchMode("insert");
        return;
      case "A":
        this.startRecording();
        this.recordBuffer = "A";
        this.doSetCursorCol(this.curLine().length);
        this.switchMode("insert");
        return;
      case "o":
        this.startRecording();
        this.recordBuffer = "o";
        this.pushUndo();
        this.st.lines.splice(this.st.cursorLine + 1, 0, "");
        this.st.cursorLine++;
        this.doSetCursorCol(0);
        this.triggerOnChange();
        this.switchMode("insert");
        return;
      case "O":
        this.startRecording();
        this.recordBuffer = "O";
        this.pushUndo();
        this.st.lines.splice(this.st.cursorLine, 0, "");
        this.doSetCursorCol(0);
        this.triggerOnChange();
        this.switchMode("insert");
        return;
      case "v":
        this.switchMode("visual");
        return;
      case "V":
        this.switchMode("visual-line");
        return;

      // ── Operators (enter pending state) ──
      case "d":
      case "c":
      case "y":
      case ">":
      case "<":
        this.pendingOperator = key;
        return;

      // ── Find character ──
      case "f":
        this.pendingFind = { type: "f" };
        return;
      case "F":
        this.pendingFind = { type: "F" };
        return;
      case "t":
        this.pendingFind = { type: "t" };
        return;
      case "T":
        this.pendingFind = { type: "T" };
        return;

      // ── Repeat find ──
      case ";":
        if (this.lastFind) {
          const range = this.motionFindChar(
            this.lastFind.type,
            this.lastFind.char,
            count,
          );
          if (range) {
            const pos = this.curPos();
            const target =
              comparePos(pos, range.start) === 0
                ? { line: range.end.line, col: range.end.col - 1 }
                : range.start;
            this.setCursor(target.line, target.col);
            this.invalidate();
          }
        }
        return;

      // ── Single-key commands ──
      case "x":
        for (let i = 0; i < count; i++) {
          const line = this.curLine();
          if (line.length > 0 && this.st.cursorCol < line.length) {
            this.pushUndo();
            const deleted = line[this.st.cursorCol];
            this.st.lines[this.st.cursorLine] =
              line.slice(0, this.st.cursorCol) +
              line.slice(this.st.cursorCol + 1);
            this.register = deleted;
            this.registerLinewise = false;
            this.clampCursor();
            this.triggerOnChange();
          }
        }
        this.lastChange = count > 1 ? `${count}x` : "x";
        this.invalidate();
        return;

      case "X":
        for (let i = 0; i < count; i++) {
          if (this.st.cursorCol > 0) {
            this.pushUndo();
            const line = this.curLine();
            const deleted = line[this.st.cursorCol - 1];
            this.st.lines[this.st.cursorLine] =
              line.slice(0, this.st.cursorCol - 1) +
              line.slice(this.st.cursorCol);
            this.register = deleted;
            this.registerLinewise = false;
            this.doSetCursorCol(this.st.cursorCol - 1);
            this.triggerOnChange();
          }
        }
        this.lastChange = count > 1 ? `${count}X` : "X";
        this.invalidate();
        return;

      case "r":
        this.pendingReplace = true;
        return;

      case "s":
        // Substitute: delete char and enter insert
        this.pushUndo();
        {
          const line = this.curLine();
          if (line.length > 0 && this.st.cursorCol < line.length) {
            this.register = line[this.st.cursorCol];
            this.registerLinewise = false;
            this.st.lines[this.st.cursorLine] =
              line.slice(0, this.st.cursorCol) +
              line.slice(this.st.cursorCol + 1);
            this.triggerOnChange();
          }
        }
        this.lastChange = "s";
        this.switchMode("insert");
        return;

      case "S":
        // Substitute entire line
        this.pushUndo();
        this.register = this.curLine();
        this.registerLinewise = false;
        this.st.lines[this.st.cursorLine] = "";
        this.doSetCursorCol(0);
        this.triggerOnChange();
        this.lastChange = "S";
        this.switchMode("insert");
        return;

      case "p":
        this.paste(false, count);
        return;

      case "P":
        this.paste(true, count);
        return;

      case "u":
        (this as any).undo();
        this.invalidate();
        return;

      case ".":
        this.dotRepeat();
        return;

      case "J":
        this.joinLines(count);
        return;

      case "~":
        this.toggleCase(count);
        return;

      case "D":
        // Delete to end of line
        this.applyOperator("d", this.motionLineEnd(1));
        this.lastChange = "D";
        return;

      case "C":
        // Change to end of line
        this.applyOperator("c", this.motionLineEnd(1));
        this.lastChange = "C";
        return;

      case "Y":
        // Yank line
        this.applyOperator("y", {
          start: { line: this.st.cursorLine, col: 0 },
          end: { line: this.st.cursorLine, col: this.curLine().length },
          linewise: true,
        });
        return;

      // ── Scroll ──
      // Ctrl-d / Ctrl-u are handled via escape sequences
      default:
        if (matchesKey(key, "ctrl+d")) {
          this.pageScroll(1, count);
          return;
        }
        if (matchesKey(key, "ctrl+u")) {
          this.pageScroll(-1, count);
          return;
        }
        if (matchesKey(key, "ctrl+r")) {
          // Redo — not available in base editor, ignore
          return;
        }

        // ── Leader key(s) ──
        if (this.leaderMenus.has(key)) {
          this.leaderPending = true;
          this.activeLeaderMenu = this.leaderMenus.get(key)!;
          this.scheduleLeaderOverlay();
          return;
        }

        // Ignore unrecognized keys in normal mode
        break;
    }
  }

  // ─── Operator-pending mode ───────────────────────────────────────────

  private handleOperatorPending(data: string): void {
    const op = this.pendingOperator!;
    const count = this.consumeCount();

    // Accumulate more count digits
    if (data >= "1" && data <= "9") {
      this.countStr += data;
      return;
    }
    if (data === "0" && this.countStr.length > 0) {
      this.countStr += data;
      return;
    }

    // Doubled operator = operate on current line(s)
    if (data === op) {
      this.pendingOperator = null;
      const startLine = this.st.cursorLine;
      const endLine = Math.min(this.st.lines.length - 1, startLine + count - 1);
      const range: Range = {
        start: { line: startLine, col: 0 },
        end: { line: endLine, col: this.lineText(endLine).length },
        linewise: true,
      };
      const recordStr = count > 1 ? `${count}${op}${op}` : `${op}${op}`;
      this.applyOperator(op, range);
      this.lastChange = recordStr;
      return;
    }

    // Text object: i/a followed by object key
    if (data === "i" || data === "a") {
      // Need another key for the text object type
      this.pendingOperator = null;
      // Store state and wait for next key
      const modifier = data;
      const originalOp = op;
      // Temporarily hijack handleInput for the next key
      const origHandler = this.handleInput.bind(this);
      this.handleInput = (nextKey: string) => {
        this.handleInput = origHandler;
        const range = this.parseTextObject(modifier, nextKey);
        if (range) {
          this.applyOperator(originalOp, range);
          this.lastChange = `${originalOp}${modifier}${nextKey}`;
        }
      };
      return;
    }

    // f/t/F/T in operator-pending
    if (data === "f" || data === "F" || data === "t" || data === "T") {
      this.pendingOperator = null;
      const findType = data as "f" | "F" | "t" | "T";
      const originalOp = op;
      const origHandler = this.handleInput.bind(this);
      this.handleInput = (charKey: string) => {
        this.handleInput = origHandler;
        const range = this.motionFindChar(findType, charKey, count);
        if (range) {
          this.lastFind = { type: findType, char: charKey };
          this.applyOperator(originalOp, range);
          this.lastChange = `${originalOp}${findType}${charKey}`;
        }
      };
      return;
    }

    // Try as a motion
    const motion = this.resolveMotion(data, count);
    this.pendingOperator = null;
    if (motion) {
      const recordStr = count > 1 ? `${op}${count}${data}` : `${op}${data}`;
      this.applyOperator(op, motion);
      this.lastChange = recordStr;
    }
    // If not a valid motion, just cancel
  }

  // ─── Pending find (f/t/F/T) in normal mode ──────────────────────────

  private handlePendingFind(data: string): void {
    const findType = this.pendingFind!.type;
    this.pendingFind = null;
    const count = this.consumeCount();

    const range = this.motionFindChar(findType, data, count);
    if (range) {
      this.lastFind = { type: findType, char: data };
      // Move cursor to the found char
      const pos = this.curPos();
      const forward = findType === "f" || findType === "t";
      if (forward) {
        this.setCursor(range.end.line, range.end.col - 1);
      } else {
        this.setCursor(range.start.line, range.start.col);
      }
      this.invalidate();
    }
  }

  // ─── Pending replace (r) ─────────────────────────────────────────────

  private handlePendingReplace(data: string): void {
    this.pendingReplace = false;
    if (data.length !== 1 || data.charCodeAt(0) < 32) return;

    const line = this.curLine();
    const col = this.st.cursorCol;
    if (col >= line.length) return;

    this.pushUndo();
    this.st.lines[this.st.cursorLine] =
      line.slice(0, col) + data + line.slice(col + 1);
    this.triggerOnChange();
    this.lastChange = `r${data}`;
    this.invalidate();
  }

  // ─── Visual mode ─────────────────────────────────────────────────────

  private handleVisualMode(data: string): void {
    if (matchesKey(data, "escape")) {
      this.switchMode("normal");
      return;
    }

    // Count accumulation
    if (data >= "1" && data <= "9") {
      this.countStr += data;
      return;
    }
    if (data === "0" && this.countStr.length > 0) {
      this.countStr += data;
      return;
    }

    const count = this.consumeCount();

    // Motions — extend selection
    const motion = this.resolveMotion(data, count);
    if (motion) {
      const pos = this.curPos();
      if (data === "j") {
        this.setCursor(
          Math.min(this.st.lines.length - 1, pos.line + count),
          pos.col,
        );
      } else if (data === "k") {
        this.setCursor(Math.max(0, pos.line - count), pos.col);
      } else {
        const target =
          comparePos(pos, motion.start) === 0 ? motion.end : motion.start;
        this.setCursor(target.line, target.col);
      }
      this.invalidate();
      return;
    }

    // f/t/F/T in visual
    if (data === "f" || data === "F" || data === "t" || data === "T") {
      const findType = data as "f" | "F" | "t" | "T";
      const origHandler = this.handleInput.bind(this);
      this.handleInput = (charKey: string) => {
        this.handleInput = origHandler;
        const range = this.motionFindChar(findType, charKey, count);
        if (range) {
          this.lastFind = { type: findType, char: charKey };
          const forward = findType === "f" || findType === "t";
          if (forward) {
            this.setCursor(range.end.line, range.end.col - 1);
          } else {
            this.setCursor(range.start.line, range.start.col);
          }
          this.invalidate();
        }
      };
      return;
    }

    // Operators on selection
    switch (data) {
      case "d":
      case "x": {
        const range = this.getVisualRange();
        this.applyOperator("d", range);
        this.lastChange = null;
        this.switchMode("normal");
        return;
      }
      case "c":
      case "s": {
        const range = this.getVisualRange();
        this.applyOperator("c", range);
        this.lastChange = null;
        return;
      }
      case "y": {
        const range = this.getVisualRange();
        this.applyOperator("y", range);
        this.switchMode("normal");
        return;
      }
      case ">": {
        const range = this.getVisualRange();
        this.pushUndo();
        this.indentLines(range.start.line, range.end.line, false);
        this.switchMode("normal");
        return;
      }
      case "<": {
        const range = this.getVisualRange();
        this.pushUndo();
        this.indentLines(range.start.line, range.end.line, true);
        this.switchMode("normal");
        return;
      }
      case "~": {
        const range = this.getVisualRange();
        this.pushUndo();
        this.toggleCaseInRange(range);
        this.switchMode("normal");
        return;
      }
      case "u": {
        const range = this.getVisualRange();
        this.pushUndo();
        this.changeCaseInRange(range, "lower");
        this.switchMode("normal");
        return;
      }
      case "U": {
        const range = this.getVisualRange();
        this.pushUndo();
        this.changeCaseInRange(range, "upper");
        this.switchMode("normal");
        return;
      }
      case "o": {
        // Swap cursor and anchor
        const tmp = this.curPos();
        this.setCursor(this.visualAnchor.line, this.visualAnchor.col);
        this.visualAnchor = tmp;
        this.invalidate();
        return;
      }
      case "v": {
        if (this.mode === "visual") {
          this.switchMode("normal");
        } else {
          this.mode = "visual";
          this.invalidate();
        }
        return;
      }
      case "V": {
        if (this.mode === "visual-line") {
          this.switchMode("normal");
        } else {
          this.mode = "visual-line";
          this.invalidate();
        }
        return;
      }
    }
  }

  // ─── Paste ───────────────────────────────────────────────────────────

  private paste(before: boolean, count: number): void {
    if (!this.register) return;
    this.pushUndo();

    const st = this.st;
    for (let i = 0; i < count; i++) {
      if (this.registerLinewise) {
        const text = this.register.endsWith("\n")
          ? this.register.slice(0, -1)
          : this.register;
        const lines = text.split("\n");
        if (before) {
          st.lines.splice(st.cursorLine, 0, ...lines);
        } else {
          st.lines.splice(st.cursorLine + 1, 0, ...lines);
          if (i === 0) st.cursorLine++;
        }
        // Move to first non-blank of first pasted line
        const pastedLine = this.lineText(st.cursorLine);
        const fnb = pastedLine.search(/\S/);
        this.doSetCursorCol(fnb >= 0 ? fnb : 0);
      } else {
        const line = this.curLine();
        if (before) {
          const endPos = this.insertTextAt(
            { line: st.cursorLine, col: st.cursorCol },
            this.register,
          );
          this.setCursor(endPos.line, Math.max(0, endPos.col - 1));
        } else {
          const insertCol = Math.min(st.cursorCol + 1, line.length);
          const endPos = this.insertTextAt(
            { line: st.cursorLine, col: insertCol },
            this.register,
          );
          this.setCursor(endPos.line, Math.max(0, endPos.col - 1));
        }
      }
    }

    this.triggerOnChange();
    this.lastChange = before
      ? `${count > 1 ? count : ""}P`
      : `${count > 1 ? count : ""}p`;
    this.invalidate();
  }

  // ─── Join lines ──────────────────────────────────────────────────────

  private joinLines(count: number): void {
    const st = this.st;
    this.pushUndo();

    for (let i = 0; i < count; i++) {
      if (st.cursorLine >= st.lines.length - 1) break;
      const line = this.curLine();
      const nextLine = (st.lines[st.cursorLine + 1] ?? "").trimStart();
      const joinCol = line.length;
      st.lines[st.cursorLine] = line + (nextLine ? " " + nextLine : "");
      st.lines.splice(st.cursorLine + 1, 1);
      this.doSetCursorCol(joinCol);
    }

    this.triggerOnChange();
    this.lastChange = count > 1 ? `${count}J` : "J";
    this.invalidate();
  }

  // ─── Toggle case ─────────────────────────────────────────────────────

  private toggleCase(count: number): void {
    const st = this.st;
    const line = this.curLine();
    this.pushUndo();

    let col = st.cursorCol;
    const chars = line.split("");
    for (let i = 0; i < count && col < chars.length; i++, col++) {
      const ch = chars[col];
      chars[col] =
        ch === ch.toLowerCase() ? ch.toUpperCase() : ch.toLowerCase();
    }
    st.lines[st.cursorLine] = chars.join("");
    this.doSetCursorCol(Math.min(col, Math.max(0, chars.length - 1)));
    this.triggerOnChange();
    this.lastChange = count > 1 ? `${count}~` : "~";
    this.invalidate();
  }

  private toggleCaseInRange(range: Range): void {
    const st = this.st;
    if (range.linewise) {
      for (let l = range.start.line; l <= range.end.line; l++) {
        st.lines[l] = (st.lines[l] ?? "")
          .split("")
          .map((ch) =>
            ch === ch.toLowerCase() ? ch.toUpperCase() : ch.toLowerCase(),
          )
          .join("");
      }
    } else {
      if (range.start.line === range.end.line) {
        const line = st.lines[range.start.line] ?? "";
        const before = line.slice(0, range.start.col);
        const middle = line
          .slice(range.start.col, range.end.col)
          .split("")
          .map((ch) =>
            ch === ch.toLowerCase() ? ch.toUpperCase() : ch.toLowerCase(),
          )
          .join("");
        const after = line.slice(range.end.col);
        st.lines[range.start.line] = before + middle + after;
      }
    }
    this.triggerOnChange();
    this.invalidate();
  }

  private changeCaseInRange(range: Range, toCase: "upper" | "lower"): void {
    const st = this.st;
    const transform =
      toCase === "upper"
        ? (s: string) => s.toUpperCase()
        : (s: string) => s.toLowerCase();
    if (range.linewise) {
      for (let l = range.start.line; l <= range.end.line; l++) {
        st.lines[l] = transform(st.lines[l] ?? "");
      }
    } else if (range.start.line === range.end.line) {
      const line = st.lines[range.start.line] ?? "";
      st.lines[range.start.line] =
        line.slice(0, range.start.col) +
        transform(line.slice(range.start.col, range.end.col)) +
        line.slice(range.end.col);
    }
    this.setCursor(range.start.line, range.start.col);
    this.triggerOnChange();
    this.invalidate();
  }

  // ─── Page scroll ─────────────────────────────────────────────────────

  private pageScroll(direction: number, count: number): void {
    // Approximate half-page as 10 lines
    const amount = 10 * count * direction;
    const newLine = clamp(
      this.st.cursorLine + amount,
      0,
      this.st.lines.length - 1,
    );
    this.setCursor(newLine, this.st.cursorCol);
    this.invalidate();
  }

  // ─── Dot repeat ──────────────────────────────────────────────────────

  private dotRepeat(): void {
    if (!this.lastChange) return;
    this.replaying = true;
    for (const ch of this.lastChange) {
      this.handleInput(ch);
    }
    this.replaying = false;
  }

  // ─── Leader key ──────────────────────────────────────────────────────

  // ─── Leader overlay ───────────────────────────────────────────────

  /** Leader menus keyed by trigger key (e.g. " " for Space). Loaded from keybindings.json. */
  private leaderMenus: Map<string, LeaderNode> = new Map();

  /** The currently active leader menu root (set when a leader key is pressed) */
  private activeLeaderMenu: LeaderNode | null = null;

  /** Pass a key sequence through to pi */
  passthrough(seq: string): void {
    super.handleInput(seq);
  }

  /** Resolve the current leader node from leaderPath */
  private currentLeaderNode(): LeaderNode | null {
    if (!this.activeLeaderMenu) return null;
    let node = this.activeLeaderMenu;
    for (const key of this.leaderPath) {
      const child = node.children?.find((c) => c.key === key);
      if (child && "children" in child) {
        node = child;
      } else {
        break;
      }
    }
    return node;
  }

  private scheduleLeaderOverlay(): void {
    this.clearLeaderOverlay();
    this.leaderOverlayTimer = setTimeout(() => {
      this.leaderOverlayTimer = null;
      this.showLeaderOverlay();
    }, this.leaderOverlayDelay);
  }

  private showLeaderOverlay(): void {
    if (!this.ctx?.ui || !this.leaderPending) return;
    const node = this.currentLeaderNode();
    if (!node?.children) return;
    this.leaderOverlayVisible = true;
    const entries = node.children;
    const title = node.label ?? "Leader";
    const pathPrefix =
      this.leaderPath.length > 0
        ? "Space " + this.leaderPath.join(" ") + " "
        : "Space ";
    this.ctx.ui.setWidget("leader-menu", (_tui: any, theme: any) => {
      const lines: string[] = [];
      const header = theme.bold ? theme.bold(title) : title;
      lines.push(" " + header);
      for (const b of entries) {
        const keyStr = theme.fg ? theme.fg("accent", b.key) : b.key;
        const suffix = "children" in b ? " →" : "";
        const labelStr = theme.fg
          ? theme.fg("muted", b.label + suffix)
          : b.label + suffix;
        lines.push("  " + keyStr + "  " + labelStr);
      }
      lines.push("");
      return {
        render: () => lines,
        invalidate: () => {},
      };
    });
  }

  private clearLeaderOverlay(): void {
    if (this.leaderOverlayTimer) {
      clearTimeout(this.leaderOverlayTimer);
      this.leaderOverlayTimer = null;
    }
    if (this.leaderOverlayVisible && this.ctx?.ui) {
      this.leaderOverlayVisible = false;
      this.ctx.ui.setWidget("leader-menu", undefined);
    }
  }

  private handleLeader(data: string): void {
    if (!this.ctx) {
      this.leaderPending = false;
      this.leaderPath = [];
      this.activeLeaderMenu = null;
      this.clearLeaderOverlay();
      return;
    }

    const node = this.currentLeaderNode();
    if (!node) {
      this.leaderPending = false;
      this.leaderPath = [];
      this.activeLeaderMenu = null;
      this.clearLeaderOverlay();
      return;
    }
    const match = node.children?.find((c) => keyMatches(data, c.key));

    if (match && "children" in match) {
      // Descend into sub-menu
      this.leaderPath.push(match.key);
      // Reset overlay timer for the sub-menu
      this.scheduleLeaderOverlay();
      return;
    }

    // Either a leaf action or unrecognized key — exit leader
    this.leaderPending = false;
    this.leaderPath = [];
    this.activeLeaderMenu = null;
    this.clearLeaderOverlay();

    if (match && "action" in match) {
      match.action();
    }
  }

  /** Submit a slash command by setting editor text and simulating Enter */
  submitCommand(command: string): void {
    if (this.ctx?.ui) {
      this.ctx.ui.setEditorText(command);
      // Simulate Enter to submit
      super.handleInput("\r");
    }
  }

  // ─── Render ──────────────────────────────────────────────────────────

  render(width: number): string[] {
    const reservedCols =
      this.widthConstraintFraction > 0
        ? Math.max(
            this.widthConstraintMinCols,
            Math.floor(width * this.widthConstraintFraction),
          )
        : 0;
    const effectiveWidth =
      reservedCols > 0 ? Math.max(40, width - reservedCols) : width;
    const lines = super.render(effectiveWidth);
    if (lines.length === 0) return lines;

    const last = lines.length - 1;

    // Pending indicator (mode itself is exposed via ctx.ui.setStatus)
    let pending = "";
    if (this.countStr) pending += this.countStr;
    if (this.pendingOperator) pending += this.pendingOperator;
    if (this.pendingFind) pending += this.pendingFind.type;
    if (this.pendingReplace) pending += "r";
    if (this.leaderPending) {
      pending += "SPC";
      if (this.leaderPath.length > 0)
        pending += " " + this.leaderPath.join(" ");
    }
    if (pending) pending = " " + pending + " ";

    const totalSuffix = pending;
    if (totalSuffix && visibleWidth(lines[last]!) >= totalSuffix.length) {
      lines[last] =
        truncateToWidth(lines[last]!, effectiveWidth - totalSuffix.length, "") +
        totalSuffix;
    }

    // Visual mode highlighting — render selection via ANSI reverse video
    if (this.mode === "visual" || this.mode === "visual-line") {
      const range = this.getVisualRange();
      // We'd need to modify rendered lines with ANSI codes
      // For now, the mode indicator and cursor position convey the selection
      // Full highlighting would require deeper integration with the render pipeline
    }

    return lines;
  }
}

// ─── Extension entry point ───────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  let activeEditor: VimEditor | null = null;
  let currentCtx: any = null;
  let actionHost: LeaderActionHost | null = null;
  let leaderMenus: Map<string, LeaderNode> = new Map();
  let previousEditorFactory: any = undefined;

  /** Pending keybinding suggestions received before the session was ready. */
  const pendingSuggestions: KeybindingSuggestion[] = [];

  /** Cleanup functions for pi.events listeners, called on session_shutdown. */
  const eventCleanups: (() => void)[] = [];

  /**
   * Merge a KeybindingsConfig into the editor's live leader menus.
   * Uses the same JSON format as keybindings.json — callers can supply
   * a full or partial config with just the menus they want to add.
   *
   * Menu items are merged additively:
   *   - New menu keys create new leader roots.
   *   - Existing menu keys merge their items (new items added).
   *   - If a suggested key clashes with an existing binding, the
   *     suggestion is ignored and a warning is shown.
   *   - Two sub-menus on the same key are merged recursively.
   */
  function applySuggestions(
    menus: Map<string, LeaderNode>,
    host: LeaderActionHost,
    config: KeybindingSuggestion,
    notify?: (msg: string, level: "info" | "warning" | "error") => void,
  ): void {
    if (!config?.menus) return;
    const incoming = buildMenuTree(config, host);
    const source = config.source ?? "unknown";
    const warn =
      notify ?? ((_m: string, _l: "info" | "warning" | "error") => {});

    warnClashingLeaderKeys(incoming, source, warn);

    for (const [triggerKey, incomingNode] of incoming) {
      const existing = menus;
      const current = existing.get(triggerKey);
      if (!current || !current.children) {
        existing.set(triggerKey, incomingNode);
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

    warn(`keybindings: applied for ${source}`, "info");
  }

  /**
   * Recursively merge incoming children into an existing children array.
   * `pathPrefix` tracks the key path for warning messages.
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
        // No clash — add the new entry
        existing.push(child);
        continue;
      }

      const existingChild = existing[idx];
      const keyPath = `${pathPrefix} ${child.key}`;
      const bothSubMenus = existingChild.children && child.children;

      if (bothSubMenus) {
        // Both are sub-menus — merge recursively
        mergeChildren(
          existingChild.children!,
          child.children!,
          keyPath,
          source,
          warn,
        );
      } else if (existingChild.label === child.label) {
        // Duplicate re-send (common after keybindings:ready) — skip quietly.
        continue;
      } else {
        // Clash: existing leaf vs incoming, or type mismatch — skip
        warn(
          `keybindings: ignoring suggested binding [${keyPath}] ` +
            `("${child.label}" from ${source}) — ` +
            `clashes with existing binding "${existingChild.label}"`,
          "warning",
        );
      }
    }
  }

  let sessionNotify:
    | ((msg: string, level: "info" | "warning" | "error") => void)
    | null = null;

  function createActionHost(ctx: any): LeaderActionHost {
    return {
      submitCommand(command: string) {
        if (activeEditor) {
          activeEditor.submitCommand(command);
          return;
        }
        ctx.ui.setEditorText(command);
        ctx.ui.notify(`Keybindings: inserted ${command}; press Enter to run`, "info");
      },
      passthrough(keyName: string, seq: string) {
        if (activeEditor && seq) {
          activeEditor.passthrough(seq);
          return;
        }
        switch (keyName) {
          case "ctrl+o": {
            const expanded = ctx.ui.getToolsExpanded?.() ?? false;
            ctx.ui.setToolsExpanded?.(!expanded);
            return;
          }
          case "shift+tab": {
            const levels = ["off", "minimal", "low", "medium", "high", "xhigh"] as const;
            const current = pi.getThinkingLevel?.() ?? "off";
            const next = levels[(Math.max(0, levels.indexOf(current as any)) + 1) % levels.length];
            pi.setThinkingLevel?.(next);
            return;
          }
          case "ctrl+l":
            ctx.ui.setEditorText("/model");
            ctx.ui.notify("Keybindings: inserted /model; press Enter to select model", "info");
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

  function installModalEditor(ctx: any): void {
    if (activeEditor) {
      activeEditor.setModalEnabled(true);
      return;
    }

    previousEditorFactory =
      typeof ctx.ui.getEditorComponent === "function"
        ? ctx.ui.getEditorComponent()
        : undefined;
    if (previousEditorFactory) {
      ctx.ui.notify(
        "Keybindings: Vim mode replaces the current editor; editor composition is not yet supported",
        "warning",
      );
    }

    ctx.ui.setEditorComponent(
      (tui: TUI, theme: EditorTheme, keybindings: KeybindingsManager) => {
        const editor = new VimEditor(tui, theme, keybindings);
        editor.setContext(ctx);
        editor.setLeaderMenus(leaderMenus);
        const settings = loadUserSettings();
        editor.setModalEnabled(true);
        editor.setDebugEnabled(settings.debug);
        activeEditor = editor;
        return editor;
      },
    );
  }

  function uninstallModalEditor(ctx: any): void {
    if (!activeEditor) {
      ctx.ui.setStatus("keybindings", undefined);
      return;
    }
    activeEditor.setModalEnabled(false);
    activeEditor = null;
    ctx.ui.setStatus("keybindings", undefined);
    ctx.ui.setEditorComponent(previousEditorFactory ?? undefined);
    previousEditorFactory = undefined;
  }

  async function showLeaderOverlay(ctx: any, rootKey: string): Promise<void> {
    if (!ctx.hasUI) return;
    if (!leaderMenus.has(rootKey)) {
      ctx.ui.notify(`Keybindings: no ${displayKey(rootKey)} leader menu loaded`, "warning");
      return;
    }
    await ctx.ui.custom<undefined>(
      (tui: TUI, theme: any, _kb: KeybindingsManager, done: (value: undefined) => void) =>
        new LeaderMenuOverlay(tui, leaderMenus, theme, () => done(undefined), rootKey),
      { overlay: true },
    );
  }

  pi.registerShortcut("alt+space", {
    description: "Open Space leader menu",
    handler: async (ctx) => {
      await showLeaderOverlay(ctx, " ");
    },
  });

  pi.registerShortcut("alt+,", {
    description: "Open comma leader menu",
    handler: async (ctx) => {
      await showLeaderOverlay(ctx, ",");
    },
  });

  pi.on("session_shutdown", () => {
    // Clean up shared event bus listeners to prevent accumulation on reload
    for (const cleanup of eventCleanups) cleanup();
    eventCleanups.length = 0;
    currentCtx?.ui?.setStatus?.("keybindings", undefined);
    activeEditor = null;
    currentCtx = null;
    actionHost = null;
    leaderMenus = new Map();
    previousEditorFactory = undefined;
    sessionNotify = null;
  });

  pi.on("session_start", (_event, ctx) => {
    sessionNotify = ctx.ui.notify.bind(ctx.ui);
    currentCtx = ctx;
    actionHost = createActionHost(ctx);

    const config = loadKeybindingsConfig();
    leaderMenus = buildMenuTree(config, actionHost);
    warnClashingLeaderKeys(leaderMenus, "defaults.json", sessionNotify ?? undefined);

    for (const suggestion of pendingSuggestions) {
      applySuggestions(leaderMenus, actionHost, suggestion, sessionNotify ?? undefined);
    }
    pendingSuggestions.length = 0;

    const settings = loadUserSettings();
    if (settings.modal) {
      installModalEditor(ctx);
    } else {
      activeEditor = null;
      ctx.ui.setStatus("keybindings", undefined);
    }

    // Signal that leader menus are ready and accepting suggestions.
    pi.events.emit("keybindings:ready", {});
  });

  // Allow other extensions (e.g. git-diff) to constrain editor width
  // without replacing the editor component.
  // Emit { fraction, minCols } to reserve space, or { fraction: 0 } to clear.
  eventCleanups.push(
    pi.events.on("editor:width-constraint", (data: any) => {
      const fraction = typeof data?.fraction === "number" ? data.fraction : 0;
      const minCols = typeof data?.minCols === "number" ? data.minCols : 0;
      activeEditor?.setWidthConstraint(fraction, minCols);
    }),
  );

  /**
   * Accept keybinding suggestions from other extensions.
   *
   * Data should be a KeybindingsConfig object in the same JSON format as
   * keybindings.json. For example:
   *
   *   pi.events.emit("keybindings:suggest", {
   *     source: "my-extension",
   *     menus: {
   *       "term": {
   *         label: "Terminal",
   *         key: " ",          // trigger key (" " = Space leader)
   *         items: {
   *           "t": {
   *             label: "+terminal",
   *             items: {
   *               "t": { label: "Toggle mirror", action: "term:toggle" },
   *               "n": { label: "Next tab",      action: "term:next" },
   *             }
   *           }
   *         }
   *       }
   *     }
   *   });
   *
   * Can be called before or after session_start — early suggestions are
   * queued and applied once the leader menus initialise.
   */
  eventCleanups.push(
    pi.events.on(
      "keybindings:suggest",
      (data: KeybindingSuggestion) => {
        if (actionHost && sessionNotify) {
          applySuggestions(leaderMenus, actionHost, data, sessionNotify);
          activeEditor?.setLeaderMenus(leaderMenus);
        } else {
          pendingSuggestions.push(data);
        }
      },
    ),
  );

  // ── Mode toggling ──────────────────────────────────────────────────

  function setMode(mode: "emacs" | "vim"): void {
    const modal = mode === "vim";
    if (currentCtx) {
      if (modal) installModalEditor(currentCtx);
      else uninstallModalEditor(currentCtx);
    }
    saveUserSettings({ modal });
    sessionNotify?.(`Editor: ${modal ? "Vim" : "Emacs"} mode`, "info");
  }

  eventCleanups.push(
    pi.events.on("keybindings:set-mode-vim", () => setMode("vim")),
  );
  eventCleanups.push(
    pi.events.on("keybindings:set-mode-emacs", () => setMode("emacs")),
  );

  // ── /kb command ─────────────────────────────────────────────────────

  pi.registerCommand("kb", {
    description: "Keybindings utilities: /kb bindings | /kb mode emacs|vim",
    handler: async (args, ctx) => {
      const trimmed = (args ?? "").trim();
      const parts = trimmed.split(/\s+/).filter(Boolean);
      const sub = parts[0] ?? "";

      if (sub === "bindings") {
        if (!ctx.hasUI) {
          ctx.ui.notify("/kb bindings requires interactive mode", "error");
          return;
        }
        await ctx.ui.custom<undefined>(
          (_tui, theme, _kb, done) => {
            return new BindingsOverlay(leaderMenus, theme, () => done(undefined));
          },
          { overlay: true },
        );
        return;
      }

      if (sub === "mode") {
        const arg = parts[1];
        if (arg !== "emacs" && arg !== "vim") {
          ctx.ui.notify("Usage: /kb mode emacs|vim", "error");
          return;
        }
        setMode(arg);
        return;
      }

      ctx.ui.notify("Usage: /kb bindings | /kb mode emacs|vim", "info");
    },
  });
}

// ─── Leader menu overlay ─────────────────────────────────────────────────────

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

    if ("children" in match) {
      this.activeNode = match;
      this.path.push(displayKey(match.key));
      this.tui.requestRender();
      return true;
    }

    match.action();
    this.done();
    return true;
  }

  render(width: number): string[] {
    const node = this.activeNode;
    const entries = node?.children ?? [...this.menus.entries()].map(([key, root]) => ({
      key,
      label: root.label ?? displayKey(key),
      children: root.children,
    }));
    const title = node?.label ?? "Leader";
    const path = this.path.length > 0 ? ` (${this.path.join(" ")})` : "";
    const innerW = Math.max(20, Math.min(width - 4, 72));
    const hBar = "─".repeat(innerW + 2);
    const topBorder = `╭${hBar}╮`;
    const botBorder = `╰${hBar}╯`;
    const lines = [topBorder];
    lines.push(`│ ${ansiPad(this.theme.bold ? this.theme.bold(title + path) : title + path, innerW)} │`);
    lines.push(`│ ${ansiPad("", innerW)} │`);

    for (const entry of entries) {
      const suffix = "children" in entry ? " →" : "";
      const keyStr = this.theme.fg ? this.theme.fg("accent", displayKey(entry.key)) : displayKey(entry.key);
      const labelStr = this.theme.fg ? this.theme.fg("muted", entry.label + suffix) : entry.label + suffix;
      lines.push(`│ ${ansiPad(`${keyStr}  ${labelStr}`, innerW)} │`);
    }

    lines.push(botBorder);
    return lines;
  }

  invalidate(): void {
    this.tui.requestRender();
  }
}

// ─── Bindings overlay ────────────────────────────────────────────────────────

class BindingsOverlay {
  private theme: any;
  private done: () => void;
  private flatLines: { prefix: string; label: string; depth: number }[] = [];
  private scrollOffset = 0;
  private selected = 0;
  private cachedWidth?: number;
  private cachedLines?: string[];

  constructor(menus: Map<string, LeaderNode>, theme: any, done: () => void) {
    this.theme = theme;
    this.done = done;
    this.flatten(menus);
  }

  private flatten(menus: Map<string, LeaderNode>): void {
    const displayKey = (k: string) => (k === " " ? "SPC" : k);

    const walk = (entries: LeaderEntry[], path: string[], depth: number) => {
      for (const entry of entries) {
        const keyPath = [...path, displayKey(entry.key)];
        if (entry.children) {
          this.flatLines.push({
            prefix: keyPath.join(" "),
            label: entry.label,
            depth,
          });
          walk(entry.children, keyPath, depth + 1);
        } else {
          this.flatLines.push({
            prefix: keyPath.join(" "),
            label: entry.label,
            depth,
          });
        }
      }
    };

    for (const [triggerKey, node] of menus) {
      const rootKey = displayKey(triggerKey);
      if (node.children) {
        this.flatLines.push({
          prefix: rootKey,
          label: node.label ?? "Leader",
          depth: 0,
        });
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
      if (this.selected > 0) {
        this.selected--;
        this.invalidate();
      }
      return;
    }
    if (matchesKey(data, "down") || matchesKey(data, "j")) {
      if (this.selected < this.flatLines.length - 1) {
        this.selected++;
        this.invalidate();
      }
      return;
    }
  }

  render(width: number): string[] {
    if (this.cachedLines && this.cachedWidth === width) {
      return this.cachedLines;
    }

    const th = this.theme;
    const innerW = width - 4;
    const lines: string[] = [];

    const hBar = (n: number) => "─".repeat(Math.max(0, n));
    const topBorder = th.fg("border", `╭${hBar(width - 2)}╮`);
    const botBorder = th.fg("border", `╰${hBar(width - 2)}╯`);

    const row = (content: string) => {
      return th.fg("border", "│") + " " + ansiPad(content, innerW) + " " + th.fg("border", "│");
    };

    const emptyRow = () => row("");

    lines.push(topBorder);
    lines.push(row(th.fg("accent", th.bold("Keybindings"))));
    lines.push(emptyRow());

    if (this.flatLines.length === 0) {
      lines.push(row(th.fg("dim", "No keybindings registered.")));
      lines.push(emptyRow());
      lines.push(row(th.fg("dim", "Press Esc or q to close")));
      lines.push(botBorder);
      this.cachedWidth = width;
      this.cachedLines = lines;
      return lines;
    }

    const maxVisible = 20;
    // Adjust scroll
    if (this.selected < this.scrollOffset) this.scrollOffset = this.selected;
    if (this.selected >= this.scrollOffset + maxVisible)
      this.scrollOffset = this.selected - maxVisible + 1;

    const visible = this.flatLines.slice(
      this.scrollOffset,
      this.scrollOffset + maxVisible,
    );

    for (let i = 0; i < visible.length; i++) {
      const entry = visible[i]!;
      const globalIdx = this.scrollOffset + i;
      const isSelected = globalIdx === this.selected;

      const indent = "  ".repeat(entry.depth);
      const keyStr = th.fg("accent", entry.prefix.padEnd(16));
      const labelStr = isSelected
        ? th.fg("text", entry.label)
        : th.fg("muted", entry.label);
      const pointer = isSelected ? th.fg("accent", "▌") : " ";

      lines.push(
        row(
          truncateToWidth(`${pointer}${indent}${keyStr} ${labelStr}`, innerW),
        ),
      );
    }

    if (this.flatLines.length > maxVisible) {
      const pos = Math.round(
        (this.scrollOffset / Math.max(1, this.flatLines.length - maxVisible)) *
          100,
      );
      lines.push(
        row(
          th.fg(
            "dim",
            `  ${this.scrollOffset + 1}-${Math.min(this.scrollOffset + maxVisible, this.flatLines.length)} of ${this.flatLines.length} (${pos}%)`,
          ),
        ),
      );
    }

    lines.push(emptyRow());
    lines.push(row(th.fg("dim", "↑↓/jk navigate • Esc/q close")));
    lines.push(botBorder);

    this.cachedWidth = width;
    this.cachedLines = lines;
    return lines;
  }

  invalidate(): void {
    this.cachedWidth = undefined;
    this.cachedLines = undefined;
  }
}
