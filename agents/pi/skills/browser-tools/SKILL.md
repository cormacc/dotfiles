---
name: browser-tools
description: Interactive browser automation via Chrome DevTools Protocol. Use when you need to interact with web pages, test frontends, or when user interaction with a visible browser is required.
---

# Browser Tools

Browser automation is provided by the `browser_nav`, `browser_eval`, `browser_tabs`,
`browser_screenshot`, `browser_pick`, and `browser_cookies` tools. These connect to
Chromium/Chrome on `localhost:9222` — the browser must be running with
`--remote-debugging-port=9222`.

## Workflow

1. **Investigate first** — use `browser_eval` to understand the page before acting:
   ```javascript
   (function() {
     return {
       title: document.title,
       forms: document.forms.length,
       buttons: document.querySelectorAll('button').length,
       inputs: document.querySelectorAll('input').length,
       mainContent: document.body.innerHTML.slice(0, 3000)
     };
   })()
   ```

2. **Target specific elements** based on what you find, then interact.

3. **Use `browser_pick`** when the user wants to select elements visually, or when
   the page structure is complex/ambiguous.

## Efficiency Guide

### DOM Inspection Over Screenshots

**Don't** take screenshots to see page state. **Do** parse the DOM directly:

```javascript
// Find interactive elements
Array.from(document.querySelectorAll('button, input, [role="button"]')).map(e => ({
  id: e.id, text: e.textContent.trim(), class: e.className
}))
```

### Use IIFEs for Complex Scripts

Wrap multi-statement code in an IIFE for `browser_eval`:

```javascript
(function() {
  const data = document.querySelector('#target').textContent;
  document.querySelector('#submit').click();
  return JSON.stringify({ data });
})()
```

### Batch Interactions

**Don't** make separate `browser_eval` calls for each click. **Do** batch them:

```javascript
(function() {
  ["btn1", "btn2", "btn3"].forEach(id => document.getElementById(id).click());
  return "Done";
})()
```

### Waiting for Updates

If the DOM updates after actions, make a second `browser_eval` call after a brief
pause rather than trying to add delays in JS. The persistent connection makes
sequential tool calls cheap.
