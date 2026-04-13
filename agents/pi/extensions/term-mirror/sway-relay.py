#!/usr/bin/env python3
"""
PTY relay for sway mirror backend.

Runs inside foot, creates a pty for the shell, and:
- Relays user keyboard input to the shell
- Accepts injected input from a FIFO (for the agent)
- Logs all shell output to a file (for capture)

Usage: sway-relay.py <input_fifo> <output_log> [shell]
"""
import os
import sys
import pty
import select
import signal
import errno

CHUNK = 4096

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input_fifo> <output_log> [shell]", file=sys.stderr)
        sys.exit(1)

    input_fifo = sys.argv[1]
    output_log = sys.argv[2]
    shell = sys.argv[3] if len(sys.argv) > 3 else os.environ.get("SHELL", "/bin/sh")

    # Fork a pty with the shell
    child_pid, master_fd = pty.fork()

    if child_pid == 0:
        # Child: exec the shell
        os.environ["PAGER"] = "cat"
        os.environ["GIT_PAGER"] = "cat"
        os.execvp(shell, [shell])

    # Parent: relay between stdin/fifo and the pty master, log output

    # Open output log for append
    log_fd = os.open(output_log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)

    # We open the FIFO in non-blocking read mode. We re-open it each time
    # it gets EOF (writer closed) to keep listening for new writers.
    fifo_fd = -1

    def open_fifo():
        nonlocal fifo_fd
        if fifo_fd >= 0:
            try:
                os.close(fifo_fd)
            except OSError:
                pass
        try:
            fifo_fd = os.open(input_fifo, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            fifo_fd = -1

    open_fifo()

    stdin_fd = sys.stdin.fileno()
    stdout_fd = sys.stdout.fileno()

    # Forward SIGWINCH to the child
    def handle_winch(signum, frame):
        import struct
        import fcntl
        import termios
        try:
            winsize = fcntl.ioctl(stdin_fd, termios.TIOCGWINSZ, b'\x00' * 8)
            fcntl.ioctl(master_fd, termios.TIOCSWINSZ, winsize)
            os.kill(child_pid, signal.SIGWINCH)
        except (OSError, IOError):
            pass

    signal.signal(signal.SIGWINCH, handle_winch)

    # Put terminal in raw mode
    import tty
    import termios
    old_settings = termios.tcgetattr(stdin_fd)
    try:
        tty.setraw(stdin_fd)

        # Propagate initial terminal size
        handle_winch(0, None)

        while True:
            fds = [stdin_fd, master_fd]
            if fifo_fd >= 0:
                fds.append(fifo_fd)

            try:
                readable, _, _ = select.select(fds, [], [], 1.0)
            except (select.error, OSError) as e:
                if hasattr(e, 'errno') and e.errno == errno.EINTR:
                    continue
                if isinstance(e, OSError) and e.errno == errno.EINTR:
                    continue
                break

            if stdin_fd in readable:
                try:
                    data = os.read(stdin_fd, CHUNK)
                except OSError:
                    break
                if not data:
                    break
                os.write(master_fd, data)

            if master_fd in readable:
                try:
                    data = os.read(master_fd, CHUNK)
                except OSError:
                    break
                if not data:
                    break
                # Write to both terminal and log
                os.write(stdout_fd, data)
                try:
                    os.write(log_fd, data)
                except OSError:
                    pass

            if fifo_fd >= 0 and fifo_fd in readable:
                try:
                    data = os.read(fifo_fd, CHUNK)
                except OSError:
                    data = b""
                if data:
                    os.write(master_fd, data)
                else:
                    # EOF on FIFO — writer closed, reopen for next writer
                    open_fifo()

    except Exception:
        pass
    finally:
        termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_settings)
        os.close(log_fd)
        if fifo_fd >= 0:
            os.close(fifo_fd)
        try:
            os.kill(child_pid, signal.SIGTERM)
            os.waitpid(child_pid, 0)
        except (OSError, ChildProcessError):
            pass

if __name__ == "__main__":
    main()
