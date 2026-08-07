import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FLAKE = ROOT / "flake.nix"
MODULE = ROOT / "hosts" / "odroid-h4" / "sudo-authorization.nix"


class NasSudoAuthorizationTests(unittest.TestCase):
    def test_nas_imports_a_host_local_sudo_policy(self):
        flake = FLAKE.read_text(encoding="utf-8")

        self.assertTrue(MODULE.is_file())
        self.assertEqual(1, flake.count("./hosts/odroid-h4/sudo-authorization.nix"))
        nas_start = flake.index("nas = nixpkgs.lib.nixosSystem")
        nas_end = flake.index("homeConfigurations =", nas_start)
        self.assertIn(
            "./hosts/odroid-h4/sudo-authorization.nix",
            flake[nas_start:nas_end],
        )

    def test_evaluated_policy_is_short_global_and_password_backed(self):
        expression = f"""
          let
            flake = builtins.getFlake {json.dumps(f'path:{ROOT}')};
            sudo = flake.nixosConfigurations.nas.config.security.sudo;
          in {{
            inherit (sudo) extraConfig extraRules wheelNeedsPassword;
          }}
        """
        sudo = json.loads(subprocess.run(
            ["nix", "eval", "--json", "--impure", "--expr", expression],
            cwd=ROOT,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        ).stdout)

        cormacc_timestamp_lines = [
            line.strip()
            for line in sudo["extraConfig"].splitlines()
            if line.strip().startswith("Defaults:cormacc timestamp_")
        ]
        self.assertEqual(
            [
                "Defaults:cormacc timestamp_type=global",
                "Defaults:cormacc timestamp_timeout=5",
            ],
            cormacc_timestamp_lines,
        )
        self.assertTrue(sudo["wheelNeedsPassword"])
        self.assertEqual(
            [
                {
                    "commands": [{"command": "ALL", "options": ["SETENV"]}],
                    "groups": [],
                    "host": "ALL",
                    "runAs": "ALL:ALL",
                    "users": ["root"],
                },
                {
                    "commands": [{"command": "ALL", "options": ["SETENV"]}],
                    "groups": ["wheel"],
                    "host": "ALL",
                    "runAs": "ALL:ALL",
                    "users": [],
                },
            ],
            sudo["extraRules"],
        )
        self.assertNotIn("NOPASSWD", json.dumps(sudo, sort_keys=True))


if __name__ == "__main__":
    unittest.main()
