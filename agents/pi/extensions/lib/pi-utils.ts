/**
 * Derive the extension name from its module URL.
 *
 * - `extensions/my-ext/index.ts`  → `"my-ext"`   (parent directory name)
 * - `extensions/my-ext.ts`        → `"my-ext"`    (filename without extension)
 */
import { basename, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@mariozechner/pi-tui";

/**
 * Pad or truncate an ANSI-styled string to exactly `width` visible columns.
 * If the string is longer, it is truncated with an ellipsis.
 * If shorter, it is right-padded with spaces.
 */
export function ansiPad(s: string, width: number): string {
  const vis = visibleWidth(s);
  if (vis >= width) return truncateToWidth(s, width, "…", true);
  return s + " ".repeat(width - vis);
}

export function getExtensionName(importMetaUrl: string): string {
  const filePath = fileURLToPath(importMetaUrl);
  const fileName = basename(filePath, ".ts");
  if (fileName === "index") {
    return basename(dirname(filePath));
  }
  return fileName;
}

// ── Modal-editor keybinding suggestions ─────────────────────────────────────

/**
 * Menu item in a keybinding suggestion (matches the keybindings extension's JSON format).
 */
export interface KeybindingMenuItem {
  label: string;
  action?: string;
  items?: Record<string, KeybindingMenuItem>;
}

/**
 * A menu definition: the trigger key plus its items tree.
 */
export interface KeybindingMenu {
  label: string;
  key: string;
  items: Record<string, KeybindingMenuItem>;
}

/**
 * Payload accepted by `keybindings:suggest`.
 */
export interface KeybindingSuggestion {
  source?: string;
  menus?: Record<string, KeybindingMenu>;
}

/**
 * Tracks active subscriptions so repeated calls for the same extension
 * automatically clean up the previous listener (safe across reloads).
 */
const activeKeybindingSubs = new Map<string, () => void>();

/**
 * Register keybinding suggestions with the keybindings extension.
 *
 * Handles the full lifecycle:
 *  - Emits suggestions immediately (in case the keybindings extension is already loaded).
 *  - Subscribes to `keybindings:ready` so suggestions are re-sent when the
 *    editor (re)initialises.
 *  - Automatically unsubscribes any prior listener for the same extension
 *    name, preventing duplicate callbacks on extension reload.
 *
 * Returns a cleanup function that unsubscribes the listener. Call it from
 * your `session_shutdown` handler.
 *
 * @example
 * ```ts
 * let cleanupKb: (() => void) | null = null;
 *
 * pi.on("session_start", async () => {
 *   cleanupKb = suggestKeybindings(pi, "my-ext", {
 *     menus: {
 *       myMenu: {
 *         label: "My Menu",
 *         key: " ",
 *         items: { x: { label: "Do X", action: "command:/my-cmd" } },
 *       },
 *     },
 *   });
 * });
 *
 * pi.on("session_shutdown", () => {
 *   cleanupKb?.();
 *   cleanupKb = null;
 * });
 * ```
 */
export function suggestKeybindings(
  pi: ExtensionAPI,
  extensionName: string,
  keybindings: KeybindingSuggestion,
): () => void {
  // Clean up any prior registration for this extension (handles reload)
  activeKeybindingSubs.get(extensionName)?.();

  // Inject source from extensionName so callers don't have to repeat it
  const payload = { ...keybindings, source: extensionName };

  const suggest = () => {
    pi.events.emit("keybindings:suggest", payload);
  };

  const unsub = pi.events.on("keybindings:ready", suggest);
  suggest();

  const cleanup = () => {
    unsub();
    activeKeybindingSubs.delete(extensionName);
  };

  activeKeybindingSubs.set(extensionName, cleanup);
  return cleanup;
}
