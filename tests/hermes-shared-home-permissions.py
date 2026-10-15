"""Exercise pinned Hermes permission functions using synthetic homes only.

Usage: python3 tests/hermes-shared-home-permissions.py HERMES_SOURCE_ROOT
AST extraction avoids importing CLI startup or reading real runtime state.
Real fixtures use 0770: the Nix sandbox forbids setting setgid. Separate
no-chmod/no-chown assertions cover preserving existing special bits without
requiring the builder to create them or relaxing its syscall filter.
"""

import ast
import contextlib
import os
from pathlib import Path
import stat
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

SOURCE = Path(sys.argv.pop(1)).resolve()
FUNCTIONS = {
    "secure_parent_dir", "apply_secure_dir_policy", "get_managed_system",
    "_container_or_chmod_skipped", "_resolve_hermes_uid_gid", "_chown_to_hermes_uid",
}
CONSTANTS = {
    "_MANAGED_TRUE_VALUES", "_LEGACY_MANAGED_SYSTEM",
    "_IGNORED_MANAGED_VALUES", "_MANAGED_FALSE_VALUES",
}


def load_policy(home):
    source = SOURCE / "hermes_constants.py"
    parsed = ast.parse(source.read_text())
    selected: list[ast.stmt] = []
    for node in parsed.body:
        if isinstance(node, ast.FunctionDef) and node.name in FUNCTIONS:
            selected.append(node)
        elif isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id in CONSTANTS
            for target in node.targets
        ):
            selected.append(node)
    found = {node.name for node in selected if isinstance(node, ast.FunctionDef)}
    if found != FUNCTIONS:
        raise AssertionError("Pinned permission API changed")
    namespace = {
        "__name__": "hermes_permission_fixture",
        "Path": Path, "contextlib": contextlib, "os": os, "sys": sys,
        "_INSTALL_ROOT": SOURCE, "get_hermes_home": lambda: home,
        "_detect_container": lambda: False,
    }
    future = ast.ImportFrom(
        module="__future__", names=[ast.alias(name="annotations")], level=0,
    )
    module = ast.fix_missing_locations(ast.Module(
        body=[future, *selected], type_ignores=[],
    ))
    exec(compile(module, str(source), "exec"), namespace)
    return namespace


