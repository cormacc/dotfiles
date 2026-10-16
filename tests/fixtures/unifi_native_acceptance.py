"""Fixed native UniFi acceptance gates; not a production activation module.

No values from config, state, credentials or journal are emitted. The root
process owns a transaction until all install/validation/audit checks complete.
The CLI is specialized at build time to one of two literal modes.
"""
import os
from pathlib import Path
import secrets
import stat
import importlib
import json
import pwd
import grp
import re
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone

COLLECTOR_LIB = Path('@COLLECTOR_LIB@')
sys.path.insert(0, str(COLLECTOR_LIB))
unifi_snapshot = importlib.import_module('unifi_snapshot')
unifi_enroll = importlib.import_module('unifi_enroll')
watch_unifi = importlib.import_module('watch_unifi')
MODE = '@MODE@'
SYSTEMCTL = '@SYSTEMCTL@'
SYSTEMD_RUN = '@SYSTEMD_RUN@'
JOURNALCTL = '@JOURNALCTL@'
LOGGER = '@LOGGER@'
PYTHON = '@PYTHON@'
PROBE = str(Path(__file__).resolve())
TRUE = '@TRUE@'
CONFIG = Path('/var/lib/homelab-unifi/config.json')
HOSTS = CONFIG.parent / 'hosts'
CA = CONFIG.parent / 'controller-ca.pem'
KEY = CONFIG.parent / 'api-key'  # metadata only; never opened by this helper
CANDIDATE = Path('/var/lib/homelab-unifi-enroll-01/config.candidate.json')
BACKUP = CANDIDATE.parent / 'config.previous.json'
STATE = Path('/var/lib/homelab-unifi-state/health.json')
SERVICE = 'homelab-unifi-watch.service'
TIMER = 'homelab-unifi-watch.timer'
VALIDATOR = 'homelab-unifi-validate-01.service'
# Public synthetic identities from the previously reviewed native rehearsal.
SYNTHETIC_IDS = {'11111111-1111-4111-8111-111111111111',
                 '22222222-2222-4222-8222-222222222222',
                 '00000000-0000-0000-0000-000000000000'}

ROOT_UID = 0
ROOT_GID = 0
MAX_BYTES = 1024 * 1024


def require(condition):
    if not condition:
        raise RuntimeError('acceptance check failed')


def directory(path, uid, gid, mode):
    """Open all components no-follow; never repair metadata."""
    require(path.is_absolute() and '..' not in path.parts)
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for index, component in enumerate(path.parts[1:]):
            nxt = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = nxt
            meta = os.fstat(fd)
            owners = {uid} if index == len(path.parts[1:]) - 1 else {0, ROOT_UID}
            require(meta.st_uid in owners and not stat.S_IMODE(meta.st_mode) & 0o022)
        meta = os.fstat(fd)
        require((meta.st_uid, meta.st_gid, stat.S_IMODE(meta.st_mode)) == (uid, gid, mode))
        result, fd = fd, -1
        return result
    finally:
        if fd >= 0:
            os.close(fd)


def metadata(fd, uid, gid, mode, maximum=MAX_BYTES):
    value = os.fstat(fd)
    require(stat.S_ISREG(value.st_mode) and value.st_nlink == 1)
    require((value.st_uid, value.st_gid, stat.S_IMODE(value.st_mode)) == (uid, gid, mode))
    require(value.st_size <= maximum)


def read_at(fd, name, uid, gid, mode, maximum=MAX_BYTES):
    file = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    try:
        metadata(file, uid, gid, mode, maximum)
        with os.fdopen(file, 'rb', closefd=False) as handle:
            content = handle.read(maximum + 1)
        require(len(content) <= maximum)
        return content
    finally:
        os.close(file)


def atomic(fd, name, content, uid, gid, mode):
    """Same-directory replace, protected before write, with directory fsync."""
    temporary = '.acceptance-' + secrets.token_hex(12)
    file = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                   0o600, dir_fd=fd)
    try:
        with os.fdopen(file, 'wb') as handle:
            os.fchown(handle.fileno(), uid, gid)
            os.fchmod(handle.fileno(), mode)
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, name, src_dir_fd=fd, dst_dir_fd=fd)
        os.fsync(fd)
    finally:
        try:
            os.unlink(temporary, dir_fd=fd)
        except FileNotFoundError:
            pass


