"""Offline-only launcher tests: never use NAS, a real key, TTY or network."""
import importlib.util
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'sources/homelab-agent/scripts'))
SOURCE = ROOT / 'tests/fixtures/unifi_native_enrollment.py'


def load_fixture():
    spec = importlib.util.spec_from_file_location('native_enrollment', SOURCE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class EnrollmentTests(unittest.TestCase):
    def test_failure_categories_follow_typed_causes_without_reflecting_private_text(self):
        from email.message import Message
        import ssl
        import urllib.error
        f = load_fixture()
        self.assertTrue(callable(getattr(f, 'failure_kind', None)))
        cases = [
            (urllib.error.URLError(TimeoutError('private-sentinel')), 'TIMEOUT'),
            (urllib.error.URLError(ssl.SSLCertVerificationError(1, 'private-sentinel')), 'TLS_CERTIFICATE'),
            (urllib.error.HTTPError('https://private-sentinel', 401, 'private-sentinel', Message(), io.BytesIO()), 'HTTP_401'),
            (urllib.error.HTTPError('https://private-sentinel', 403, 'private-sentinel', Message(), io.BytesIO()), 'HTTP_403'),
            (f.unifi_enroll.unifi_snapshot.ConfigError('private-sentinel'), 'CONFIG'),
            (f.unifi_enroll.unifi_snapshot.CredentialError('private-sentinel'), 'CREDENTIAL'),
            (f.unifi_enroll.unifi_snapshot.CollectorError('private-sentinel'), 'API_RESPONSE'),
        ]
        for cause, expected in cases:
            wrapped = f.unifi_enroll.unifi_snapshot.CollectorError('private-sentinel')
            wrapped.__context__ = cause
            try:
                with self.subTest(expected=expected):
                    self.assertEqual(expected, f.failure_kind(wrapped))
            finally:
                if isinstance(cause, urllib.error.HTTPError):
                    cause.close()
        cyclic = RuntimeError('private-sentinel')
        cyclic.__context__ = cyclic
        self.assertEqual('INTERNAL', f.failure_kind(cyclic))

    def test_main_audits_only_fixed_failure_stage_and_kind(self):
        import types
        import urllib.error
        f = load_fixture()
        error = f.unifi_enroll.unifi_snapshot.CollectorError('private-sentinel')
        error.__context__ = urllib.error.URLError(TimeoutError('private-sentinel'))
        marker = 'UNIFI_ENROLL_FAILURE stage=info reason=TIMEOUT'
        with mock.patch.object(f.os, 'geteuid', return_value=0), mock.patch.object(
            f.os, 'getegid', return_value=0
        ), mock.patch.object(f, 'COLLECTOR_LIB', Path(f.unifi_enroll.__file__).parent), mock.patch.object(
            f, 'enroll', side_effect=error
        ), mock.patch.object(f, 'ENROLLMENT_STAGE', 'info', create=True), mock.patch.object(
            f, 'LOGGER', '/synthetic/logger', create=True
        ), mock.patch.object(sys, 'argv', ['launcher', 'enroll']), mock.patch.object(
            f.subprocess, 'run', return_value=types.SimpleNamespace(returncode=0)
        ) as audit, mock.patch('sys.stdout', new_callable=io.StringIO) as output:
            self.assertEqual(2, f.main())
            self.assertEqual(marker + '\nUNIFI_ENROLL_STEP_FAILED\n', output.getvalue())
        self.assertEqual(['/synthetic/logger', '-t', 'homelab-unifi-enroll-01', '--', marker], audit.call_args.args[0])
        self.assertNotIn('private-sentinel', output.getvalue())

    def test_failed_api_call_records_stage_and_restores_original_client(self):
        import json
        f = load_fixture()
        original = f.unifi_enroll.unifi_snapshot.UniFiClient
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self, limit): return json.dumps({'applicationVersion': '1.0'}).encode()
        for failed_stage in ['info', 'sites']:
            def opener(request, **kwargs):
                if failed_stage == 'info' or '/sites?' in request.full_url:
                    raise TimeoutError('private-sentinel')
                return Response()
            def runner(*args, **kwargs):
                client = f.unifi_enroll.unifi_snapshot.UniFiClient(
                    'https://rehearsal.invalid/proxy/network/integration',
                    'synthetic-sentinel', 3, opener=opener)
                client.application_info()
                client.sites()
            with tempfile.TemporaryDirectory() as tmp:
                state = Path(tmp).resolve()/'state'; state.mkdir(mode=0o700)
                with mock.patch.multiple(f, STATE=state, CANDIDATE=state/'config.candidate.json'), mock.patch.dict(
                    os.environ, {'CREDENTIALS_DIRECTORY': f.CREDENTIAL_DIRECTORY}, clear=True
                ), mock.patch.object(f.unifi_enroll, '_open_private_terminal', return_value=mock.MagicMock()), mock.patch.object(
                    f.unifi_enroll.unifi_snapshot, 'load_config', return_value={'enabled': True, 'ca_file': str(f.CA)}
                ), mock.patch.object(f.unifi_enroll, 'run_enrollment', side_effect=runner):
                    with self.assertRaises(f.unifi_enroll.unifi_snapshot.CollectorError) as caught:
                        f.enroll()
                self.assertEqual(failed_stage, f.ENROLLMENT_STAGE)
                self.assertEqual('TIMEOUT', f.failure_kind(caught.exception))
                self.assertIs(original, f.unifi_enroll.unifi_snapshot.UniFiClient)

    def test_closed_terminal_does_not_prevent_fixed_failure_audit(self):
        import types
        f = load_fixture()
        class Broken(io.StringIO):
            def write(self, text): raise BrokenPipeError('private-sentinel')
        returned = None
        with mock.patch.object(f.os, 'geteuid', return_value=0), mock.patch.object(
            f.os, 'getegid', return_value=0
        ), mock.patch.object(f, 'COLLECTOR_LIB', Path(f.unifi_enroll.__file__).parent), mock.patch.object(
            f, 'enroll', side_effect=TimeoutError('private-sentinel')
        ), mock.patch.object(sys, 'argv', ['launcher', 'enroll']), mock.patch.object(
            f.subprocess, 'run', return_value=types.SimpleNamespace(returncode=0)
        ) as audit, mock.patch('sys.stdout', Broken()):
            try:
                returned = f.main()
            except OSError:
                pass
        self.assertEqual(2, returned)
        audit.assert_called_once()
        self.assertNotIn('private-sentinel', str(audit.call_args))

    def setUp(self):
        import socket
        import subprocess
        import unifi_enroll
        for target, name in [(socket, 'socket'), (subprocess, 'run'),
                             (unifi_enroll, '_open_private_terminal'),
                             (unifi_enroll.unifi_snapshot, 'read_credential')]:
            guard = mock.patch.object(target, name, side_effect=AssertionError('offline boundary'))
            guard.start()
            self.addCleanup(guard.stop)

    def test_finish_requires_preserved_candidate_not_merely_empty_state(self):
        f = load_fixture()
        self.assertTrue(callable(getattr(f, 'finish', None)), 'candidate-required final check missing')
        with mock.patch.object(f, 'cleanup', return_value=False), self.assertRaises(RuntimeError):
            f.finish()
        with mock.patch.object(f, 'cleanup', return_value=True):
            f.finish()

    def test_enrollment_acquires_terminal_before_config_and_reuses_existing_runner(self):
        self.assertTrue(SOURCE.exists(), 'real private enrollment launcher is missing')
        f = load_fixture()
        events = []
        terminal = mock.MagicMock()
        terminal.__enter__.side_effect = lambda: events.append('tty') or terminal
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp).resolve() / 'state'
            state.mkdir(mode=0o700)
            with mock.patch.multiple(f, STATE=state, CANDIDATE=state/'config.candidate.json'), mock.patch.object(
                f.unifi_enroll, '_open_private_terminal', return_value=terminal
            ), mock.patch.object(f.unifi_enroll.unifi_snapshot, 'load_config', side_effect=lambda p: events.append('config') or {'enabled': True, 'ca_file': str(f.CA)}), mock.patch.object(
                f.unifi_enroll, 'run_enrollment', side_effect=lambda *a, **kw: events.append('runner')
            ) as runner, mock.patch.dict(os.environ, {'CREDENTIALS_DIRECTORY': f.CREDENTIAL_DIRECTORY}, clear=True):
                f.enroll()
            self.assertEqual(['tty', 'config', 'runner'], events)
            runner.assert_called_once_with(f.CONFIG, Path(f.CREDENTIAL_DIRECTORY)/'unifi-api-key', state/'config.candidate.json', terminal=terminal)


    def test_cleanup_preserves_candidate_and_refuses_residue(self):
        f = load_fixture()
        self.assertTrue(callable(getattr(f, 'cleanup', None)), 'protected cleanup missing')
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp).resolve() / 'state'
            state.mkdir(mode=0o700)
            candidate = state/'config.candidate.json'
            candidate.write_text('synthetic-private-candidate')
            candidate.chmod(0o600)
            with mock.patch.multiple(f, STATE=state, CANDIDATE=candidate), mock.patch.object(f, 'quiescent') as quiet, mock.patch.object(f, 'verify_candidate') as verify:
                f.cleanup()
                verify.assert_called_once()
                self.assertTrue(candidate.exists())
                residue = state/'.unknown'
                residue.write_text('preserve')
                with self.assertRaises(RuntimeError):
                    f.cleanup()
                self.assertTrue(residue.exists())
                residue.unlink()
                candidate.unlink()
                f.cleanup()
                self.assertFalse(state.exists())
                self.assertEqual(3, quiet.call_count)

    def test_preflight_collision_is_metadata_only(self):
        f = load_fixture()
        self.assertTrue(callable(getattr(f, 'preflight', None)), 'metadata preflight missing')
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp)/'existing'
            state.mkdir()
            with mock.patch.object(f, 'STATE', state), mock.patch('builtins.open', side_effect=AssertionError('no reads')), mock.patch.object(f.unifi_enroll.unifi_snapshot, 'load_config') as config, mock.patch.object(f.unifi_enroll.unifi_snapshot, 'read_credential') as credential:
                with self.assertRaises(RuntimeError):
                    f.preflight()
                config.assert_not_called()
                credential.assert_not_called()

    def test_metadata_rejects_symlink_fifo_and_wrong_mode(self):
        f = load_fixture()
        self.assertTrue(callable(getattr(f, 'metadata', None)), 'metadata validation missing')
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            regular = root/'regular'
            regular.write_text('not-a-secret')
            regular.chmod(0o644)
            link = root/'link'
            link.symlink_to(regular)
            fifo = root/'fifo'
            os.mkfifo(fifo, 0o600)
            for path in [regular, link, fifo]:
                with self.subTest(path=path.name), self.assertRaises(RuntimeError):
                    f.metadata(path, 0o600, os.getegid())


    def test_wrapper_is_fixed_bounded_native_only_and_revokes_before_success(self):
        nix = ROOT/'tests/unifi-native-enrollment.nix'
        self.assertTrue(nix.exists(), 'immutable enrollment wrapper missing')
        text = nix.read_text()
        for required in ['sudo=/run/wrappers/bin/sudo', '-t 0', '-t 1', '-t 2', '$EUID == 0',
                         '4511:0:0:regular file', 'trap cleanup EXIT', '"$sudo" -K', '"$sudo" -v',
                         '--pty --wait --collect', '--property=TimeoutStartSec=180s',
                         '--property=TimeoutStopSec=10s', '--property=StateDirectoryMode=0700',
                         '--property=ProtectSystem=strict', '--property=PrivateTmp=yes',
                         '--property=ProtectHome=yes', '--property=NoNewPrivileges=yes',
                         '--property=UMask=0077', '--property=LimitCORE=0', '--property=Restart=no',
                         '--property=TimeoutStartFailureMode=terminate', '--property=KillMode=control-group',
                         '--property=KillSignal=SIGTERM', '--property=FinalKillSignal=SIGKILL',
                         '--property=SendSIGKILL=yes',
                         '--property=LoadCredential=unifi-api-key:/var/lib/homelab-unifi/api-key',
                         '--property=BindReadOnlyPaths=/var/lib/homelab-unifi/hosts:/etc/hosts',
                         'InaccessiblePaths=/run/nscd/socket -/var/lib/hermes /var/lib/homelab-unifi/api-key',
                         'UNIFI_ENROLL_CANDIDATE_VERIFIED', 'ticket-closed', 'UNIFI_ENROLL_ESCALATION_REQUIRED']:
            self.assertIn(required, text)
        self.assertNotIn('PrivateNetwork=yes', text)
        self.assertNotIn('systemctl start', text)
        self.assertIn('stop "$unit"', text)
        self.assertIn('reset-failed "$unit"', text)
        self.assertLess(text.index('UNIFI_ENROLL_CANDIDATE_VERIFIED'), text.index('ticket-closed'))

    def test_candidate_verification_uses_deployed_parser_after_tty_without_output(self):
        f = load_fixture()
        self.assertTrue(callable(getattr(f, 'verify_candidate', None)))
        events = []
        terminal = mock.MagicMock()
        terminal.__enter__.side_effect = lambda: events.append('tty') or terminal
        config = {'version': 1, 'enabled': True,
                  'base_url': 'https://synthetic.invalid/proxy/network/integration',
                  'site_id': '11111111-1111-4111-8111-111111111111',
                  'expected_devices': {'synthetic': '22222222-2222-4222-8222-222222222222'},
                  'ca_file': str(f.CA)}
        import json
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp).resolve()/'state'
            state.mkdir(mode=0o700)
            candidate = state/'config.candidate.json'
            candidate.write_text(json.dumps(config))
            candidate.chmod(0o600)
            parser = f.unifi_enroll.unifi_snapshot.load_config
            def parse(path):
                events.append('parser')
                return parser(path)
            with mock.patch.multiple(f, STATE=state, CANDIDATE=candidate), mock.patch.object(f.unifi_enroll, '_open_private_terminal', return_value=terminal), mock.patch.object(f.unifi_enroll.unifi_snapshot, '_read_ca_data', return_value='synthetic-ca'), mock.patch.object(f.unifi_enroll.unifi_snapshot, 'load_config', side_effect=parse), mock.patch('sys.stdout', new_callable=io.StringIO) as stdout:
                f.verify_candidate()
                self.assertEqual(['tty', 'parser'], events)
                self.assertEqual('', stdout.getvalue())
                for mode in [0o644, 0o400]:
                    candidate.chmod(mode)
                    with self.assertRaises(RuntimeError):
                        f.verify_candidate()

    def test_real_runner_with_synthetic_transport_persists_only_candidate(self):
        import json
        f = load_fixture()
        snapshot = f.unifi_enroll.unifi_snapshot
        site = '11111111-1111-4111-8111-111111111111'
        device = '22222222-2222-4222-8222-222222222222'
        requests = []
        class Terminal(io.StringIO):
            def isatty(self):
                return True
            def __exit__(self, *args):
                pass
        terminal = Terminal('1\nall\n')
        # Separate read/write positions emulate the private stream without a TTY.
        responses = io.StringIO('1\nall\n')
        terminal.readline = responses.readline
        def transport(request, **kwargs):
            requests.append(request)
            if request.full_url.endswith('/v1/info'):
                payload = {'applicationVersion': '10.4.57'}
            else:
                data = ([{'id': site, 'name': 'private-site-sentinel', 'internalReference': 'private-reference'}]
                        if request.full_url.split('?')[0].endswith('/v1/sites') else
                        [{'id': device, 'features': [], 'firmwareUpdatable': False, 'interfaces': [],
                          'ipAddress': '192.0.2.23', 'macAddress': '00:11:22:33:44:55', 'model': 'UDM',
                          'name': 'private-device-sentinel', 'state': 'ONLINE', 'supported': True}])
                payload = {'offset': 0, 'limit': 50, 'count': 1, 'totalCount': 1, 'data': data}
            return io.BytesIO(json.dumps(payload).encode())
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            state = root/'state'
            state.mkdir(mode=0o700)
            config = root/'config.json'
            config.write_text(json.dumps({'version': 1, 'enabled': True,
                'base_url': 'https://synthetic.invalid/proxy/network/integration', 'site_id': site,
                'expected_devices': {'placeholder': '33333333-3333-4333-8333-333333333333'}, 'ca_file': str(f.CA)}))
            config.chmod(0o600)
            candidate = state/'config.candidate.json'
            with mock.patch.multiple(f, CONFIG=config, STATE=state, CANDIDATE=candidate), mock.patch.dict(os.environ, {'CREDENTIALS_DIRECTORY': f.CREDENTIAL_DIRECTORY}, clear=True), mock.patch.object(f.unifi_enroll, '_open_private_terminal', return_value=terminal), mock.patch.object(snapshot, '_read_ca_data', return_value=None), mock.patch.object(snapshot, 'read_credential', return_value='synthetic-key-sentinel'), mock.patch.object(snapshot, '_verified_opener', return_value=transport), mock.patch('sys.stdout', new_callable=io.StringIO) as stdout, mock.patch('sys.stderr', new_callable=io.StringIO) as stderr:
                f.enroll()
                self.assertEqual('', stdout.getvalue() + stderr.getvalue())
            self.assertEqual(3, len(requests))
            self.assertEqual(['GET']*3, [r.get_method() for r in requests])
            self.assertEqual(['config.candidate.json'], os.listdir(state))
            self.assertEqual(0o600, candidate.stat().st_mode & 0o777)
            content = candidate.read_text()
            self.assertEqual({'device-001': device}, json.loads(content)['expected_devices'])
            self.assertNotIn('private-site-sentinel', content)
            self.assertNotIn('private-device-sentinel', content)
            self.assertNotIn('synthetic-key-sentinel', content + terminal.getvalue())
            self.assertIn('private-device-sentinel', terminal.getvalue())

    def test_quiescence_rejects_unit_collision_and_scheduled_timer(self):
        f = load_fixture()
        def props(unit, names):
            if unit == f.UNIT:
                return {'LoadState': 'not-found'}
            if unit.endswith('.service'):
                return {'ActiveState': 'inactive'}
            return {'ActiveState': 'inactive', 'NextElapseUSecRealtime': '', 'NextElapseUSecMonotonic': 'infinity'}
        with mock.patch.object(f.os.path, 'lexists', return_value=False), mock.patch.object(f, 'properties', side_effect=props):
            f.quiescent()
            with mock.patch.object(f.os.path, 'lexists', return_value=True), self.assertRaises(RuntimeError):
                f.quiescent()
            for changes in [{'ActiveState': 'active'}, {'NextElapseUSecRealtime': 'Fri 2026-10-16'}, {'NextElapseUSecMonotonic': '10s'}]:
                def changed(unit, names):
                    original = props(unit, names)
                    return {**original, **changes} if unit.endswith('.timer') else original
                with mock.patch.object(f, 'properties', side_effect=changed), self.assertRaises(RuntimeError):
                    f.quiescent()

    def test_metadata_checks_final_type_owner_mode_and_all_ancestors(self):
        import stat
        import types
        f = load_fixture()
        parent = types.SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_uid=0, st_gid=0)
        valid = types.SimpleNamespace(st_mode=stat.S_IFREG | 0o440, st_uid=0, st_gid=123)
        path = Path('/synthetic/config')
        with mock.patch.object(Path, 'lstat', side_effect=lambda p: valid if p == path else parent, autospec=True):
            f.metadata(path, 0o440, 123)
            for field, bad in [('st_mode', stat.S_IFIFO | 0o440), ('st_mode', stat.S_IFLNK | 0o440), ('st_mode', stat.S_IFREG | 0o644), ('st_uid', 501), ('st_gid', 0)]:
                original = getattr(valid, field)
                setattr(valid, field, bad)
                with self.assertRaises(RuntimeError):
                    f.metadata(path, 0o440, 123)
                setattr(valid, field, original)
            parent.st_mode = stat.S_IFLNK | 0o755
            with self.assertRaises(RuntimeError):
                f.metadata(path, 0o440, 123)

    def test_preflight_checks_only_fixed_metadata_and_socket(self):
        import grp
        import stat
        import types
        f = load_fixture()
        with mock.patch.object(f.os.path, 'lexists', return_value=False), mock.patch.object(f, 'quiescent'), mock.patch.object(grp, 'getgrnam', return_value=types.SimpleNamespace(gr_gid=123)), mock.patch.object(f, 'metadata') as metadata, mock.patch.object(Path, 'lstat', return_value=types.SimpleNamespace(st_mode=stat.S_IFSOCK)), mock.patch.object(Path, 'is_file', return_value=True), mock.patch('builtins.open', side_effect=AssertionError('no file reads')):
            f.preflight()
            self.assertEqual([mock.call(f.CONFIG.parent, 0o750, 123, directory=True), mock.call(f.CONFIG, 0o440, 123), mock.call(f.CONFIG.parent/'hosts', 0o440, 123), mock.call(f.CA, 0o440, 123), mock.call(f.CONFIG.parent/'api-key', 0o400, 0)], metadata.call_args_list)
            with mock.patch.object(Path, 'lstat', return_value=types.SimpleNamespace(st_mode=stat.S_IFREG)), self.assertRaises(RuntimeError):
                f.preflight()

    def test_no_tty_or_existing_candidate_never_enters_runner(self):
        f = load_fixture()
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp).resolve()/'state'
            state.mkdir(mode=0o700)
            with mock.patch.multiple(f, STATE=state, CANDIDATE=state/'config.candidate.json'), mock.patch.dict(os.environ, {'CREDENTIALS_DIRECTORY': f.CREDENTIAL_DIRECTORY}, clear=True), mock.patch.object(f.unifi_enroll, 'run_enrollment') as runner, mock.patch.object(f.unifi_enroll.unifi_snapshot, 'load_config') as parser:
                with self.assertRaises(AssertionError):
                    f.enroll()  # Default offline TTY guard fails before config/key.
                parser.assert_not_called()
                (state/'config.candidate.json').write_text('preserve')
                with self.assertRaises(RuntimeError):
                    f.enroll()
                runner.assert_not_called()

    def test_verifier_rejects_unsafe_candidate_and_parent_without_removing_them(self):
        f = load_fixture()
        for variant in ['symlink', 'fifo', 'public-parent', 'invalid-json']:
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as tmp:
                state = Path(tmp).resolve()/'state'
                state.mkdir(mode=0o700)
                candidate = state/'config.candidate.json'
                if variant == 'symlink':
                    candidate.symlink_to(state/'missing')
                elif variant == 'fifo':
                    os.mkfifo(candidate, 0o600)
                else:
                    candidate.write_text('{}')
                    candidate.chmod(0o600)
                if variant == 'public-parent':
                    state.chmod(0o755)
                with mock.patch.multiple(f, STATE=state, CANDIDATE=candidate), mock.patch.object(f.unifi_enroll, '_open_private_terminal', return_value=mock.MagicMock()):
                    with self.assertRaises((RuntimeError, OSError, f.unifi_enroll.unifi_snapshot.ConfigError)):
                        f.verify_candidate()
                self.assertTrue(os.path.lexists(candidate))
                self.assertEqual(0o755 if variant == 'public-parent' else 0o700, state.stat().st_mode & 0o777)

    def test_main_sanitizes_errors_and_rejects_nonroot_and_unknown_arguments(self):
        f = load_fixture()
        for uid, args in [(501, ['enroll']), (0, ['private-sentinel'])]:
            with mock.patch.object(f.os, 'geteuid', return_value=uid), mock.patch.object(f.os, 'getegid', return_value=0), mock.patch.object(f, 'COLLECTOR_LIB', Path(f.unifi_enroll.__file__).parent), mock.patch.object(sys, 'argv', ['launcher', *args]), mock.patch('sys.stdout', new_callable=io.StringIO) as output:
                self.assertEqual(2, f.main())
                self.assertEqual('UNIFI_ENROLL_STEP_FAILED\n', output.getvalue())

    def test_ticket_closed_rejects_generic_failure(self):
        f = load_fixture()
        self.assertTrue(callable(getattr(f, 'ticket_closed', None)), 'revocation proof missing')
        import types
        for code, error, good in [(1, 'sudo: a password is required\n', True),
                                  (1, 'sudo: policy plugin failed\n', False), (124, '', False), (0, '', False)]:
            result = types.SimpleNamespace(returncode=code, stdout='', stderr=error)
            with mock.patch.object(f.subprocess, 'run', return_value=result):
                if good:
                    f.ticket_closed()
                else:
                    with self.assertRaises(RuntimeError):
                        f.ticket_closed()


if __name__ == '__main__':
    unittest.main()
