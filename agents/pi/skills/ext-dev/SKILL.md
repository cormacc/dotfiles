---
name: ext-dev
description: Develop, modify, or debug pi extensions. Use when creating new extensions, modifying existing ones, or troubleshooting extension issues. Covers the extension API, TUI components, keybindings, theming, and custom editors.
---

# Pi Extension Development

## Workflow

1. **Read the documentation** before writing any code — do not guess APIs.
   Load the docs listed below with the `read` tool.
2. **Load extension source** with `/ext <name>` (autocompletes extension names).
   Use `/ext` with no arguments to list available extensions.
3. **Read relevant examples** from the examples directory. Read `README.md`
   there first, then inspect specific examples as needed.

## Documentation

Read as needed (most to least commonly needed):

| Doc              | When to read                                                                   |
| ---------------- | ------------------------------------------------------------------------------ |
| `extensions.md`  | **Always** — core extension API, lifecycle, tools, commands, events, shortcuts |
| `tui.md`         | Custom renderers, widgets, overlays, Box/Text layout, themes                   |
| `keybindings.md` | KeybindingsManager, registerShortcut, key matching                             |
| `themes.md`      | Theme tokens, fg/bg/bold, EditorTheme vs MessageTheme                          |

Paths are in the system prompt under "Additional docs" and "Examples".

## Guidelines

- **Shared utilities** :: check `extensions/lib/pi-utils.ts` for reusable helpers
  (e.g. `getExtensionName`, `suggestKeybindings`) before writing new code.
- **Extension structure** :: single-file extensions go in `extensions/foo.ts`;
  multi-file extensions go in `extensions/foo/index.ts` with supporting modules.
- **Imports** :: use `@mariozechner/pi-coding-agent` for the extension API,
  `@mariozechner/pi-tui` for TUI primitives, `@sinclair/typebox` for tool
  parameter schemas.
- **Testing** :: use `/reload` to hot-reload extensions during development.
- **Documentation** :: Create a short README.md per extension.
  - Multi-file extensions :: `extensions/foo/README.md`
  - Single-file extensions :: `extensions/foo.md`
  - Include :: purpose, slash commands, dependencies, suggested keybindings.
  - Always update the readme after modifying an extension.

## Keybindings

Extensions should NOT bind keys explicitly. Instead, use `suggestKeybindings`
from `extensions/lib/pi-utils.ts` to register bindings with `modal-editor`.
Call `suggestKeybindings` inside `session_start` (not at the top level of the
default function) and store the cleanup handle at **module level** so it
survives reloads. Call the cleanup function on `session_shutdown`.

```typescript
const EXT_NAME = getExtensionName(import.meta.url);

/** Cleanup handle for keybinding suggestions, to avoid duplicates on reload. */
let cleanupKb: (() => void) | null = null;

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async () => {
    cleanupKb = suggestKeybindings(pi, EXT_NAME, {
      menus: {
        myMenu: {
          label: "My Menu",
          key: " ",
          items: {
            x: { label: "Do thing", action: "command:/my-cmd thing" },
          },
        },
      },
    });
  });

  pi.on("session_shutdown", async () => {
    cleanupKb?.();
    cleanupKb = null;
  });
}
```