class ConfigTransaction:
    def __init__(self, live, backup, service_gid):
        self.live, self.backup, self.gid = live, backup, service_gid
        self.original = None
        self.candidate = None
        self.owned = False

    def install(self, content):
        live = directory(self.live.parent, ROOT_UID, self.gid, 0o750)
        private = directory(self.backup.parent, ROOT_UID, ROOT_GID, 0o700)
        try:
            self.original = read_at(live, self.live.name, ROOT_UID, self.gid, 0o440)
            # O_EXCL prevents reuse, overwrite, and ambiguous resumed ownership.
            backup = os.open(self.backup.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=private)
            with os.fdopen(backup, 'wb') as output:
                os.fchown(output.fileno(), ROOT_UID, ROOT_GID)
                os.fchmod(output.fileno(), 0o600)
                output.write(self.original)
                output.flush()
                os.fsync(output.fileno())
            os.fsync(private)
            require(read_at(private, self.backup.name, ROOT_UID, ROOT_GID, 0o600) == self.original)
            self.candidate = content
            self.owned = True  # before rename: fsync/readback failure must roll back
            atomic(live, self.live.name, content, ROOT_UID, self.gid, 0o440)
            require(read_at(live, self.live.name, ROOT_UID, self.gid, 0o440) == content)
        finally:
            os.close(live)
            os.close(private)

    def rollback(self):
        if not self.owned:
            return
        live = directory(self.live.parent, ROOT_UID, self.gid, 0o750)
        private = directory(self.backup.parent, ROOT_UID, ROOT_GID, 0o700)
        try:
            saved = read_at(private, self.backup.name, ROOT_UID, ROOT_GID, 0o600)
            require(saved == self.original)
            current = read_at(live, self.live.name, ROOT_UID, self.gid, 0o440)
            require(current in (self.original, self.candidate))  # never clobber third-party data
            if current != self.original:
                atomic(live, self.live.name, saved, ROOT_UID, self.gid, 0o440)
            require(read_at(live, self.live.name, ROOT_UID, self.gid, 0o440) == self.original)
            self.owned = False
        finally:
            os.close(live)
            os.close(private)


def accept_install(tx, content, postread, validate, dormant, audit, restored):
    """Audit is inside commit boundary; rollback never depends on audit working."""
    try:
        tx.install(content)
        postread()
        validate()
        dormant()
        postread()
        audit()
    except BaseException:
        old_mask = signal.pthread_sigmask(signal.SIG_BLOCK,
                                         {signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGALRM})
        try:
            tx.rollback()
            restored()
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)
        raise
    tx.owned = False


def accept_snapshot(snapshot, status):
    require(watch_unifi._valid_snapshot(snapshot))
    require(snapshot['schema_version'] == 2)
    require(snapshot['overall'] in {'healthy', 'degraded'})
    # Reviewed collector status 1 means device degradation, not failed GETs.
    require(status == (0 if snapshot['overall'] == 'healthy' else 1))


def verify_invocation(before, after):
    require(re.fullmatch('[0-9a-f]{32}', after.get('InvocationID', '')) is not None)
    require(after['InvocationID'] != before.get('InvocationID'))
    require(int(after['ExecMainStartTimestampMonotonic']) >
            int(before.get('ExecMainStartTimestampMonotonic') or '0'))
    require(all(after.get(key) == value for key, value in {
        'Result': 'success', 'ExecMainStatus': '0',
        'ActiveState': 'inactive', 'SubState': 'dead'}.items()))


def verify_messages(records, expected, invocation):
    require(len(records) == (1 if expected else 0))
    for record in records:
        require(record.get('_SYSTEMD_INVOCATION_ID') == invocation)
        require(record.get('_SYSTEMD_UNIT') == SERVICE)
        require(record.get('_TRANSPORT') == 'stdout')
        require(record.get('MESSAGE') == expected)


