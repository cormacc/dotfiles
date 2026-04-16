# term

A [pi-coding-agent](https://github.com/nichochar/pi-coding-agent) extension
that redirects all agent commands to a shared terminal split, giving both the
agent and the user full bidirectional visibility of the same terminal.

## Usage

```bash
pi --mirror
```

The extension is auto-discovered from `~/.pi/agent/extensions/` but only
activates when the `--mirror` flag is passed.

Supports two backends:

- **tmux** — detected via `$TMUX`, uses tmux split panes and `tmux wait-for`
  for instant signaling.
- **sway** — detected via `$SWAYSOCK`, launches a foot terminal split via
  swaymsg, uses a PTY relay for I/O and named pipes (FIFOs) for instant
  signaling.

## Features

- **Shared terminal** — agent commands run in a visible terminal split instead
  of a hidden subprocess. The user sees every command as it executes.
- **Bidirectional** — when the user types commands in the pane, the agent is
  notified instantly and can respond to the output.
- **Clean command display** — the actual command text is sent to the shell
  directly (via `tmux send-keys` or a PTY relay). No wrapper scripts, markers,
  or temp file execution visible in the terminal.
- **Exit code tracking** — a shell hook (`precmd` for zsh, `PROMPT_COMMAND` for
  bash) atomically writes a sequence number + exit code to a temp file after
  every command.
- **Instant detection** — uses `tmux wait-for` (tmux) or named pipe FIFOs
  (sway) for zero-CPU event-driven notifications. Both command completion
  (agent) and user activity detection block with no busy loops.
- **Prompt-aware output parsing** — auto-detects the user's prompt symbol and
  height from the pane after `clear`. Uses this to cleanly extract command
  output, stripping prompt lines and RPROMPT timestamps. The same parsing logic
  is used for both agent commands and user activity.
- **Pane lifecycle management** — auto-creates a split pane on startup.
  Recovers if the user closes the pane. Reuses existing panes across agent
  restarts via saved state (tmux session env or sway window ID).
- **Multi-line commands** — commands with newlines are wrapped in `{ ... }` to
  form a single compound command. This ensures `precmd` fires only once (after
  all commands complete), not after each line. Works with heredocs, quoted
  strings, and nested constructs.
- **Smart `cd`** — only prepends `cd <dir> &&` when the pane's working directory
  differs from the agent's.
- **Pager disabled** — sets `PAGER=cat GIT_PAGER=cat` so commands like
  `git log` don't block the terminal.

## How It Works

### Architecture

**tmux backend:**

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

**sway backend:**

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

### Shell Hook

On startup the extension sends the hook code inline to the pane's shell. The
hook:

1. Registers a `precmd` function (zsh) or `PROMPT_COMMAND` (bash).
2. On every prompt: stores `<seq> <exit_code>`.
   - **tmux:** in a tmux session env var (`PI_LAST_RC`) via `tmux set-environment`.
   - **sway:** in a temp file (`/tmp/pi-mirror-rc-<session-uuid>`).
3. Signals completion to wake any blocked waiters.
   - **tmux:** `tmux wait-for -S pi-prompt`.
   - **sway:** `echo > /tmp/pi-mirror-signal-<session-uuid> &` (writes to a
     named pipe/FIFO; backgrounded so the shell doesn't block if no reader is
     connected yet).

This provides instant, invisible notification that a command has completed,
along with its exit code. Both mechanisms use zero CPU while waiting.

### Prompt Detection

After the hook is installed and the pane is cleared, the extension captures the
rendered prompt and detects:

- **`promptHeight`** — number of non-empty trailing lines (typically 2 for a
  two-line prompt with info bar + input line).
- **`promptSymbol`** — the first non-space token on the last line (e.g., `❯`,
  `$`, `#`). Used to identify prompt lines in captured output.

These are used by both `extractOutput` (agent commands) and `formatActivity`
(user commands) to strip prompt decoration and extract clean command output.

### Agent Commands (`bash` tool)

1. Capture the pane state (`before`).
2. Send the command text to the pane (via `tmux send-keys` or input FIFO).
3. Block until precmd fires (via `tmux wait-for` or signal FIFO).
4. Read exit code from the RC storage.
5. Capture the pane state (`after`).
6. Diff `before`/`after`, find the last prompt line with command text, collect
   output lines until the next prompt block.

### User Activity Detection

A background async loop blocks on the prompt signal (via `tmux wait-for` or
signal FIFO). When signaled (and the agent is idle):

1. Capture the pane and diff against the last snapshot.
2. Parse the diff using the same prompt-aware logic: find the last command,
   collect output, read exit code.
3. Format as `~/dir $ command\noutput\n[exit code: N]`.
4. Inject into the conversation via `pi.sendMessage` with `triggerTurn: true`.

### Pane Recovery

On every `bash` call, `ensurePane()` checks if the target pane is still alive
(via `tmux list-panes` or the sway tree). If the pane was closed:

1. Reset all state (paneReady, hookInstalled, RC files).
2. Wait 500ms for terminal resize to settle.
3. Create a new split pane.
4. Wait for a shell to start (polls `pane_current_command` for up to 10s).
5. Reinstall the hook.

The pane ID is saved persistently (tmux session env or sway window ID file) so
it can be reused across agent restarts without creating duplicate panes.

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

## Suggested Keybindings

Registered with `modal-editor` under `Space t` (terminal sub-menu):

| Key         | Action        | Command        |
| ----------- | ------------- | -------------- |
| `Space t t` | Toggle mirror | `/term toggle` |
| `Space t f` | Focus pane    | `/term focus`  |
| `Space t h` | Prev tab      | `/term prev`   |
| `Space t l` | Next tab      | `/term next`   |

## CLI Flag

| Flag          | Description                               |
| ------------- | ----------------------------------------- |
| `--no-mirror` | Disable shared terminal split (tmux/sway) |

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

## State Storage

**tmux backend** — all state in tmux session environment variables (no temp files):

| Variable         | Purpose                                    |
| ---------------- | ------------------------------------------ |
| `PI_MIRROR_PANE` | Pane ID for cross-restart reuse            |
| `PI_LAST_RC`     | `<seq> <exit_code>` written by precmd hook |

**sway backend** — state in temp files (UUID-scoped per session for multi-agent safety):

| File                                         | Purpose                                    |
| -------------------------------------------- | ------------------------------------------ |
| `/tmp/pi-mirror-log-<session-uuid>`          | Output log from PTY relay                  |
| `/tmp/pi-mirror-input-<session-uuid>`        | Input FIFO for text injection              |
| `/tmp/pi-mirror-rc-<session-uuid>`           | `<seq> <exit_code>` written by precmd hook |
| `/tmp/pi-mirror-signal-<session-uuid>`       | Named pipe (FIFO) for activity signals     |
| `/tmp/pi-mirror-agent-signal-<session-uuid>` | Named pipe (FIFO) for agent signals        |
| `/tmp/pi-mirror-ready-<session-uuid>`        | Named pipe (FIFO) for ready signals        |

### Diff Viewer Pane

A read-only pane below the command pane shows `git diff --color=always` output.
It auto-refreshes after each agent bash command via `tmux wait-for` signaling.
The user can scroll with tmux copy mode (`prefix + [`).

Debug log: `/tmp/pi-mirror-debug.log` (activity loop, temporary).

## Testing

This line was added to test the diff viewer pane.
And this is a second change to see the diff grow.
Third change — testing the less-based diff viewer with native scrolling.
Fourth change — now using direct command injection instead of a loop.
Fifth change — verifying the diff viewer updates after Edit tool changes.
Sixth change — testing with multiple file edits in one turn.
Seventh change — another round.

## Implementation Notes

### Why event-driven signaling instead of polling?

The original implementation polled the RC file every 300ms to detect command
completion, and used a 3-second `setInterval` for user activity. This was
replaced with blocking mechanisms that use zero CPU while waiting:

- **tmux:** `tmux wait-for` blocks until signaled by `tmux wait-for -S`.
- **sway:** `cat <fifo>` blocks on a named pipe (FIFO) until the precmd hook
  writes to it via `echo > fifo &`.

Both the agent command wait loop and the user activity loop use this mechanism.
Detection is instant rather than delayed by a polling interval.

### Why `capture-pane -J`?

Without `-J`, tmux wraps long lines at the pane width, producing multiple
physical lines per logical line. The user's prompt (with RPROMPT timestamp
padding) would appear as two lines in the capture, causing the parser to see
duplicate commands. `-J` joins wrapped lines back into logical lines.

