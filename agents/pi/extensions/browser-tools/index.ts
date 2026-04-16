import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import puppeteer, { type Browser, type Page } from "puppeteer-core";

const CDP_URL = "http://localhost:9222";
const CONNECT_TIMEOUT = 5000;

// ---------------------------------------------------------------------------
// Persistent connection state (lives in extension closure)
// ---------------------------------------------------------------------------

let browser: Browser | null = null;

async function ensureBrowser(): Promise<Browser> {
  // Check if existing connection is still alive
  if (browser) {
    try {
      // Quick liveness check
      await browser.version();
      return browser;
    } catch {
      browser = null;
    }
  }

  browser = await Promise.race([
    puppeteer.connect({ browserURL: CDP_URL, defaultViewport: null }),
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error("Connection timeout")), CONNECT_TIMEOUT)
    ),
  ]);

  return browser;
}

async function getActivePage(): Promise<Page> {
  const b = await ensureBrowser();
  const pages = await b.pages();
  const page = pages.at(-1);
  if (!page) throw new Error("No active tab found");
  return page;
}

async function getAllPages(): Promise<Page[]> {
  const b = await ensureBrowser();
  return b.pages();
}

// ---------------------------------------------------------------------------
// Extension entry point
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
  // Clean up on shutdown
  pi.on("session_shutdown", async () => {
    if (browser) {
      try {
        await browser.disconnect();
      } catch {}
      browser = null;
    }
  });

  // ------------------------------------------------------------------
  // browser_nav — Navigate to a URL
  // ------------------------------------------------------------------
  pi.registerTool({
    name: "browser_nav",
    label: "Browser Navigate",
    description:
      "Navigate the browser to a URL. Connects to Chromium on localhost:9222 (must be started with --remote-debugging-port=9222).",
    promptSnippet: "Navigate the browser to a URL, optionally in a new tab",
    parameters: Type.Object({
      url: Type.String({ description: "URL to navigate to" }),
      newTab: Type.Optional(
        Type.Boolean({ description: "Open in a new tab instead of reusing the active one" })
      ),
    }),
    async execute(_toolCallId, params, signal, onUpdate) {
      onUpdate?.({ content: [{ type: "text", text: `Navigating to ${params.url}...` }], details: {} });

      const b = await ensureBrowser();
      let page: Page;

      if (params.newTab) {
        page = await b.newPage();
      } else {
        page = await getActivePage();
      }

      await page.goto(params.url, { waitUntil: "domcontentloaded" });
      const title = await page.title();

      return {
        content: [{ type: "text", text: `${params.newTab ? "Opened" : "Navigated to"}: ${title}\nURL: ${page.url()}` }],
        details: { title, url: page.url() },
      };
    },
  });

  // ------------------------------------------------------------------
  // browser_eval — Evaluate JavaScript in the active tab
  // ------------------------------------------------------------------
  pi.registerTool({
    name: "browser_eval",
    label: "Browser Eval",
    description:
      "Evaluate JavaScript in the active browser tab. Code runs in an async context. Return values are serialized as text.",
    promptSnippet: "Evaluate JavaScript in the active browser tab",
    parameters: Type.Object({
      code: Type.String({ description: "JavaScript code to evaluate. Runs in async context." }),
    }),
    async execute(_toolCallId, params) {
      const page = await getActivePage();

      const result = await page.evaluate((code) => {
        const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
        return new AsyncFunction(`return (${code})`)();
      }, params.code);

      let text: string;
      if (result === undefined) {
        text = "undefined";
      } else if (result === null) {
        text = "null";
      } else if (typeof result === "object") {
        text = JSON.stringify(result, null, 2);
      } else {
        text = String(result);
      }

      return {
        content: [{ type: "text", text }],
        details: {},
      };
    },
  });

  // ------------------------------------------------------------------
  // browser_tabs — List open tabs grouped by window
  // ------------------------------------------------------------------
  pi.registerTool({
    name: "browser_tabs",
    label: "Browser Tabs",
    description: "List all open browser tabs, grouped by window.",
    promptSnippet: "List all browser tabs grouped by window",
    parameters: Type.Object({}),
    async execute() {
      const pages = await getAllPages();

      const windowMap: Record<number, Array<{ title: string; url: string }>> = {};

      for (const page of pages) {
        const session = await page.createCDPSession();
        try {
          const { windowId } = await session.send("Browser.getWindowForTarget") as { windowId: number };
          if (!windowMap[windowId]) windowMap[windowId] = [];
          windowMap[windowId].push({ title: await page.title(), url: page.url() });
        } finally {
          await session.detach();
        }
      }

      const lines: string[] = [];
      let winNum = 1;
      for (const [winId, tabs] of Object.entries(windowMap)) {
        lines.push(`Window ${winNum} (id: ${winId}):`);
        tabs.forEach((t, i) => {
          lines.push(`  ${i}: ${t.title}`);
          lines.push(`     ${t.url}`);
        });
        winNum++;
      }

      return {
        content: [{ type: "text", text: lines.join("\n") }],
        details: { windowMap },
      };
    },
  });

  // ------------------------------------------------------------------
  // browser_screenshot — Capture current viewport
  // ------------------------------------------------------------------
  pi.registerTool({
    name: "browser_screenshot",
    label: "Browser Screenshot",
    description: "Capture a screenshot of the current browser viewport. Returns the file path of the saved PNG.",
    promptSnippet: "Screenshot the current browser viewport",
    parameters: Type.Object({}),
    async execute() {
      const page = await getActivePage();

      const { tmpdir } = await import("node:os");
      const { join } = await import("node:path");

      const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
      const filepath = join(tmpdir(), `screenshot-${timestamp}.png`);

      await page.screenshot({ path: filepath });

      return {
        content: [{ type: "text", text: filepath }],
        details: { path: filepath },
      };
    },
  });

  // ------------------------------------------------------------------
  // browser_cookies — Show cookies for the active tab
  // ------------------------------------------------------------------
  pi.registerTool({
    name: "browser_cookies",
    label: "Browser Cookies",
    description: "Display all cookies for the current browser tab, including domain, path, httpOnly and secure flags.",
    promptSnippet: "Show cookies for the active browser tab",
    parameters: Type.Object({}),
    async execute() {
      const page = await getActivePage();
      const cookies = await page.cookies();

      const lines = cookies.map(
        (c) =>
          `${c.name}: ${c.value}\n  domain: ${c.domain}  path: ${c.path}  httpOnly: ${c.httpOnly}  secure: ${c.secure}`
      );

      return {
        content: [{ type: "text", text: lines.join("\n\n") || "(no cookies)" }],
        details: { count: cookies.length },
      };
    },
  });

  // ------------------------------------------------------------------
  // browser_pick — Interactive element picker
  // ------------------------------------------------------------------
  pi.registerTool({
    name: "browser_pick",
    label: "Browser Pick",
    description:
      "Launch an interactive element picker in the browser. The user clicks elements to select them (Cmd/Ctrl+Click for multiple, Enter to finish, Esc to cancel). Returns CSS-relevant info and HTML for the selected elements.",
    promptSnippet: "Let the user pick DOM elements interactively in the browser",
    parameters: Type.Object({
      message: Type.String({ description: "Prompt message shown to the user in the browser overlay" }),
    }),
    async execute(_toolCallId, params) {
      const page = await getActivePage();

      // Inject the pick() helper
      await page.evaluate(() => {
        if (!window["pick"]) {
          window["pick"] = async (message) => {
            if (!message) throw new Error("pick() requires a message parameter");
            return new Promise((resolve) => {
              const selections = [];
              const selectedElements = new Set();

              const overlay = document.createElement("div");
              overlay.style.cssText =
                "position:fixed;top:0;left:0;width:100%;height:100%;z-index:2147483647;pointer-events:none";

              const highlight = document.createElement("div");
              highlight.style.cssText =
                "position:absolute;border:2px solid #3b82f6;background:rgba(59,130,246,0.1);transition:all 0.1s";
              overlay.appendChild(highlight);

              const banner = document.createElement("div");
              banner.style.cssText =
                "position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#1f2937;color:white;padding:12px 24px;border-radius:8px;font:14px sans-serif;box-shadow:0 4px 12px rgba(0,0,0,0.3);pointer-events:auto;z-index:2147483647";

              const updateBanner = () => {
                banner.textContent = `${message} (${selections.length} selected, Cmd/Ctrl+click to add, Enter to finish, ESC to cancel)`;
              };
              updateBanner();
              document.body.append(banner, overlay);

              const cleanup = () => {
                document.removeEventListener("mousemove", onMove, true);
                document.removeEventListener("click", onClick, true);
                document.removeEventListener("keydown", onKey, true);
                overlay.remove();
                banner.remove();
                selectedElements.forEach((el) => { el.style.outline = ""; });
              };

              const onMove = (e) => {
                const el = document.elementFromPoint(e.clientX, e.clientY);
                if (!el || overlay.contains(el) || banner.contains(el)) return;
                const r = el.getBoundingClientRect();
                highlight.style.cssText = `position:absolute;border:2px solid #3b82f6;background:rgba(59,130,246,0.1);top:${r.top}px;left:${r.left}px;width:${r.width}px;height:${r.height}px`;
              };

              const buildElementInfo = (el) => ({
                tag: el.tagName.toLowerCase(),
                id: el.id || null,
                class: el.className || null,
                text: el.textContent?.trim().slice(0, 200) || null,
                html: el.outerHTML.slice(0, 500),
              });

              const onClick = (e) => {
                if (banner.contains(e.target)) return;
                e.preventDefault();
                e.stopPropagation();
                const el = document.elementFromPoint(e.clientX, e.clientY);
                if (!el || overlay.contains(el) || banner.contains(el)) return;

                if (e.metaKey || e.ctrlKey) {
                  if (!selectedElements.has(el)) {
                    selectedElements.add(el);
                    el.style.outline = "3px solid #10b981";
                    selections.push(buildElementInfo(el));
                    updateBanner();
                  }
                } else {
                  cleanup();
                  const info = buildElementInfo(el);
                  resolve(selections.length > 0 ? selections : info);
                }
              };

              const onKey = (e) => {
                if (e.key === "Escape") {
                  e.preventDefault();
                  cleanup();
                  resolve(null);
                } else if (e.key === "Enter" && selections.length > 0) {
                  e.preventDefault();
                  cleanup();
                  resolve(selections);
                }
              };

              document.addEventListener("mousemove", onMove, true);
              document.addEventListener("click", onClick, true);
              document.addEventListener("keydown", onKey, true);
            });
          };
        }
      });

      const result = await page.evaluate(
        (msg) => window["pick"](msg),
        params.message
      );

      if (result === null) {
        return {
          content: [{ type: "text", text: "Cancelled by user" }],
          details: { cancelled: true },
        };
      }

      const text = typeof result === "object"
        ? JSON.stringify(result, null, 2)
        : String(result);

      return {
        content: [{ type: "text", text }],
        details: { result },
      };
    },
  });
}