def command(args, timeout=5):
    """Bound process and output; raw journal never leaves this root process."""
    import selectors
    process = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, start_new_session=True)
    output = bytearray()
    selector = selectors.DefaultSelector()
    try:
        selector.register(process.stdout, selectors.EVENT_READ)
        until = time.monotonic() + timeout
        while selector.get_map():
            remaining = until - time.monotonic()
            require(remaining > 0)
            for key, _ in selector.select(min(remaining, 1)):
                block = os.read(key.fd, 65536)
                if not block:
                    selector.unregister(key.fileobj)
                    break
                output.extend(block)
                require(len(output) <= 4 * MAX_BYTES)
        require(process.wait(timeout=max(0.01, until - time.monotonic())) == 0)
        return output.decode('utf-8')
    except BaseException:
        process.kill()
        process.wait(timeout=2)
        raise
    finally:
        selector.close()
        process.stdout.close()


def properties(unit, names):
    result = command([SYSTEMCTL, 'show', unit, '--no-pager'] +
                     [item for name in names for item in ('-p', name)])
    values = dict(line.split('=', 1) for line in result.splitlines())
    require(set(values) == set(names))
    return values


def dormant():
    service = properties(SERVICE, ['LoadState', 'ActiveState', 'SubState', 'Job'])
    require(service == {'LoadState': 'loaded', 'ActiveState': 'inactive',
                        'SubState': 'dead', 'Job': ''})
    timer = properties(TIMER, ['LoadState', 'ActiveState', 'SubState', 'UnitFileState',
                               'NextElapseUSecRealtime', 'NextElapseUSecMonotonic', 'Job'])
    require(timer['LoadState'] == 'loaded' and timer['ActiveState'] == 'inactive'
            and timer['SubState'] == 'dead' and timer['Job'] == '')
    require(timer['UnitFileState'] in {'disabled', 'static'})
    require(all(timer[key] in {'', '0', 'infinity', 'n/a'} for key in
                ('NextElapseUSecRealtime', 'NextElapseUSecMonotonic')))


def deadline():
    values = properties(SERVICE, ['TimeoutStartUSec', 'TimeoutStopUSec', 'KillMode',
                                  'KillSignal', 'FinalKillSignal', 'SendSIGKILL',
                                  'TimeoutStartFailureMode', 'User', 'Group',
                                  'StateDirectory', 'StateDirectoryMode'])
    require(values == {'TimeoutStartUSec': '2min', 'TimeoutStopUSec': '10s',
                      'KillMode': 'control-group', 'KillSignal': '15',
                      'FinalKillSignal': '9', 'SendSIGKILL': 'yes',
                      'TimeoutStartFailureMode': 'terminate', 'User': 'homelab-health',
                      'Group': 'homelab-health', 'StateDirectory': 'homelab-unifi-state',
                      'StateDirectoryMode': '0700'})


def read_file(path, uid, gid, mode, parent_mode, maximum=MAX_BYTES):
    fd = directory(path.parent, uid if parent_mode == 0o700 else ROOT_UID, gid, parent_mode)
    try:
        return read_at(fd, path.name, uid, gid, mode, maximum)
    finally:
        os.close(fd)


def protected_config(path, gid, candidate=False, accepted=False):
    owner_gid = ROOT_GID if candidate else gid
    mode, parent_mode = (0o600, 0o700) if candidate else (0o440, 0o750)
    content = read_file(path, ROOT_UID, owner_gid, mode, parent_mode)
    config = unifi_snapshot.load_config(path)
    if accepted:
        require(config['enabled'] and config['expected_devices'])
        require(config['ca_file'] == str(CA))
        require(not ({config['site_id']} | set(config['expected_devices'].values())) & SYNTHETIC_IDS)
    require(content == read_file(path, ROOT_UID, owner_gid, mode, parent_mode))
    return content


