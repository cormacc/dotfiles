# term

A [pi](https://github.com/nichochar/pi-coding-agent) extension that redirects
agent commands to a shared terminal split, giving both the agent and the user
full bidirectional visibility of the same terminal.

The extension **activates automatically** when it detects a supported
environment (tmux or sway). Use `--no-mirror` to disable it.

## Backends

| Backend  | Detection  | Status                     |
| -------- | ---------- | -------------------------- |
| **tmux** | `$TMUX`    | Preferred, actively developed |
| sway     | `$SWAYSOCK`| Less actively developed    |

**tmux** is the recommended backend. Run pi inside a tmux session and a split
pane is auto-created. The sway backend launches a foot terminal window and is
functional but receives less active development.

## Features

- **Shared terminal** — agent commands run in a visible split instead of a
  hidden subprocess. The user sees every command as it executes.
- **Bidirectional** — when the user types commands in the pane, the agent is
  notified and can respond to the output.
- **Process tabs** — long-running processes (dev servers, test watchers, REPLs)
  run in named tabs with optional auto-reporting of output changes.
- **Clean command display** — commands are sent to the shell directly (via
  `tmux send-keys` or a PTY relay). No wrapper scripts or markers visible.
- **Exit code tracking** — a shell hook captures exit codes after every command.
- **Instant detection** — event-driven signaling (tmux `wait-for` / named pipe
  FIFOs) with zero CPU while waiting.
- **Pane recovery** — auto-recovers if the user closes the pane, reuses
  existing panes across agent restarts.

## CLI

```bash
pi                # auto-activates in tmux or sway
pi --no-mirror    # disable shared terminal
```

## Slash Command

### `/term [subcommand]`

| Subcommand              | Description                         |
| ----------------------- | ----------------------------------- |
| _(none)_ / `toggle`     | Toggle the mirror pane visibility   |
| `focus`                 | Show (if hidden) and focus the pane |
| `prev`                  | Switch to previous tab              |
| `next`                  | Switch to next tab                  |
| `<index>`               | Switch to tab by 1-based index      |
| `kill <index\|name>`    | Kill a process tab by index or name |
| `run "<cmd>"`           | Run a command in the primary shell  |
| `spawn [title] "<cmd>"` | Spawn a new process tab             |

## Keybindings

Registered with `modal-editor` under `Space t` (terminal sub-menu):

| Key         | Action        | Command        |
| ----------- | ------------- | -------------- |
| `Space t t` | Toggle mirror | `/term toggle` |
| `Space t f` | Focus pane    | `/term focus`  |
| `Space t h` | Prev tab      | `/term prev`   |
| `Space t l` | Next tab      | `/term next`   |

## Tools

### `bash` (overrides built-in)

Executes a command in the shared terminal pane.

| Parameter | Type     | Description                       |
| --------- | -------- | --------------------------------- |
| `command` | `string` | Bash command to execute           |
| `timeout` | `number` | Timeout in seconds (default: 120) |

### `read_terminal`

Reads recent content from the shared terminal pane scrollback.

| Parameter | Type     | Description                        |
| --------- | -------- | ---------------------------------- |
| `lines`   | `number` | Lines of scrollback (default: 200) |

### `start_process`

Launch a long-running process in a named tab (e.g. dev server, test watcher,
REPL). Returns immediately.

| Parameter | Type     | Description                                                               |
| --------- | -------- | ------------------------------------------------------------------------- |
| `name`    | `string` | Short name for this process (e.g. "server", "tests")                      |
| `command` | `string` | Command to run                                                            |
| `mode`    | `string` | `"watch"` (auto-injects output changes, default) or `"quiet"` (on demand) |

### `send_input`

Send text input to a named running process (e.g. type into a REPL).

| Parameter | Type      | Description                           |
| --------- | --------- | ------------------------------------- |
| `name`    | `string`  | Process name                          |
| `text`    | `string`  | Text to send                          |
| `enter`   | `boolean` | Send Enter after text (default: true) |

### `read_process`

Read recent output from a named running process.

| Parameter | Type     | Description                        |
| --------- | -------- | ---------------------------------- |
| `name`    | `string` | Process name                       |
| `lines`   | `number` | Lines of scrollback (default: 200) |

### `stop_process`

Stop a named running process (sends Ctrl+C, then kills the tab).

| Parameter | Type     | Description  |
| --------- | -------- | ------------ |
| `name`    | `string` | Process name |

### `list_processes`

List all managed background processes and their status.

## Configuration

| Environment Variable | Description                                     |
| -------------------- | ----------------------------------------------- |
| `TMUX_MIRROR_TARGET` | Explicit tmux pane target (default: auto-split) |

## Requirements

**tmux backend:**

- Must run pi inside a tmux session.
- The shell in the split pane must be zsh or bash.

**sway backend:**

- Must run pi under sway (detected via `$SWAYSOCK`).
- `foot` terminal must be available.
- Python 3 must be available (for the PTY relay script).
- The shell must be zsh or bash.

## Dependencies

- `lib/pi-utils.ts` — `getExtensionName`, `suggestKeybindings`

---

## Architecture

### Shell Hook

On startup the extension sends hook code inline to the pane's shell. The hook:

1. Registers a `precmd` function (zsh) or `PROMPT_COMMAND` (bash).
2. On every prompt: stores `<seq> <exit_code>`.
   - **tmux:** in a tmux session env var (`PI_LAST_RC`) via `tmux set-environment`.
   - **sway:** in a temp file (`/tmp/pi-mirror-rc-<session-uuid>`).
3. Signals completion to wake any blocked waiters.
   - **tmux:** `tmux wait-for -S pi-prompt`.
   - **sway:** `echo > /tmp/pi-mirror-signal-<session-uuid> &` (writes to a
     named pipe/FIFO; backgrounded so the shell doesn't block if no reader is
     connected yet).

### Prompt Detection

After the hook is installed and the pane is cleared, the extension captures the
rendered prompt and detects:

- **`promptHeight`** — number of non-empty trailing lines (typically 2 for a
  two-line prompt with info bar + input line).
- **`promptSymbol`** — the first non-space token on the last line (e.g., `❯`,
  `$`, `#`). Used to identify prompt lines in captured output.

### Agent Commands (`bash` tool)

1. Capture the pane state (`before`).
2. Send the command text to the pane (via `tmux send-keys` or input FIFO).
3. Block until precmd fires (via `tmux wait-for` or signal FIFO).
4. Read exit code from the RC storage.
5. Capture the pane state (`after`).
6. Diff `before`/`after`, find the last prompt line with command text, collect
   output lines until the next prompt block.

### User Activity Detection

A background async loop blocks on the prompt signal. When signaled (and the
agent is idle):

1. Capture the pane and diff against the last snapshot.
2. Parse the diff using the same prompt-aware logic: find the last command,
   collect output, read exit code.
3. Format as `~/dir $ command\noutput\n[exit code: N]`.
4. Inject into the conversation via `pi.sendMessage`.

### Pane Recovery

On every `bash` call, `ensurePane()` checks if the target pane is still alive.
If the pane was closed:

1. Reset all state (paneReady, hookInstalled, RC files).
2. Wait 500ms for terminal resize to settle.
3. Create a new split pane.
4. Wait for a shell to start (polls `pane_current_command` for up to 10s).
5. Reinstall the hook.

The pane ID is saved persistently (tmux session env or sway window ID file) so
it can be reused across agent restarts without creating duplicate panes.

### Backend architecture

**tmux:**

```
┌─────────────────────┐  ┌──────────────────────┐
│  pi (agent pane)    │  │  shared pane (%N)     │
│                     │  │                       │
│  term ext            │──│  zsh/bash + hook      │
│  ├─ bash tool       │  │  ├─ precmd writes RC  │
│  ├─ read_terminal   │  │  └─ wait-for -S       │
│  └─ activity loop   │  │                       │
└─────────────────────┘  └──────────────────────┘
         │                          │
         └── tmux wait-for ─────────┘  (event-driven, zero CPU)
```

**sway:**

```
┌─────────────────────┐  ┌──────────────────────┐
│  pi (agent window)  │  │  foot terminal (id:N) │
│                     │  │                       │
│  term ext            │──│  sway-relay.py + pty  │
│  ├─ bash tool       │  │  ├─ zsh/bash + hook   │
│  ├─ read_terminal   │  │  ├─ precmd writes RC  │
│  └─ activity loop   │  │  └─ echo > FIFO &     │
└─────────────────────┘  └──────────────────────┘
         │                          │
         ├── input FIFO ────────────┘  (text injection via relay)
         ├── output log file            (capture via log)
         └── cat signal FIFO (blocks)   (zero CPU, like tmux wait-for)
```

### State Storage

**tmux** — all state in tmux session environment variables (no temp files):

| Variable         | Purpose                                    |
| ---------------- | ------------------------------------------ |
| `PI_MIRROR_PANE` | Pane ID for cross-restart reuse            |
| `PI_LAST_RC`     | `<seq> <exit_code>` written by precmd hook |

**sway** — state in temp files (UUID-scoped per session):

| File                                         | Purpose                                    |
| -------------------------------------------- | ------------------------------------------ |
| `/tmp/pi-mirror-log-<uuid>`                  | Output log from PTY relay                  |
| `/tmp/pi-mirror-input-<uuid>`                | Input FIFO for text injection              |
| `/tmp/pi-mirror-rc-<uuid>`                   | `<seq> <exit_code>` written by precmd hook |
| `/tmp/pi-mirror-signal-<uuid>`               | Named pipe (FIFO) for activity signals     |
| `/tmp/pi-mirror-agent-signal-<uuid>`         | Named pipe (FIFO) for agent signals        |
| `/tmp/pi-mirror-ready-<uuid>`                | Named pipe (FIFO) for ready signals        |

### Design Decisions

**Why event-driven signaling instead of polling?**
The original implementation polled every 300ms. This was replaced with blocking
mechanisms (`tmux wait-for` / named pipe FIFOs) that use zero CPU while waiting
and provide instant detection.

**Why `capture-pane -J`?**
Without `-J`, tmux wraps long lines at the pane width, producing multiple
physical lines per logical line. `-J` joins wrapped lines back into logical
lines, preventing duplicate prompt detection.

**Why detect prompt from the pane instead of reading PS1?**
`PS1`/`PROMPT` contain unexpanded escape sequences that are useless for matching
rendered output. The extension captures the pane after `clear` and reads the
actual rendered prompt.

**Why save the pane ID in tmux session environment?**
Pane titles are overwritten by shell prompt themes. A tmux session environment
variable is scoped to the session, survives agent restarts, and doesn't leave
temp files.

**Why wrap multi-line commands in `{ ... }`?**
When newlines are sent via `send-keys`, each triggers Enter and `precmd` fires
after each line. Wrapping in `{ ... }` creates a compound command so `precmd`
fires only once at the end.

**Why report only the last command in user activity?**
The exit code in the RC file only corresponds to the last command. Reporting
all commands in a diff would show stale exit codes for earlier ones.