### Why detect prompt from the pane instead of reading PS1?

`PS1`/`PROMPT` contain unexpanded escape sequences (`%~`, `%F{blue}`, etc.)
that are useless for matching rendered output. Instead, the extension captures
the pane after `clear` and reads the actual rendered prompt. A 500ms delay
after the `wait-for` signal ensures the prompt has finished drawing (since
`precmd` fires before the prompt is rendered).

### Why save the pane ID in tmux session environment?

Originally the pane was tagged via `tmux select-pane -T "pi-mirror"` and found
by title. But the user's shell prompt theme overwrites the pane title on every
prompt redraw, so the tag was lost. A tmux session environment variable
(`PI_MIRROR_PANE`) is scoped to the session, survives agent restarts, and
doesn't leave temp files on the filesystem.

### Why wrap multi-line commands in `{ ... }`?

When multiple commands separated by newlines are sent via `send-keys`, each
newline triggers Enter. The shell executes each command separately, and
`precmd` fires after each one. The agent's `wait-for` catches the first signal
and thinks the entire command is done, while remaining commands are still in the
shell's input buffer. Wrapping in `{ ... }` creates a compound command — the
shell enters continuation mode on `{`, executes all commands when `}` is
reached, and `precmd` fires only once at the end.

An earlier approach used backslash (`\`) continuation, but this corrupted
multi-line string content (e.g., commit messages with newlines) because the `\`
appeared literally inside quoted strings.

### Why report only the last command in user activity?

The diff between snapshots can contain multiple commands if the user typed
several between checks. The exit code in the RC file only corresponds to the
last command. Reporting all commands would show stale exit codes for earlier
ones. Additionally, zsh autosuggestions or history recall can cause the same
command text to appear on the new prompt line, creating false duplicates.
