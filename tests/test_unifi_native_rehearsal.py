import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1] / "sources/homelab-agent/scripts"
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location(
    "native_rehearsal", Path(__file__).parent / "fixtures/unifi_native_rehearsal.py"
)
assert SPEC is not None and SPEC.loader is not None
fixture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fixture)


class Terminal(io.StringIO):
    def __init__(self, response):
        super().__init__()
        self.response = io.StringIO(response)

    def readline(self, size=-1):
        return self.response.readline(size)

    def isatty(self):
        return True


class RehearsalTests(unittest.TestCase):
    def test_revocation_requires_password_required_not_arbitrary_sudo_failure(self):
        self.assertTrue(callable(getattr(fixture, "ticket_closed", None)))
        for code, error, accepted in [(1, "sudo: a password is required\n", True),
                                      (0, "", False), (1, "sudo: policy plugin failed\n", False),
                                      (124, "", False)]:
            result = types.SimpleNamespace(returncode=code, stdout="", stderr=error)
            with mock.patch.object(fixture.subprocess, "run", return_value=result):
                if accepted:
                    fixture.ticket_closed()
                else:
                    with self.assertRaises(RuntimeError):
                        fixture.ticket_closed()

    def test_cleanup_rejects_public_or_symlinked_known_file_without_deleting(self):
        for variant in ["public", "symlink", "fifo", "wrong-json"]:
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as tmp:
                state = Path(tmp).resolve() / "state"
                state.mkdir(mode=0o700)
                path = state / "candidate.json"
                if variant == "symlink":
                    path.symlink_to(Path(tmp).resolve() / "outside")
                elif variant == "fifo":
                    os.mkfifo(path, 0o600)
                else:
                    path.write_text(json.dumps(fixture.CANDIDATE if variant == "public" else {}))
                    path.chmod(0o644 if variant == "public" else 0o600)
                with mock.patch.object(fixture, "STATE", state), self.assertRaises((RuntimeError, OSError)):
                    fixture.cleanup()
                self.assertTrue(os.path.lexists(path))

    def test_record_schema_rejects_ambiguous_or_duplicate_process_ids(self):
        valid = {"pids": [[12345, 100], [12346, 101]], "started": 100.0}
        fixture.validate_record(valid)
        for bad in [None, {**valid, "extra": 1}, {**valid, "started": float("nan")},
                    {**valid, "pids": [[1, 100], [2, 101]]},
                    {**valid, "pids": [[True, 100], [2, 101]]},
                    {**valid, "pids": [[12345, 100], [12345, 101]]}]:
            with self.subTest(record=bad), self.assertRaises(RuntimeError):
                fixture.validate_record(bad)

    def test_main_denies_nonroot_without_reading_synthetic_or_real_inputs(self):
        with mock.patch.object(fixture.os, "geteuid", return_value=1000), mock.patch.object(
            fixture, "probe"
        ) as probe, mock.patch.object(fixture.sys, "argv", ["probe", "probe"]), mock.patch(
            "sys.stdout", new_callable=io.StringIO
        ) as output:
            self.assertEqual(2, fixture.main())
        self.assertEqual("UNIFI_REHEARSAL_STEP_FAILED\n", output.getvalue())
        probe.assert_not_called()

    def test_negative_verification_requires_timeout_and_no_live_descendants(self):
        self.assertTrue(callable(getattr(fixture, "verify_negative", None)))
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp).resolve() / "state"
            state.mkdir(mode=0o700)
            fixture.unifi_enroll.write_candidate(state / "candidate.json", fixture.CANDIDATE)
            record = {"pids": [[12345, 100], [12346, 101]], "started": 100.0}
            (state / "pids.json").write_text(json.dumps(record))
            (state / "pids.json").chmod(0o600)
            properties = {"Result": "timeout", "ExecMainStatus": "9", "TimeoutStartUSec": "2s", "TimeoutStopUSec": "1s", "KillMode": "control-group", "SendSIGKILL": "yes", "KillSignal": "15", "FinalKillSignal": "9"}
            with mock.patch.object(fixture, "STATE", state), mock.patch.object(
                fixture, "unit_properties", return_value=properties
            ), mock.patch.object(fixture, "process_start", return_value=None), mock.patch.object(
                fixture, "cgroup_empty", return_value=True
            ), mock.patch.object(fixture.time, "monotonic", return_value=103.0):
                fixture.verify_negative()
                with mock.patch.object(fixture, "process_start", return_value=(100, "S")), self.assertRaises(RuntimeError):
                    fixture.verify_negative()
                with mock.patch.object(fixture, "unit_properties", return_value={**properties, "Result": "success"}), self.assertRaises(RuntimeError):
                    fixture.verify_negative()

    def test_cleanup_removes_only_valid_synthetic_files(self):
        self.assertTrue(callable(getattr(fixture, "cleanup", None)))
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp).resolve() / "state"
            state.mkdir(mode=0o700)
            fixture.unifi_enroll.write_candidate(state / "candidate.json", fixture.CANDIDATE)
            with mock.patch.object(fixture, "STATE", state):
                fixture.cleanup()
            self.assertFalse(state.exists())

    def test_cleanup_preserves_directory_with_unexpected_entry(self):
        self.assertTrue(callable(getattr(fixture, "cleanup", None)))
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp).resolve() / "state"
            state.mkdir(mode=0o700)
            fixture.unifi_enroll.write_candidate(state / "candidate.json", fixture.CANDIDATE)
            (state / "unexpected").write_text("preserve")
            with mock.patch.object(fixture, "STATE", state), self.assertRaises(RuntimeError):
                fixture.cleanup()
            self.assertTrue((state / "candidate.json").is_file())
            self.assertEqual("preserve", (state / "unexpected").read_text())

    def test_probe_uses_only_synthetic_inputs_and_private_candidate(self):
        self.assertTrue(callable(getattr(fixture, "probe", None)))
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp).resolve() / "state"
            state.mkdir(mode=0o700)
            hosts = Path(tmp).resolve() / "hosts"
            hosts.write_text("127.0.0.1 localhost\n192.0.2.23 unifi-rehearsal.invalid\n")
            terminal = Terminal("rehearsal-ok\n")
            with mock.patch.multiple(fixture, STATE=state, HOSTS=hosts, MOUNTED_HOSTS=hosts), mock.patch.object(
                fixture.socket, "getaddrinfo", return_value=[(2, 1, 6, "", ("192.0.2.23", 443))]
            ), mock.patch.object(fixture, "network_is_private", return_value=True), mock.patch.object(
                fixture.unifi_enroll, "_open_private_terminal", return_value=terminal
            ), mock.patch.object(fixture.unifi_enroll.unifi_snapshot, "read_credential") as key, mock.patch.object(
                fixture.unifi_enroll.unifi_snapshot, "UniFiClient"
            ) as client:
                fixture.probe()
            self.assertEqual(fixture.CANDIDATE, json.loads((state / "candidate.json").read_text()))
            self.assertEqual(0o600, (state / "candidate.json").stat().st_mode & 0o777)
            self.assertEqual(["candidate.json"], sorted(p.name for p in state.iterdir()))
            key.assert_not_called()
            client.assert_not_called()


if __name__ == "__main__":
    unittest.main()
