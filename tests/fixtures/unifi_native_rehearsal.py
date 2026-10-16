"""Synthetic-only native UniFi rehearsal; no credentials or controller calls."""
import importlib
import json
import math
import os
from pathlib import Path
import signal
import socket
import stat
import subprocess
import sys
import time

COLLECTOR_LIB = Path("@COLLECTOR_LIB@")
sys.path.insert(0, str(COLLECTOR_LIB))
unifi_enroll = importlib.import_module("unifi_enroll")

HOSTS = Path("@HOSTS@")
MOUNTED_HOSTS = Path("/etc/hosts")
SYSTEMCTL = "@SYSTEMCTL@"
TRUE = "@TRUE@"
STATE = Path("/var/lib/homelab-unifi-rehearsal-01")
NORMAL = "homelab-unifi-rehearsal-01.service"
NEGATIVE = "homelab-unifi-deadline-rehearsal-01.service"
CANDIDATE = {
    "version": 1, "enabled": True,
    "base_url": "https://unifi-rehearsal.invalid/proxy/network/integration",
    "site_id": "11111111-1111-4111-8111-111111111111",
    "expected_devices": {"synthetic": "22222222-2222-4222-8222-222222222222"},
    "api_key_header": "X-API-Key", "timeout_seconds": 3.0,
    "page_limit": 50, "ca_file": None,
}


def require(condition):
    if not condition:
        raise RuntimeError("synthetic rehearsal check failed")


def state_directory():
    descriptor = unifi_enroll._open_private_directory(STATE)
    if os.fstat(descriptor).st_gid != os.getegid():
        os.close(descriptor)
        raise RuntimeError("synthetic directory group is unsafe")
    return descriptor


def private_json(name):
    directory = state_directory()
    descriptor = -1
    try:
        descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        metadata = os.fstat(descriptor)
        require(stat.S_ISREG(metadata.st_mode))
        require(metadata.st_uid == os.geteuid() and metadata.st_gid == os.getegid())
        require(stat.S_IMODE(metadata.st_mode) == 0o600)
        content = os.read(descriptor, 8193)
        require(len(content) <= 8192)
        return json.loads(content)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.close(directory)


def network_is_private():
    return (
        os.stat("/proc/self/ns/net").st_ino != os.stat("/proc/1/ns/net").st_ino
        and [name for _, name in socket.if_nameindex()] == ["lo"]
    )


def probe():
    directory = state_directory()
    try:
        require(os.listdir(directory) == [])
    finally:
        os.close(directory)
    require(network_is_private())
    require(MOUNTED_HOSTS.read_bytes() == HOSTS.read_bytes())
    answers = socket.getaddrinfo("unifi-rehearsal.invalid", 443, socket.AF_INET, socket.SOCK_STREAM)
    require(bool(answers) and {answer[4][0] for answer in answers} == {"192.0.2.23"})
    with unifi_enroll._open_private_terminal() as terminal:
        require(terminal.isatty())
        terminal.write("Synthetic rehearsal only — type rehearsal-ok: ")
        terminal.flush()
        require(terminal.readline(129) == "rehearsal-ok\n")
    unifi_enroll.write_candidate(STATE / "candidate.json", CANDIDATE)
    require(private_json("candidate.json") == CANDIDATE)


def cleanup():
    require(cgroup_empty(NORMAL) and cgroup_empty(NEGATIVE))
    if not os.path.lexists(STATE):
        return
    directory = state_directory()
    try:
        names = set(os.listdir(directory))
        require(names <= {"candidate.json", "pids.json"})
        if "candidate.json" in names:
            require(private_json("candidate.json") == CANDIDATE)
        if "pids.json" in names:
            validate_record(private_json("pids.json"))
        metadata = os.fstat(directory)
        require(STATE.lstat().st_ino == metadata.st_ino)
        for name in sorted(names):
            os.unlink(name, dir_fd=directory)
    finally:
        os.close(directory)
    STATE.rmdir()
    require(not os.path.lexists(STATE))


def validate_record(record):
    require(isinstance(record, dict) and set(record) == {"pids", "started"})
    require(type(record["started"]) in (float, int) and math.isfinite(record["started"]))
    require(isinstance(record["pids"], list) and len(record["pids"]) == 2)
    for entry in record["pids"]:
        require(isinstance(entry, list) and len(entry) == 2)
        require(type(entry[0]) is int and 1 < entry[0] < 2**31)
        require(type(entry[1]) is int and entry[1] >= 0)
    require(record["pids"][0][0] != record["pids"][1][0])