def state(uid, gid, missing=True):
    try:
        content = read_file(STATE, uid, gid, 0o600, 0o700, 4 * MAX_BYTES)
    except FileNotFoundError:
        require(missing)
        if os.path.lexists(STATE.parent):
            fd = directory(STATE.parent, uid, gid, 0o700)
            os.close(fd)
        return None
    snapshot = json.loads(content)
    require(watch_unifi._valid_snapshot(snapshot))
    return snapshot


def preflight(mode, uid, gid):
    dormant()
    deadline()
    fd = directory(CONFIG.parent, ROOT_UID, gid, 0o750)
    try:
        for path in (HOSTS, CA):
            read_at(fd, path.name, ROOT_UID, gid, 0o440)
        # Never open/read/hash/compare the credential, including during preflight.
        info = os.stat(KEY.name, dir_fd=fd, follow_symlinks=False)
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1)
        require((info.st_uid, info.st_gid, stat.S_IMODE(info.st_mode)) == (ROOT_UID, ROOT_GID, 0o400))
    finally:
        os.close(fd)
    require(0 <= time.time() - CANDIDATE.lstat().st_mtime <= 86400)
    candidate = protected_config(CANDIDATE, gid, candidate=True, accepted=True)
    live = protected_config(CONFIG, gid, accepted=(mode == 'collect'))
    previous = state(uid, gid)
    if mode == 'install':
        require(not os.path.lexists(BACKUP))
        require(properties(VALIDATOR, ['LoadState'])['LoadState'] == 'not-found')
        require(not os.path.lexists(Path('/run/systemd/transient') / VALIDATOR))
    else:
        require(live == candidate)
        protected_config(BACKUP, gid, candidate=True)
        require(0 <= time.time() - BACKUP.lstat().st_mtime <= 86400)
    return candidate, previous


def audit(marker):
    require(marker in {'UNIFI_ACCEPT_INSTALL_CHECKS_PASS', 'UNIFI_ACCEPT_COLLECT_CHECKS_PASS'})
    command([LOGGER, '-t', 'homelab-unifi-acceptance-01', '--', marker])


def validate():
    with unifi_enroll._open_private_terminal() as terminal:
        require(terminal.isatty())
        credential = Path('/run/credentials') / VALIDATOR / 'unifi-api-key'
        snapshot, status = unifi_snapshot.run_collection(
            CONFIG, credential, observed_at=datetime.now(timezone.utc).isoformat())
        accept_snapshot(snapshot, status)
    print('UNIFI_ACCEPT_AUTHENTICATED_COLLECTION_PASS', flush=True)


def validation_unit():
    args = [SYSTEMD_RUN, '--system', '--pty', '--wait', '--collect',
            '--service-type=oneshot', '--unit=' + VALIDATOR]
    values = ['User=root', 'Group=root', 'Restart=no', 'TimeoutStartSec=120s',
              'TimeoutStopSec=10s', 'TimeoutStartFailureMode=terminate',
              'TimeoutStopFailureMode=terminate', 'KillMode=control-group',
              'KillSignal=SIGTERM', 'FinalKillSignal=SIGKILL', 'SendSIGKILL=yes',
              'PrivateTmp=yes', 'ProtectSystem=strict', 'ProtectHome=yes',
              'NoNewPrivileges=yes', 'UMask=0077', 'LimitCORE=0',
              'BindReadOnlyPaths=' + str(HOSTS) + ':/etc/hosts',
              'InaccessiblePaths=/run/nscd/socket -/var/lib/hermes ' + str(KEY),
              'LoadCredential=unifi-api-key:' + str(KEY)]
    args += ['--property=' + value for value in values]
    args += [PYTHON, '-I', '-B', PROBE, '--validate']
    # Inherit the native controlling terminal, never a model-owned pipe.
    result = subprocess.run(args, timeout=145, check=False)
    require(result.returncode == 0)


def stop(unit):
    require(unit in {SERVICE, VALIDATOR})
    if unit == VALIDATOR and properties(unit, ['LoadState'])['LoadState'] == 'not-found':
        return
    command([SYSTEMCTL, 'stop', unit], timeout=15)
    values = properties(unit, ['ActiveState', 'SubState'])
    require(values['ActiveState'] in {'inactive', 'failed'} and values['SubState'] in {'dead', 'failed'})


