from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "hosts" / "odroid-h4" / "homelab-compose.nix"


class HomelabBackupTests(unittest.TestCase):
    def test_non_zfs_root_is_never_force_imported(self):
        text = MODULE.read_text(encoding="utf-8")
        self.assertIn("boot.zfs.forceImportRoot = false;", text)

    def test_zfs_snapshot_backup_traverses_snapshot_filesystem(self):
        text = MODULE.read_text(encoding="utf-8")
        backup_start = text.index('${pkgs.restic}/bin/restic -r "$local_repo" backup')
        backup_end = text.index('${pkgs.restic}/bin/restic -r "$mfs_repo" copy', backup_start)
        backup_command = text[backup_start:backup_end]

        self.assertIn("''${sources[@]}", backup_command)
        self.assertNotIn("--one-file-system", backup_command)


if __name__ == "__main__":
    unittest.main()