def process_start(pid):
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        return int(fields[19]), fields[0]
    except FileNotFoundError:
        return None


def cgroup_empty(unit):
    path = Path("/sys/fs/cgroup/system.slice") / unit / "cgroup.procs"
    return not path.exists() or not path.read_text().strip()


def unit_properties(unit):
    result = subprocess.run(
        [SYSTEMCTL, "show", unit, "--no-pager", "-p", "Result", "-p", "ExecMainStatus",
         "-p", "TimeoutStartUSec", "-p", "TimeoutStopUSec", "-p", "KillMode",
         "-p", "SendSIGKILL", "-p", "KillSignal", "-p", "FinalKillSignal"],
        capture_output=True, text=True, timeout=5, check=True,
    )
    return dict(line.split("=", 1) for line in result.stdout.splitlines())


def verify_negative():
    require(private_json("candidate.json") == CANDIDATE)
    record = private_json("pids.json")
    validate_record(record)
    expected = {"Result": "timeout", "ExecMainStatus": "9", "TimeoutStartUSec": "2s",
                "TimeoutStopUSec": "1s", "KillMode": "control-group", "SendSIGKILL": "yes",
                "KillSignal": "15", "FinalKillSignal": "9"}
    require(unit_properties(NEGATIVE) == expected)
    require(1 <= time.monotonic() - record["started"] <= 20)
    for pid, ticks in record["pids"]:
        current = process_start(pid)
        require(current is None or current[0] != ticks or current[1] == "Z")
    require(cgroup_empty(NORMAL) and cgroup_empty(NEGATIVE))


def hang():
    require(private_json("candidate.json") == CANDIDATE)
    directory = state_directory()
    try:
        require(set(os.listdir(directory)) == {"candidate.json"})
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        child = os.fork()
        if child == 0:
            os.close(directory)
            while True:
                signal.pause()
        parent_start = process_start(os.getpid())
        child_start = process_start(child)
        if parent_start is None or child_start is None:
            raise RuntimeError("synthetic process identity unavailable")
        record = {"pids": [[os.getpid(), parent_start[0]],
                            [child, child_start[0]]], "started": time.monotonic()}
        validate_record(record)
        descriptor = os.open("pids.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=directory)
        with os.fdopen(descriptor, "w") as output:
            json.dump(record, output)
            output.flush()
            os.fsync(output.fileno())
    finally:
        os.close(directory)
    while True:
        signal.pause()


def preflight():
    for path in [Path("/"), Path("/var"), Path("/var/lib")]:
        metadata = path.lstat()
        require(stat.S_ISDIR(metadata.st_mode) and metadata.st_uid == 0)
        require(not stat.S_IMODE(metadata.st_mode) & 0o022)
    require(not os.path.lexists(STATE))
    require(Path("/run/nscd/socket").is_socket())
    require(Path("/sys/fs/cgroup/cgroup.controllers").is_file())
    for unit in [NORMAL, NEGATIVE]:
        require(not os.path.lexists(Path("/run/systemd/transient") / unit))
        result = subprocess.run([SYSTEMCTL, "show", unit, "-p", "LoadState", "--value"],
                                capture_output=True, text=True, timeout=5)
        require(result.stdout.strip() == "not-found")


def ticket_closed():
    result = subprocess.run(
        ["/run/wrappers/bin/sudo", "-n", "--", TRUE], stdin=subprocess.DEVNULL,
        capture_output=True, text=True, timeout=3,
        env={**os.environ, "LC_ALL": "C"},
    )
    require(result.returncode == 1 and result.stdout == ""
            and result.stderr == "sudo: a password is required\n")


def main():
    try:
        if sys.argv[1:] == ["ticket-closed"]:
            require(os.geteuid() != 0)
            ticket_closed()
            print("UNIFI_REHEARSAL_TICKET_CLOSED", flush=True)
            return 0
        require(os.geteuid() == os.getegid() == 0)
        module_file = unifi_enroll.__file__
        if module_file is None:
            raise RuntimeError("collector module origin missing")
        require(Path(module_file).parent == COLLECTOR_LIB)
        operations = {"preflight": preflight, "probe": probe, "hang": hang,
                      "verify": verify_negative, "cleanup": cleanup}
        require(len(sys.argv) == 2 and sys.argv[1] in operations)
        operations[sys.argv[1]]()
    except BaseException:
        print("UNIFI_REHEARSAL_STEP_FAILED", flush=True)
        return 2
    print("UNIFI_REHEARSAL_STEP_PASS", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
