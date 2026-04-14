# bb-tasks

A [pi-coding-agent](https://github.com/nichochar/pi-coding-agent) extension
that integrates [Babashka](https://babashka.org/) task running into pi.

## Features

- **Auto-detection** — activates only when `bb.edn` exists in the project root.
- **Task discovery** — runs `bb tasks` on startup to enumerate available tasks.
- **`/bb` command** — slash command with auto-completion for all discovered tasks.
- **Watch process tabs** — tasks whose name starts with `watch` are launched in
  a dedicated process tab (via `start_process`) when the `term-mirror` extension
  is available. Other tasks run in the default shell.

## Usage

```
/bb              — list all available tasks
/bb clean        — run the "clean" task in the shell
/bb watch-tests  — run in a process tab (term-mirror) or shell (fallback)
```

## Requirements

- `bb` (babashka) must be on `$PATH`.
- A `bb.edn` file must exist in the project root.
- For watch process tabs: the `term-mirror` extension must be loaded.