def install(candidate, gid):
    tx = ConfigTransaction(CONFIG, BACKUP, gid)
    def postread():
        require(protected_config(CONFIG, gid, accepted=True) == candidate)
    def restored():
        stopped = True
        try:
            stop(VALIDATOR)
        except BaseException:
            stopped = False
        require(protected_config(CONFIG, gid) == tx.original)
        dormant()
        require(stopped)
        print('UNIFI_ACCEPT_ROLLBACK_VERIFIED', flush=True)
    accept_install(tx, candidate, postread, validation_unit, dormant,
                   lambda: audit('UNIFI_ACCEPT_INSTALL_CHECKS_PASS'), restored)


def collect(previous, uid, gid):
    before = properties(SERVICE, ['InvocationID', 'ExecMainStartTimestampMonotonic'])
    started = datetime.now(timezone.utc)
    start_ns = time.time_ns()
    try:
        command([SYSTEMCTL, 'start', SERVICE], timeout=145)
        after = properties(SERVICE, ['InvocationID', 'ExecMainStartTimestampMonotonic',
                                    'Result', 'ExecMainStatus', 'ActiveState', 'SubState'])
        verify_invocation(before, after)
        dormant()
        current = state(uid, gid, missing=False)
        if current is None:
            raise RuntimeError('fresh UniFi state missing')
        require(current['schema_version'] == 2)
        require(current['overall'] in {'healthy', 'degraded'})
        observed = datetime.fromisoformat(current['observed_at'])
        require(started <= observed <= datetime.now(timezone.utc))
        require(STATE.lstat().st_mtime_ns >= start_ns)
        expected = watch_unifi.transition_message(previous, current)
        journal = command([JOURNALCTL, '--no-pager', '--all', '--output=json', '-n', '3',
                           '_SYSTEMD_UNIT=' + SERVICE,
                           '_SYSTEMD_INVOCATION_ID=' + after['InvocationID'],
                           '_TRANSPORT=stdout'])
        verify_messages([json.loads(line) for line in journal.splitlines()], expected, after['InvocationID'])
        audit('UNIFI_ACCEPT_COLLECT_CHECKS_PASS')
    except BaseException:
        stop(SERVICE)
        raise


def ticket_closed():
    result = subprocess.run(['/run/wrappers/bin/sudo', '-n', '--', TRUE],
                            stdin=subprocess.DEVNULL, capture_output=True, text=True,
                            timeout=3, env={**os.environ, 'LC_ALL': 'C'})
    require(result.returncode == 1 and result.stdout == ''
            and result.stderr == 'sudo: a password is required\n')


def interrupted(_signum, _frame):
    raise RuntimeError('acceptance interrupted')


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    try:
        require(MODE in {'install', 'collect'})
        if args == ['--ticket-closed']:
            require(os.geteuid() != 0)
            ticket_closed()
            return 0
        require(os.geteuid() == os.getegid() == 0)
        for module in (unifi_snapshot, unifi_enroll, watch_unifi):
            require(Path(module.__file__).parent == COLLECTOR_LIB)
        if args == ['--validate']:
            require(MODE == 'install')
            validate()
            return 0
        require(args in ([], ['--preflight']))
        with unifi_enroll._open_private_terminal() as terminal:
            require(terminal.isatty())
            uid = pwd.getpwnam('homelab-health').pw_uid
            gid = grp.getgrnam('homelab-health').gr_gid
            for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGALRM):
                signal.signal(signum, interrupted)
            signal.alarm(180)
            try:
                candidate, previous = preflight(MODE, uid, gid)
                if not args:
                    if MODE == 'install':
                        install(candidate, gid)
                    else:
                        collect(previous, uid, gid)
            finally:
                signal.alarm(0)
        print('UNIFI_ACCEPT_PREFLIGHT_PASS' if args else 'UNIFI_ACCEPT_CHECKS_PASS', flush=True)
        return 0
    except BaseException:
        print('UNIFI_ACCEPT_STEP_FAILED', flush=True)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