class SharedHomePermissions(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="hermes-policy-test-")
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name) / "home"
        self.home.mkdir()
        self.policy = load_policy(self.home)
        self.environment = patch.dict(os.environ, {}, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def mode(self, path):
        return stat.S_IMODE(path.stat().st_mode)

    def test_managed_home_preserves_declared_shared_permissions(self):
        self.home.chmod(0o770)
        (self.home / ".managed").write_text("nixos\n")
        before = self.mode(self.home)
        self.policy["secure_parent_dir"](self.home / "synthetic-auth.json")
        self.assertEqual(before, self.mode(self.home))
        self.assertEqual(0o770, self.mode(self.home) & 0o777)
        self.assertFalse((self.home / "synthetic-auth.json").exists())

    def test_managed_environment_preserves_active_home(self):
        self.home.chmod(0o770)
        before = self.mode(self.home)
        os.environ["HERMES_MANAGED"] = "nixos"
        self.policy["secure_parent_dir"](self.home / "synthetic.json")
        self.assertEqual(before, self.mode(self.home))

    def test_profile_write_through_preserves_managed_global_home(self):
        global_home = self.home.parent / "managed-global-home"
        global_home.mkdir()
        (global_home / ".managed").write_text("nixos\n")
        global_home.chmod(0o770)
        before = self.mode(global_home)
        self.policy["secure_parent_dir"](global_home / "synthetic-auth.json")
        self.assertEqual(before, self.mode(global_home))

    def test_unmanaged_active_home_is_still_private(self):
        self.home.chmod(0o770)
        self.policy["secure_parent_dir"](self.home / "synthetic.json")
        self.assertEqual(0o700, self.mode(self.home))

    def test_managed_homes_make_no_chmod_or_chown_calls(self):
        for home in [self.home, self.home.parent / "managed-global-home"]:
            with self.subTest(home=home.name):
                home.mkdir(exist_ok=True)
                (home / ".managed").write_text("nixos\n")
                home.chmod(0o770)
                with patch.object(os, "chmod", wraps=os.chmod) as chmod, \
                        patch.object(os, "chown", wraps=os.chown) as chown:
                    self.policy["secure_parent_dir"](home / "synthetic.json")
                    chmod.assert_not_called()
                    chown.assert_not_called()
                self.assertEqual(0o770, self.mode(home))

    def test_explicit_active_home_mode_is_honored(self):
        self.home.chmod(0o770)
        os.environ["HERMES_HOME_MODE"] = "750"
        self.policy["secure_parent_dir"](self.home / "synthetic.json")
        self.assertEqual(0o750, self.mode(self.home))

    def test_managed_choice_does_not_relax_unrelated_parents(self):
        other = self.home.parent / "private-cache"
        other.mkdir(mode=0o770)
        os.environ["HERMES_MANAGED"] = "nixos"
        os.environ["HERMES_HOME_MODE"] = "2770"
        self.policy["secure_parent_dir"](other / "synthetic.json")
        self.assertEqual(0o700, self.mode(other))

    def test_nested_credential_cache_remains_private(self):
        cache = self.home / "credential-cache"
        cache.mkdir(mode=0o770)
        (self.home / ".managed").write_text("nixos\n")
        self.policy["secure_parent_dir"](cache / "synthetic.json")
        self.assertEqual(0o700, self.mode(cache))

    def test_alias_to_active_home_preserves_managed_mode(self):
        alias = self.home.parent / "alias"
        alias.symlink_to(self.home, target_is_directory=True)
        (self.home / ".managed").write_text("nixos\n")
        self.home.chmod(0o770)
        before = self.mode(self.home)
        self.policy["secure_parent_dir"](alias / "synthetic.json")
        self.assertEqual(before, self.mode(self.home))

    def test_root_and_install_tree_guards_remain(self):
        with patch.object(os, "chmod") as chmod, self.assertLogs(level="WARNING"):
            for target in [Path("/synthetic.json"), SOURCE / "synthetic.json",
                           SOURCE / "nested" / "synthetic.json"]:
                self.policy["secure_parent_dir"](target)
            chmod.assert_not_called()

    def test_install_prefix_sibling_is_not_exempt(self):
        sibling = Path(str(SOURCE) + "-private-cache")
        with patch.object(os, "chmod") as chmod:
            self.policy["secure_parent_dir"](sibling / "synthetic.json")
            chmod.assert_called_once_with(sibling, 0o700)

    def test_auth_writer_still_requests_owner_only_file_mode(self):
        parsed = ast.parse((SOURCE / "hermes_cli" / "auth.py").read_text())
        writer = next(node for node in parsed.body
                      if isinstance(node, ast.FunctionDef)
                      and node.name == "_save_private_json")
        namespace = dict(self.policy)
        namespace["Any"] = object
        constants = types.ModuleType("hermes_constants")
        constants.__dict__["mkdir_under_hermes_home"] = lambda path: path.mkdir(exist_ok=True)
        with patch.dict(sys.modules, {"hermes_constants": constants}), \
                patch.dict(namespace, {"atomic_json_write": Mock()}):
            exec(compile(ast.Module(body=[writer], type_ignores=[]),
                         str(SOURCE / "hermes_cli" / "auth.py"), "exec"), namespace)
            (self.home / ".managed").write_text("nixos\n")
            self.home.chmod(0o770)
            before = self.mode(self.home)
            target = self.home / "synthetic-auth.json"
            namespace["_save_private_json"](target, {"synthetic": True})
            namespace["atomic_json_write"].assert_called_once_with(
                target, {"synthetic": True}, mode=0o600, fsync_dir=False,
            )
            self.assertEqual(before, self.mode(self.home))
            self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
