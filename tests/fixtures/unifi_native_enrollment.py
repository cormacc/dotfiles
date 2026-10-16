"""Fixed-path private enrollment payload; never install or activate a candidate."""
import grp
import importlib
import stat
import socket
import ssl
import subprocess
import os
from pathlib import Path
import sys
import urllib.error

COLLECTOR_LIB = Path("@COLLECTOR_LIB@")
sys.path.insert(0, str(COLLECTOR_LIB))
unifi_enroll = importlib.import_module("unifi_enroll")
CONFIG = Path('/var/lib/homelab-unifi/config.json')
CA = Path('/var/lib/homelab-unifi/controller-ca.pem')
STATE = Path('/var/lib/homelab-unifi-enroll-01')
CANDIDATE = STATE / 'config.candidate.json'
CREDENTIAL_DIRECTORY = '/run/credentials/homelab-unifi-enroll-01.service'


def require(condition):
    if not condition:
        raise RuntimeError('private enrollment check failed')


def failure_kind(error):
    """Classify exception types/HTTP numbers, never messages or response data."""
    pending, seen = [error], set()
    fallback = 'INTERNAL'
    for _ in range(32):
        if not pending:
            break
        current = pending.pop()
        if not isinstance(current, BaseException) or id(current) in seen:
            continue
        seen.add(id(current))
        if isinstance(current, urllib.error.HTTPError):
            return f'HTTP_{current.code}' if type(current.code) is int and 100 <= current.code <= 599 else 'HTTP'
        if isinstance(current, ssl.SSLCertVerificationError):
            return 'TLS_CERTIFICATE'
        if isinstance(current, ssl.SSLError):
            return 'TLS_PROTOCOL'
        if isinstance(current, TimeoutError):
            return 'TIMEOUT'
        if isinstance(current, socket.gaierror):
            return 'DNS'
        if isinstance(current, ConnectionRefusedError):
            return 'CONNECTION_REFUSED'
        if isinstance(current, ConnectionResetError):
            return 'CONNECTION_RESET'
        if isinstance(current, unifi_enroll.unifi_snapshot.ConfigError):
            return 'CONFIG'
        if isinstance(current, unifi_enroll.unifi_snapshot.CredentialError):
            return 'CREDENTIAL'
        if isinstance(current, unifi_enroll.unifi_snapshot.CollectorError):
            fallback = 'API_RESPONSE'
        pending.extend([current.__context__, current.__cause__])
        if isinstance(current, urllib.error.URLError):
            pending.append(current.reason)
    return fallback


SYSTEMCTL = '@SYSTEMCTL@'
TRUE = '@TRUE@'
LOGGER = '@LOGGER@'
ENROLLMENT_STAGE = 'prepare'
UNIT = 'homelab-unifi-enroll-01.service'
CGROUP = Path('/sys/fs/cgroup/system.slice') / UNIT
TRANSIENT = Path('/run/systemd/transient') / UNIT


def metadata(path, mode, gid, *, directory=False):
    # lstat only: not even the key is opened. All ancestors are checked too.
    for parent in reversed(path.parents):
        info = parent.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == 0)
        require(not stat.S_IMODE(info.st_mode) & 0o022)
    info = path.lstat()
    require((stat.S_ISDIR if directory else stat.S_ISREG)(info.st_mode))
    require(info.st_uid == 0 and info.st_gid == gid)
    require(stat.S_IMODE(info.st_mode) == mode)


def properties(unit, names):
    result = subprocess.run([SYSTEMCTL, 'show', unit, '--no-pager',
                             *[arg for name in names for arg in ('-p', name)]],
                            capture_output=True, text=True, timeout=5)
    require(result.returncode in (0, 4))
    values = dict(line.split('=', 1) for line in result.stdout.splitlines())
    require(set(values) == set(names))
    return values


def quiescent():
    require(not os.path.lexists(TRANSIENT) and not os.path.lexists(CGROUP))
    require(properties(UNIT, ['LoadState']) == {'LoadState': 'not-found'})
    require(properties('homelab-unifi-watch.service', ['ActiveState']) == {'ActiveState': 'inactive'})
    timer = properties('homelab-unifi-watch.timer',
                       ['ActiveState', 'NextElapseUSecRealtime', 'NextElapseUSecMonotonic'])
    require(timer['ActiveState'] == 'inactive')
    require(timer['NextElapseUSecRealtime'] in ('', 'n/a', '0', 'infinity'))
    require(timer['NextElapseUSecMonotonic'] in ('', 'n/a', '0', 'infinity'))


def preflight():
    require(not os.path.lexists(STATE))
    quiescent()
    group = grp.getgrnam('homelab-health').gr_gid
    metadata(CONFIG.parent, 0o750, group, directory=True)
    for path in (CONFIG, CONFIG.parent / 'hosts', CA):
        metadata(path, 0o440, group)
    metadata(CONFIG.parent / 'api-key', 0o400, 0)
    require(stat.S_ISSOCK(Path('/run/nscd/socket').lstat().st_mode))
    require(Path('/sys/fs/cgroup/cgroup.controllers').is_file())


