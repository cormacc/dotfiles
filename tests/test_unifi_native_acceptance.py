"""Synthetic-only acceptance gates. Never invoke sudo/systemd/network."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
import io
import contextlib
from types import SimpleNamespace
import subprocess
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'sources/homelab-agent/scripts'))


def module():
    path = HERE / 'fixtures/unifi_native_acceptance.py'
    assert path.exists(), 'native acceptance implementation is missing'
    spec = importlib.util.spec_from_file_location('native_acceptance', path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class TransactionTests(unittest.TestCase):
    def test_transaction_preserves_previous_and_installs_exact_bytes(self):
        m = module()
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as temporary:
            root = Path(temporary).resolve()
            live = root / 'live'
            private = root / 'private'
            live.mkdir(mode=0o750)
            private.mkdir(mode=0o700)
            original = b'{"version":1,"enabled":false}\n'
            candidate = b'{"version":1,"enabled":true}\n'
            (live / 'config.json').write_bytes(original)
            (live / 'config.json').chmod(0o440)
            with patch.multiple(m, ROOT_UID=os.geteuid(), ROOT_GID=os.getegid()):
                tx = m.ConfigTransaction(live / 'config.json', private / 'config.previous.json', os.getegid())
                tx.install(candidate)
                self.assertEqual((live / 'config.json').read_bytes(), candidate)
                self.assertEqual((private / 'config.previous.json').read_bytes(), original)
                self.assertEqual((private / 'config.previous.json').stat().st_mode & 0o777, 0o600)
                tx.rollback()
                self.assertEqual((live / 'config.json').read_bytes(), original)


class GateTests(unittest.TestCase):
    def test_live_acceptance_requires_name_schema_but_legacy_state_stays_readable(self):
        m = module()
        legacy = m.unifi_snapshot.collect_snapshot(
            {'site_id': 'site', 'expected_devices': {'device-001': 'device'}},
            SimpleNamespace(application_info=lambda: {'applicationVersion': '1'},
                            sites=lambda: [{'id': 'site'}], adopted_devices=lambda site: []),
            '2026-10-16T12:00:00+00:00')
        legacy['schema_version'] = 1
        for device in legacy['devices']:
            device.pop('name', None)
        self.assertTrue(m.watch_unifi._valid_snapshot(legacy))
        with self.assertRaises(RuntimeError):
            m.accept_snapshot(legacy, 1)

    def test_install_rolls_back_on_validation_or_audit_failure(self):
        m = module()
        for failure in ('install', 'postread', 'validate', 'dormant', 'audit'):
            with self.subTest(failure=failure):
                events = []
                class Transaction:
                    owned = False
                    def install(self, content):
                        self.owned = True
                        events.append('install')
                        if failure == 'install':
                            raise RuntimeError('PRIVATE_SENTINEL')
                    def rollback(self):
                        events.append('rollback')
                        self.owned = False
                def check(name):
                    events.append(name)
                    if name == failure:
                        raise RuntimeError('PRIVATE_SENTINEL')
                tx = Transaction()
                with self.assertRaises(RuntimeError):
                    m.accept_install(tx, b'candidate', lambda: check('postread'),
                                     lambda: check('validate'), lambda: check('dormant'),
                                     lambda: check('audit'), lambda: check('restored'))
                self.assertIn('rollback', events)
                self.assertIn('restored', events)
                self.assertFalse(tx.owned)

    def test_commit_rechecks_installed_bytes_after_validation_before_audit(self):
        m = module()
        events = []
        tx = SimpleNamespace(owned=True, install=lambda data: events.append('install'),
                             rollback=lambda: events.append('rollback'))
        m.accept_install(tx, b'candidate', lambda: events.append('read'),
                         lambda: events.append('validate'), lambda: events.append('dormant'),
                         lambda: events.append('audit'), lambda: events.append('restored'))
        self.assertEqual(events, ['install', 'read', 'validate', 'dormant', 'read', 'audit'])
        self.assertFalse(tx.owned)

    def test_rollback_blocks_termination_until_restore_checks_finish(self):
        m = module()
        seen = []
        tx = SimpleNamespace(owned=True, install=lambda content: None,
                             rollback=lambda: seen.append('rollback'))
        with patch.object(m.signal, 'pthread_sigmask', side_effect=lambda how, value: seen.append(how) or set()):
            with self.assertRaises(RuntimeError):
                m.accept_install(tx, b'candidate', lambda: None,
                                 lambda: (_ for _ in ()).throw(RuntimeError('PRIVATE_SENTINEL')),
                                 lambda: None, lambda: None, lambda: seen.append('restored'))
        self.assertEqual(seen, [m.signal.SIG_BLOCK, 'rollback', 'restored', m.signal.SIG_SETMASK])

    def test_snapshot_acceptance_uses_real_schema_and_degraded_return_convention(self):
        m = module()
        snapshot = m.unifi_snapshot.collect_snapshot(
            {'site_id': 'site', 'expected_devices': {'ap': 'device'}},
            type('Client', (), {'application_info': lambda self: {'applicationVersion': '1'},
                               'sites': lambda self: [{'id': 'site'}],
                               'adopted_devices': lambda self, site: []})(),
            '2026-10-16T12:00:00+00:00')
        m.accept_snapshot(snapshot, 1)
        for status in (0, 2):
            with self.assertRaises(RuntimeError):
                m.accept_snapshot(snapshot, status)
        with self.assertRaises(RuntimeError):
            m.accept_snapshot({'overall': 'healthy'}, 0)

    def test_collect_requires_new_invocation_fresh_state_and_exact_journal(self):
        m = module()
        old = {'InvocationID': 'a' * 32, 'ExecMainStartTimestampMonotonic': '100'}
        after = dict(old, InvocationID='b' * 32, ExecMainStartTimestampMonotonic='200',
                     Result='success', ExecMainStatus='0', ActiveState='inactive', SubState='dead')
        m.verify_invocation(old, after)
        for field, value in [('InvocationID', 'a' * 32), ('Result', 'timeout'),
                             ('ExecMainStatus', '1'), ('ActiveState', 'active'),
                             ('ExecMainStartTimestampMonotonic', '100')]:
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                m.verify_invocation(old, dict(after, **{field: value}))
        m.verify_messages([], '', 'b' * 32)
        with self.assertRaises(RuntimeError):
            m.verify_messages([{'MESSAGE': 'PRIVATE_SENTINEL'}], '', 'b' * 32)


class SyntheticFiles(unittest.TestCase):
    def setUp(self):
        self.m = module()
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.uid, self.gid = os.geteuid(), os.getegid()
        self.live = self.root / 'live'
        self.private = self.root / 'private'
        self.state_dir = self.root / 'state'
        for path, mode in ((self.live, 0o750), (self.private, 0o700), (self.state_dir, 0o700)):
            path.mkdir()
            path.chmod(mode)
        values = dict(ROOT_UID=self.uid, ROOT_GID=self.gid,
                      CONFIG=self.live / 'config.json', HOSTS=self.live / 'hosts',
                      CA=self.live / 'controller-ca.pem', KEY=self.live / 'api-key',
                      CANDIDATE=self.private / 'config.candidate.json',
                      BACKUP=self.private / 'config.previous.json',
                      STATE=self.state_dir / 'health.json')
        patcher = patch.multiple(self.m, **values)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.original = b'{"version":1,"enabled":false}\n'
        self.config = {'version': 1, 'enabled': True,
                       'base_url': 'https://synthetic.invalid/proxy/network/integration',
                       'site_id': '12345678-1234-4234-8234-123456789abc',
                       'expected_devices': {'ap': '87654321-4321-4321-8321-cba987654321'},
                       'ca_file': str(self.m.CA)}
        self.candidate = json.dumps(self.config).encode()
        for path, content, mode in ((self.m.CONFIG, self.original, 0o440),
                                    (self.m.CANDIDATE, self.candidate, 0o600),
                                    (self.m.CA, b'SYNTHETIC CA BYTES', 0o440),
                                    (self.m.HOSTS, b'127.0.0.1 localhost\n', 0o440),
                                    (self.m.KEY, b'SYNTHETIC NEVER OPEN', 0o400)):
            path.write_bytes(content)
            path.chmod(mode)

    def tx(self):
        return self.m.ConfigTransaction(self.m.CONFIG, self.m.BACKUP, self.gid)

    def snapshot(self, now=None, degraded=False):
        client = SimpleNamespace(application_info=lambda: {'applicationVersion': '1'},
                                 sites=lambda: [{'id': self.config['site_id']}],
                                 adopted_devices=lambda site: [] if degraded else [
                                     {'id': next(iter(self.config['expected_devices'].values())),
                                      'model': 'synthetic', 'state': 'ONLINE',
                                      'supported': True, 'firmwareUpdatable': False}])
        return self.m.unifi_snapshot.collect_snapshot(
            self.config, client, now or self.m.datetime.now(self.m.timezone.utc).isoformat())

    def preflight(self, mode='install'):
        with patch.object(self.m, 'dormant'), patch.object(self.m, 'deadline'), \
             patch.object(self.m, 'properties', return_value={'LoadState': 'not-found'}):
            return self.m.preflight(mode, self.uid, self.gid)

    def test_full_install_accepts_and_preserves_root_only_backup(self):
        events = []
        with patch.object(self.m, 'validation_unit', side_effect=lambda: events.append('validate')), \
             patch.object(self.m, 'dormant', side_effect=lambda: events.append('dormant')), \
             patch.object(self.m, 'audit', side_effect=lambda marker: events.append('audit')):
            self.m.install(self.candidate, self.gid)
        self.assertEqual(events, ['validate', 'dormant', 'audit'])
        self.assertEqual(self.m.CONFIG.read_bytes(), self.candidate)
        self.assertEqual(self.m.BACKUP.read_bytes(), self.original)
        self.assertEqual(self.m.CONFIG.stat().st_mode & 0o777, 0o440)
        self.assertEqual(self.m.BACKUP.stat().st_mode & 0o777, 0o600)

    def test_real_transaction_fault_classes_restore_exact_original(self):
        for fault in ('write', 'file-fsync', 'rename', 'directory-fsync', 'readback',
                      'parser', 'validate', 'dormant', 'audit', 'signal'):
            with self.subTest(fault=fault):
                self.m.CONFIG.chmod(0o640)
                self.m.CONFIG.write_bytes(self.original)
                self.m.CONFIG.chmod(0o440)
                self.m.BACKUP.unlink(missing_ok=True)
                atomic = self.m.atomic
                fsync = self.m.os.fsync
                replace = self.m.os.replace
                read_at = self.m.read_at
                protected = self.m.protected_config
                fired = [False]
                def once(operation, action):
                    if not fired[0] and fault == operation:
                        fired[0] = True
                        raise RuntimeError('PRIVATE_SENTINEL')
                    return action()
                def damaged_atomic(*args):
                    return once('write', lambda: atomic(*args))
                def damaged_fsync(fd):
                    isdir = __import__('stat').S_ISDIR(os.fstat(fd).st_mode)
                    operation = 'directory-fsync' if isdir else 'file-fsync'
                    # Cover live-file fsync before rename and live-directory
                    # fsync AFTER rename, not just backup creation failures.
                    if self.m.BACKUP.exists():
                        inode = os.fstat(fd).st_ino
                        if (isdir and inode == self.live.stat().st_ino) or (
                                not isdir and inode != self.m.BACKUP.stat().st_ino):
                            return once(operation, lambda: fsync(fd))
                    return fsync(fd)
                def damaged_replace(*args, **kwargs):
                    return once('rename', lambda: replace(*args, **kwargs))
                def damaged_read(fd, name, *args, **kwargs):
                    if name == self.m.CONFIG.name and self.m.CONFIG.read_bytes() == self.candidate:
                        return once('readback', lambda: read_at(fd, name, *args, **kwargs))
                    return read_at(fd, name, *args, **kwargs)
                def damaged_parser(*args, **kwargs):
                    if kwargs.get('accepted'):
                        return once('parser', lambda: protected(*args, **kwargs))
                    return protected(*args, **kwargs)
                def validate():
                    if fault == 'signal':
                        self.m.interrupted(15, None)
                    once('validate', lambda: None)
                def dormant():
                    once('dormant', lambda: None)
                output = io.StringIO()
                with patch.object(self.m, 'atomic', side_effect=damaged_atomic), \
                     patch.object(self.m.os, 'fsync', side_effect=damaged_fsync), \
                     patch.object(self.m.os, 'replace', side_effect=damaged_replace), \
                     patch.object(self.m, 'read_at', side_effect=damaged_read), \
                     patch.object(self.m, 'protected_config', side_effect=damaged_parser), \
                     patch.object(self.m, 'validation_unit', side_effect=validate), \
                     patch.object(self.m, 'dormant', side_effect=dormant), \
                     patch.object(self.m, 'audit', side_effect=lambda marker: once('audit', lambda: None)), \
                     patch.object(self.m, 'stop'), contextlib.redirect_stdout(output):
                    with self.assertRaises(RuntimeError):
                        self.m.install(self.candidate, self.gid)
                self.assertEqual(self.m.CONFIG.read_bytes(), self.original)
                self.assertNotIn('PRIVATE_SENTINEL', output.getvalue())
                self.assertIn('ROLLBACK_VERIFIED', output.getvalue())

    def test_rollback_failure_withholds_verified_marker_and_preserves_evidence(self):
        with patch.object(self.m, 'validation_unit', side_effect=RuntimeError('PRIVATE_SENTINEL')), \
             patch.object(self.m.ConfigTransaction, 'rollback', side_effect=OSError('PRIVATE_SENTINEL')), \
             patch.object(self.m, 'dormant'), patch.object(self.m, 'audit'), \
             contextlib.redirect_stdout(io.StringIO()) as output:
            with self.assertRaises(OSError):
                self.m.install(self.candidate, self.gid)
        self.assertEqual(output.getvalue(), '')
        self.assertEqual(self.m.CONFIG.read_bytes(), self.candidate)
        self.assertEqual(self.m.BACKUP.read_bytes(), self.original)

    def test_metadata_and_temporary_creation_failures_restore_original(self):
        for operation in ('fchown', 'fchmod', 'open'):
            with self.subTest(operation=operation):
                self.m.BACKUP.unlink(missing_ok=True)
                real = getattr(self.m.os, operation)
                fired = [False]
                def fail_once(*args, **kwargs):
                    eligible = operation != 'open' or str(args[0]).startswith('.acceptance-')
                    if eligible and not fired[0]:
                        fired[0] = True
                        raise OSError('PRIVATE_SENTINEL')
                    return real(*args, **kwargs)
                with patch.object(self.m.os, operation, side_effect=fail_once), \
                     patch.object(self.m, 'stop'), patch.object(self.m, 'dormant'), \
                     contextlib.redirect_stdout(io.StringIO()) as output:
                    with self.assertRaises(OSError):
                        self.m.install(self.candidate, self.gid)
                self.assertTrue(fired[0])
                self.assertEqual(self.m.CONFIG.read_bytes(), self.original)
                self.assertIn('ROLLBACK_VERIFIED', output.getvalue())

    def test_existing_backup_never_overwritten(self):
        self.m.BACKUP.write_bytes(b'prior protected backup')
        self.m.BACKUP.chmod(0o600)
        with self.assertRaises(FileExistsError):
            self.tx().install(self.candidate)
        self.assertEqual(self.m.BACKUP.read_bytes(), b'prior protected backup')
        self.assertEqual(self.m.CONFIG.read_bytes(), self.original)

    def test_rollback_refuses_unknown_live_or_changed_backup(self):
        tx = self.tx()
        tx.install(self.candidate)
        self.m.CONFIG.chmod(0o640)
        self.m.CONFIG.write_bytes(b'unknown third config')
        self.m.CONFIG.chmod(0o440)
        with self.assertRaises(RuntimeError):
            tx.rollback()
        self.assertEqual(self.m.CONFIG.read_bytes(), b'unknown third config')
        self.m.CONFIG.chmod(0o640)
        self.m.CONFIG.write_bytes(self.candidate)
        self.m.CONFIG.chmod(0o440)
        self.m.BACKUP.write_bytes(b'tampered backup')
        with self.assertRaises(RuntimeError):
            tx.rollback()
        self.assertEqual(self.m.CONFIG.read_bytes(), self.candidate)

    def test_preflight_never_opens_key_or_mutates_infrastructure(self):
        original_open = self.m.os.open
        opened = []
        def checked_open(path, *args, **kwargs):
            opened.append(str(path))
            self.assertNotEqual(str(path), self.m.KEY.name)
            self.assertNotEqual(str(path), str(self.m.KEY))
            self.assertFalse(args[0] & (os.O_CREAT | os.O_WRONLY | os.O_RDWR))
            return original_open(path, *args, **kwargs)
        with patch.object(self.m.os, 'open', side_effect=checked_open):
            candidate, previous = self.preflight()
        self.assertEqual(candidate, self.candidate)
        self.assertIsNone(previous)
        self.assertFalse(self.m.BACKUP.exists())
        self.assertTrue(opened)

    def test_protected_configs_reject_synthetic_ids_empty_disabled_wrong_ca(self):
        for update in ({'site_id': next(iter(self.m.SYNTHETIC_IDS))},
                       {'expected_devices': {}}, {'enabled': False},
                       {'ca_file': None}, {'expected_devices': {'ap': '22222222-2222-4222-8222-222222222222'}}):
            with self.subTest(update=update):
                self.m.CANDIDATE.write_text(json.dumps(dict(self.config, **update)))
                with self.assertRaises((RuntimeError, ValueError)):
                    self.preflight()

    def test_file_and_directory_metadata_drift_is_not_repaired(self):
        for path in (self.m.CONFIG, self.m.CANDIDATE, self.m.CA, self.m.HOSTS,
                     self.m.KEY, self.private, self.live, self.state_dir):
            mode = path.stat().st_mode & 0o777
            with self.subTest(path=path.name):
                path.chmod(mode | 0o020)
                with self.assertRaises((RuntimeError, OSError, ValueError)):
                    self.preflight()
                self.assertEqual(path.stat().st_mode & 0o777, mode | 0o020)
                path.chmod(mode)

    def test_symlink_fifo_hardlink_and_oversized_candidate_are_rejected(self):
        path = self.m.CANDIDATE
        for kind in ('symlink', 'fifo', 'hardlink', 'oversize'):
            with self.subTest(kind=kind):
                path.unlink()
                target = self.private / 'target'
                if kind in ('symlink', 'hardlink'):
                    target.write_bytes(self.candidate)
                    target.chmod(0o600)
                    if kind == 'symlink':
                        path.symlink_to(target)
                    else:
                        os.link(target, path)
                elif kind == 'fifo':
                    os.mkfifo(path, 0o600)
                else:
                    path.write_bytes(b' ' * (self.m.MAX_BYTES + 1))
                    path.chmod(0o600)
                with self.assertRaises((RuntimeError, OSError, ValueError)):
                    self.preflight()
                path.unlink()
                target.unlink(missing_ok=True)
                path.write_bytes(self.candidate)
                path.chmod(0o600)

    def test_root_validator_accepts_service_owned_state_without_load_state(self):
        snapshot = self.snapshot()
        self.m.STATE.write_text(json.dumps(snapshot))
        self.m.STATE.chmod(0o600)
        with patch.object(self.m.watch_unifi, 'load_state', side_effect=AssertionError('wrong EUID API')):
            self.assertEqual(self.m.state(self.uid, self.gid), snapshot)
        self.m.STATE.chmod(0o640)
        with self.assertRaises(RuntimeError):
            self.m.state(self.uid, self.gid)

    def test_collect_preflight_requires_exact_installed_candidate(self):
        tx = self.tx()
        tx.install(self.candidate)
        candidate, prior = self.preflight('collect')
        self.assertEqual(candidate, self.candidate)
        self.assertIsNone(prior)
        self.m.CANDIDATE.write_bytes(self.candidate + b'\n')
        with self.assertRaises(RuntimeError):
            self.preflight('collect')

    def test_native_validator_uses_real_three_get_collector_with_synthetic_transport(self):
        self.m.CONFIG.chmod(0o640)
        self.m.CONFIG.write_bytes(self.candidate)
        self.m.CONFIG.chmod(0o440)
        requests = []
        site_id = self.config['site_id']
        class Terminal(io.StringIO):
            def isatty(self):
                return True
        def transport(request, **kwargs):
            requests.append((request.get_method(), request.full_url))
            if request.full_url.endswith('/v1/info'):
                body = {'applicationVersion': '1'}
            elif '/devices?' in request.full_url:
                # Missing expected device is valid DEGRADED, raw collector rc1.
                body = {'offset': 0, 'limit': 50, 'count': 0, 'totalCount': 0, 'data': []}
            else:
                body = {'offset': 0, 'limit': 50, 'count': 1, 'totalCount': 1,
                        'data': [{'id': site_id, 'name': 'synthetic', 'internalReference': 'synthetic'}]}
            return io.BytesIO(json.dumps(body).encode())
        with patch.object(self.m.unifi_enroll, '_open_private_terminal', return_value=Terminal()), \
             patch.object(self.m.unifi_snapshot, '_read_ca_data', return_value=None), \
             patch.object(self.m.unifi_snapshot, 'read_credential', return_value='SYNTHETIC_SENTINEL'), \
             patch.object(self.m.unifi_snapshot, '_verified_opener', return_value=transport), \
             contextlib.redirect_stdout(io.StringIO()) as output:
            self.m.validate()
        self.assertEqual(len(requests), 3)
        self.assertEqual({method for method, _ in requests}, {'GET'})
        self.assertEqual([url.removeprefix(self.config['base_url']) for _, url in requests],
                         ['/v1/info', '/v1/sites?offset=0&limit=50',
                          '/v1/sites/' + site_id + '/devices?offset=0&limit=50'])
        self.assertEqual(output.getvalue(), 'UNIFI_ACCEPT_AUTHENTICATED_COLLECTION_PASS\n')

    def test_supervised_collect_runs_once_and_unchanged_invocation_is_silent(self):
        previous = self.snapshot()
        for baseline in (None, previous):
            commands = []
            before = {'InvocationID': 'a' * 32, 'ExecMainStartTimestampMonotonic': '100'}
            after = dict(before, InvocationID='b' * 32, ExecMainStartTimestampMonotonic='200',
                         Result='success', ExecMainStatus='0', ActiveState='inactive', SubState='dead')
            def run(args, timeout=5):
                commands.append(args)
                if args[0] == self.m.SYSTEMCTL:
                    fresh = self.snapshot()
                    self.m.STATE.write_text(json.dumps(fresh))
                    self.m.STATE.chmod(0o600)
                return ''
            with patch.object(self.m, 'properties', side_effect=[before, after]), \
                 patch.object(self.m, 'command', side_effect=run), \
                 patch.object(self.m, 'dormant'), patch.object(self.m, 'audit') as audit, \
                 patch.object(self.m, 'stop') as stop:
                self.m.collect(baseline, self.uid, self.gid)
                stop.assert_not_called()
                audit.assert_called_once_with('UNIFI_ACCEPT_COLLECT_CHECKS_PASS')
            self.assertEqual(commands[0], [self.m.SYSTEMCTL, 'start', self.m.SERVICE])
            self.assertEqual(len(commands), 2)
            self.assertIn('_SYSTEMD_INVOCATION_ID=' + 'b' * 32, commands[1])
            self.assertNotIn(self.m.TIMER, str(commands))

    def test_collect_failures_stop_only_watcher_preserve_state_and_config(self):
        for failure in ('start', 'invocation', 'state', 'stale', 'journal', 'audit'):
            with self.subTest(failure=failure):
                before = {'InvocationID': 'a' * 32, 'ExecMainStartTimestampMonotonic': '100'}
                after = dict(before, InvocationID='b' * 32, ExecMainStartTimestampMonotonic='200',
                             Result='success', ExecMainStatus='0', ActiveState='inactive', SubState='dead')
                if failure == 'invocation':
                    after['InvocationID'] = before['InvocationID']
                saved = []
                def run(args, timeout=5):
                    if args[0] == self.m.SYSTEMCTL:
                        if failure == 'start':
                            raise RuntimeError('PRIVATE_SENTINEL')
                        snapshot = self.snapshot('2020-01-01T00:00:00+00:00' if failure == 'stale' else None)
                        if failure == 'state':
                            snapshot = {'overall': 'healthy'}
                        self.m.STATE.write_text(json.dumps(snapshot))
                        self.m.STATE.chmod(0o600)
                        saved.append(self.m.STATE.read_bytes())
                    return '{"MESSAGE":"PRIVATE_SENTINEL"}\n' if failure == 'journal' else ''
                with patch.object(self.m, 'properties', side_effect=[before, after]), \
                     patch.object(self.m, 'command', side_effect=run), patch.object(self.m, 'dormant'), \
                     patch.object(self.m, 'audit', side_effect=RuntimeError('PRIVATE_SENTINEL') if failure == 'audit' else None), \
                     patch.object(self.m, 'stop') as stop, patch.object(self.m, 'install') as install:
                    with self.assertRaises((RuntimeError, ValueError)):
                        self.m.collect(None, self.uid, self.gid)
                    stop.assert_called_once_with(self.m.SERVICE)
                    install.assert_not_called()
                self.assertEqual(self.m.CONFIG.read_bytes(), self.original)
                if saved:
                    self.assertEqual(self.m.STATE.read_bytes(), saved[0])

    def test_candidate_age_is_bounded_without_cleanup(self):
        os.utime(self.m.CANDIDATE, (1, 1))
        with self.assertRaises(RuntimeError):
            self.preflight()
        self.assertTrue(self.m.CANDIDATE.exists())


class BoundaryTests(unittest.TestCase):
    def test_dormancy_accepts_actual_infinity_but_rejects_schedules_or_jobs(self):
        m = module()
        service = dict(LoadState='loaded', ActiveState='inactive', SubState='dead', Job='')
        timer = dict(service, UnitFileState='static', NextElapseUSecRealtime='',
                     NextElapseUSecMonotonic='infinity')
        with patch.object(m, 'properties', side_effect=[service, timer]):
            m.dormant()
        for changes in ({'ActiveState': 'active'}, {'NextElapseUSecMonotonic': '5min'},
                        {'NextElapseUSecRealtime': 'Fri 2026-10-16'}, {'UnitFileState': 'enabled'},
                        {'Job': '123'}):
            with self.subTest(changes=changes), patch.object(m, 'properties', side_effect=[service, dict(timer, **changes)]):
                with self.assertRaises(RuntimeError):
                    m.dormant()

    def test_transient_validate_has_fixed_private_bindings_credential_and_deadline(self):
        m = module()
        with patch.object(m.subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as run:
            m.validation_unit()
        args = run.call_args.args[0]
        for value in ('--system', '--pty', '--wait', '--collect', '--unit=' + m.VALIDATOR,
                      '--property=TimeoutStartSec=120s', '--property=TimeoutStopSec=10s',
                      '--property=KillMode=control-group', '--property=SendSIGKILL=yes',
                      '--property=LoadCredential=unifi-api-key:' + str(m.KEY),
                      '--property=BindReadOnlyPaths=' + str(m.HOSTS) + ':/etc/hosts'):
            self.assertIn(value, args)
        self.assertNotIn('--property=PrivateNetwork=yes', args)
        self.assertTrue(any('InaccessiblePaths=/run/nscd/socket -/var/lib/hermes ' + str(m.KEY) in item for item in args))
        self.assertEqual(args[-5:], [m.PYTHON, '-I', '-B', m.PROBE, '--validate'])
        self.assertEqual(run.call_args.kwargs['timeout'], 145)

    def test_private_terminal_precedes_any_collection(self):
        m = module()
        events = []
        class Terminal(io.StringIO):
            def isatty(self):
                return True
        def terminal():
            events.append('terminal')
            return Terminal()
        def run(*args, **kwargs):
            events.append('collection')
            self.assertEqual(args, (m.CONFIG, Path('/run/credentials') / m.VALIDATOR / 'unifi-api-key'))
            return {'PRIVATE_SENTINEL': 'private'}, 0
        output = io.StringIO()
        with patch.object(m.unifi_enroll, '_open_private_terminal', side_effect=terminal), \
             patch.object(m.unifi_snapshot, 'run_collection', side_effect=run), \
             patch.object(m, 'accept_snapshot'), contextlib.redirect_stdout(output):
            m.validate()
        self.assertEqual(events, ['terminal', 'collection'])
        self.assertEqual(output.getvalue(), 'UNIFI_ACCEPT_AUTHENTICATED_COLLECTION_PASS\n')

    def test_cli_terminal_failure_never_touches_preflight_or_reflects_exception(self):
        m = module()
        with patch.multiple(m, MODE='install', COLLECTOR_LIB=Path(m.unifi_snapshot.__file__).parent), \
             patch.object(m.os, 'geteuid', return_value=0), patch.object(m.os, 'getegid', return_value=0), \
             patch.object(m.unifi_enroll, '_open_private_terminal', side_effect=RuntimeError('PRIVATE_SENTINEL')), \
             patch.object(m, 'preflight') as preflight, contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(m.main(['--preflight']), 2)
            preflight.assert_not_called()
        self.assertEqual(output.getvalue(), 'UNIFI_ACCEPT_STEP_FAILED\n')

    def test_ticket_closure_requires_specific_password_required_class(self):
        m = module()
        for result in (SimpleNamespace(returncode=0, stdout='', stderr=''),
                       SimpleNamespace(returncode=1, stdout='', stderr='sudo: no permission\n'),
                       SimpleNamespace(returncode=1, stdout='PRIVATE_SENTINEL', stderr='sudo: a password is required\n')):
            with patch.object(m.subprocess, 'run', return_value=result), self.assertRaises(RuntimeError):
                m.ticket_closed()
        with patch.object(m.subprocess, 'run', return_value=SimpleNamespace(
                returncode=1, stdout='', stderr='sudo: a password is required\n')):
            m.ticket_closed()

    def test_bounded_command_captures_only_local_synthetic_children(self):
        m = module()
        self.assertEqual(m.command([sys.executable, '-c', 'print("synthetic")']), 'synthetic\n')
        with self.assertRaises(RuntimeError):
            m.command([sys.executable, '-c', 'import sys;sys.stdout.write("x"*(4*1024*1024+1))'])
        with self.assertRaises(RuntimeError):
            m.command([sys.executable, '-c', 'import time;time.sleep(10)'], timeout=0.02)

    def test_absent_transient_stop_is_harmless(self):
        m = module()
        with patch.object(m, 'properties', return_value={'LoadState': 'not-found'}), \
             patch.object(m, 'command') as command:
            m.stop(m.VALIDATOR)
            command.assert_not_called()


class LauncherTests(unittest.TestCase):
    def test_pure_nix_shape_and_generated_shell_without_build_or_privileges(self):
        import shutil
        nix = shutil.which('nix-instantiate')
        if not nix:
            self.skipTest('nix parser unavailable; parent performs native build')
        expression = '''(import %s) {
          collector = "/synthetic/collector";
          pkgs = {
            writeText = name: text: builtins.seq (builtins.stringLength text) "/synthetic/probe.py";
            writeShellScriptBin = name: text: { inherit name text; };
            symlinkJoin = value: value;
            systemd = "/synthetic/systemd";
            coreutils = "/synthetic/coreutils";
            python3 = "/synthetic/python";
            util-linux = "/synthetic/util-linux";
          };
        }''' % (HERE / 'unifi-native-acceptance.nix')
        result = subprocess.run([nix, '--eval', '--strict', '--json', '--expr', expression],
                                capture_output=True, text=True, check=True, timeout=15)
        rendered = json.loads(result.stdout)
        self.assertEqual([item['name'] for item in rendered['paths']],
                         ['unifi-native-install-validate', 'unifi-native-supervised-collect'])
        for item in rendered['paths']:
            script = item['text']
            syntax = subprocess.run(['bash', '-n'], input=script, text=True,
                                    capture_output=True, timeout=5)
            self.assertEqual(syntax.returncode, 0, syntax.stderr)
            negative = subprocess.run(['bash', '-s'], input=script, text=True,
                                      capture_output=True, timeout=5)
            self.assertEqual(negative.returncode, 2)
            self.assertEqual(negative.stdout, 'UNIFI_ACCEPT_ABORT stage=native-terminal\n')
            self.assertEqual(negative.stderr, '')

    def test_exact_two_fixed_launchers_share_proven_auth_boundary(self):
        path = HERE / 'unifi-native-acceptance.nix'
        self.assertTrue(path.exists(), 'fixed native entrypoints are missing')
        source = path.read_text()
        for text in ('pkgs.symlinkJoin', 'unifi-native-install-validate',
                     'unifi-native-supervised-collect', '/run/wrappers/bin/sudo',
                     "4511:0:0:regular file", '--preflight', '--ticket-closed',
                     '"$sudo" -K', '"$sudo" -v', '"$sudo" -n',
                     'trap cleanup EXIT', '200s', '15s'):
            self.assertIn(text, source)
        for text in ('ssh ', 'switch-to-configuration', 'nixos-rebuild',
                     'enable --now', 'reset-failed'):
            self.assertNotIn(text, source)


if __name__ == '__main__':
    unittest.main()