def state_directory():
    descriptor = unifi_enroll._open_private_directory(STATE)
    try:
        require(os.fstat(descriptor).st_gid == os.getegid())
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def verify_candidate():
    directory = state_directory()
    descriptor = -1
    try:
        descriptor = os.open(CANDIDATE.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                             dir_fd=directory)
        info = os.fstat(descriptor)
        require(stat.S_ISREG(info.st_mode))
        require(info.st_uid == os.geteuid() and info.st_gid == os.getegid())
        require(stat.S_IMODE(info.st_mode) == 0o600 and info.st_nlink == 1)
        with unifi_enroll._open_private_terminal():
            config = unifi_enroll.unifi_snapshot.load_config(CANDIDATE)
            require(config['enabled'] is True and bool(config['expected_devices']))
            require(config['ca_file'] == str(CA))
        current = os.stat(CANDIDATE.name, dir_fd=directory, follow_symlinks=False)
        require((current.st_dev, current.st_ino) == (info.st_dev, info.st_ino))
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.close(directory)


def cleanup():
    quiescent()
    if not os.path.lexists(STATE):
        return
    directory = state_directory()
    try:
        names = set(os.listdir(directory))
        require(names <= {CANDIDATE.name})
        if names:
            verify_candidate()  # Keep it, including on any subsequent failure.
            return True
        info = os.fstat(directory)
        current = STATE.lstat()
        require((info.st_dev, info.st_ino) == (current.st_dev, current.st_ino))
        STATE.rmdir()  # Empty only; never recursively remove anything.
    finally:
        os.close(directory)


def finish():
    require(cleanup())


def enroll():
    global ENROLLMENT_STAGE
    ENROLLMENT_STAGE = 'prepare'
    require(os.environ.get('CREDENTIALS_DIRECTORY') == CREDENTIAL_DIRECTORY)
    ENROLLMENT_STAGE = 'state'
    directory = state_directory()
    try:
        require(os.listdir(directory) == [])
    finally:
        os.close(directory)
    ENROLLMENT_STAGE = 'terminal'
    with unifi_enroll._open_private_terminal() as terminal:
        ENROLLMENT_STAGE = 'config'
        config = unifi_enroll.unifi_snapshot.load_config(CONFIG)
        require(config['enabled'] is True and config['ca_file'] == str(CA))
        original = unifi_enroll.unifi_snapshot.UniFiClient
        class ReportingClient(original):
            def _get_json(self, path):
                global ENROLLMENT_STAGE
                ENROLLMENT_STAGE = ('info' if path == '/v1/info' else
                                    'sites' if path.startswith('/v1/sites?') else 'devices')
                return super()._get_json(path)
        ENROLLMENT_STAGE = 'client'
        unifi_enroll.unifi_snapshot.UniFiClient = ReportingClient
        try:
            unifi_enroll.run_enrollment(CONFIG, Path(CREDENTIAL_DIRECTORY) / 'unifi-api-key',
                                        CANDIDATE, terminal=terminal)
        finally:
            unifi_enroll.unifi_snapshot.UniFiClient = original


def ticket_closed():
    result = subprocess.run(
        ['/run/wrappers/bin/sudo', '-n', '--', TRUE], stdin=subprocess.DEVNULL,
        capture_output=True, text=True, timeout=3, env={**os.environ, 'LC_ALL': 'C'})
    require(result.returncode == 1 and result.stdout == ''
            and result.stderr == 'sudo: a password is required\n')


def main():
    operation = None
    try:
        if sys.argv[1:] == ['ticket-closed']:
            require(os.geteuid() != 0)
            ticket_closed()
            emit('UNIFI_ENROLL_TICKET_CLOSED')
            return 0
        require(os.geteuid() == os.getegid() == 0)
        module_file = unifi_enroll.__file__
        if module_file is None:
            raise RuntimeError('collector module origin missing')
        require(Path(module_file).parent == COLLECTOR_LIB)
        operations = {'preflight': preflight, 'enroll': enroll,
                      'cleanup': cleanup, 'finish': finish}
        require(len(sys.argv) == 2 and sys.argv[1] in operations)
        operation = sys.argv[1]
        operations[operation]()
    except BaseException as error:
        if operation == 'enroll':
            stages = {'prepare', 'state', 'terminal', 'config', 'client', 'info',
                      'sites', 'site-selection', 'devices', 'aliases'}
            stage = ENROLLMENT_STAGE if ENROLLMENT_STAGE in stages else 'prepare'
            marker = f'UNIFI_ENROLL_FAILURE stage={stage} reason={failure_kind(error)}'
            try:
                subprocess.run([LOGGER, '-t', 'homelab-unifi-enroll-01', '--', marker],
                               capture_output=True, timeout=3, check=True)
            except BaseException:
                emit('UNIFI_ENROLL_DIAGNOSTIC_UNAVAILABLE')
            emit(marker)
        emit('UNIFI_ENROLL_STEP_FAILED')
        return 2
    emit('UNIFI_ENROLL_STEP_PASS')
    return 0


def emit(marker):
    try:
        print(marker, flush=True)
    except OSError:
        pass  # Root audit already persisted; broken terminal cannot suppress it.


if __name__ == '__main__':
    raise SystemExit(main())
