from pathlib import Path
import json
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
FLAKE = ROOT / "flake.nix"
GITMODULES = ROOT / ".gitmodules"
AGENT_MODULE = ROOT / "hosts" / "odroid-h4" / "homelab-agent.nix"
COMPOSE_MODULE = ROOT / "hosts" / "odroid-h4" / "homelab-compose.nix"
HEALTH_DIR = ROOT / "hosts" / "odroid-h4" / "homelab-health"
HOMELAB_SOURCE = ROOT / "sources" / "homelab-agent"
EXPECTED_HOMELAB_REVISION = "05210ea8b99d3930a712ddc35ba6d04c2ad275b9"


class HomelabAgentSourceTests(unittest.TestCase):
    def git(self, *args: str, cwd: Path = ROOT) -> str:
        return subprocess.run(
            ["git", "-C", str(cwd), *args],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def test_dotfiles_owns_the_homelab_source_submodule(self):
        flake = FLAKE.read_text(encoding="utf-8")
        gitmodules = GITMODULES.read_text(encoding="utf-8")

        self.assertIn('[submodule "sources/homelab-agent"]', gitmodules)
        self.assertIn("path = sources/homelab-agent", gitmodules)
        self.assertIn("url = git@github.com:cormacc/homelab-agent.git", gitmodules)
        self.assertIn("self.submodules = true;", flake)

    def test_gitlink_pins_the_expected_pushed_revision(self):
        mode, revision, _stage, path = self.git(
            "ls-files", "--stage", "sources/homelab-agent"
        ).split()

        self.assertEqual("160000", mode)
        self.assertEqual(EXPECTED_HOMELAB_REVISION, revision)
        self.assertEqual("sources/homelab-agent", path)
        self.assertEqual(EXPECTED_HOMELAB_REVISION, self.git("rev-parse", "HEAD", cwd=HOMELAB_SOURCE))
        self.assertEqual(
            EXPECTED_HOMELAB_REVISION,
            self.git("rev-parse", "refs/remotes/origin/main", cwd=HOMELAB_SOURCE),
        )

    def test_pinned_compose_restart_policy_cannot_bypass_systemd_gate(self):
        compose_paths = sorted((HOMELAB_SOURCE / "services").glob("*/compose.yaml"))
        compose_paths.append(HOMELAB_SOURCE / "monitoring" / "docker-compose.yml")

        self.assertGreater(len(compose_paths), 1)
        for path in compose_paths:
            with self.subTest(path=path.relative_to(HOMELAB_SOURCE)):
                restart_policies = re.findall(
                    r'^\s+restart:\s+(.+)$',
                    path.read_text(encoding="utf-8"),
                    flags=re.MULTILINE,
                )
                self.assertTrue(restart_policies, path)
                self.assertEqual({'"no"'}, set(restart_policies), path)

    def test_accepted_compose_projects_autostart_declaratively(self):
        flake_url = json.dumps(f"path:{ROOT}")
        expression = f"""
          let
            flake = builtins.getFlake {flake_url};
            services = flake.nixosConfigurations.nas.config.systemd.services;
            names = builtins.filter (
              name:
                builtins.match
                  "Homelab Compose project: .*"
                  (services.${{name}}.description or "") != null
            ) (builtins.attrNames services);
          in
            builtins.listToAttrs (builtins.map (name: {{
              inherit name;
              value = services.${{name}}.wantedBy;
            }}) names)
        """
        actual = json.loads(
            subprocess.run(
                ["nix", "eval", "--json", "--impure", "--expr", expression],
                check=True,
                capture_output=True,
                text=True,
                cwd=ROOT,
            ).stdout
        )
        expected = {
            "homelab-compose-traefik": ["multi-user.target"],
            "homelab-compose-sabnzbd": ["multi-user.target"],
            "homelab-compose-sonarr": ["multi-user.target"],
            "homelab-compose-radarr": ["multi-user.target"],
            "homelab-compose-syncthing": ["multi-user.target"],
            "homelab-compose-monitoring": ["multi-user.target"],
        }
        self.assertEqual(expected, actual)

    def test_managed_applications_require_explicit_one_service_restarts(self):
        flake_url = json.dumps(f"path:{ROOT}")
        expression = f"""
          let
            flake = builtins.getFlake {flake_url};
            services = flake.nixosConfigurations.nas.config.systemd.services;
            composeNames = builtins.filter (
              name:
                builtins.match
                  "Homelab Compose project: .*"
                  (services.${{name}}.description or "") != null
            ) (builtins.attrNames services);
            names = [ "hermes-agent" ] ++ composeNames;
          in
            builtins.listToAttrs (builtins.map (name: {{
              inherit name;
              value = {{
                inherit (services.${{name}})
                  restartIfChanged
                  stopIfChanged
                  wantedBy;
              }};
            }}) names)
        """
        actual = json.loads(
            subprocess.run(
                ["nix", "eval", "--json", "--impure", "--expr", expression],
                check=True,
                capture_output=True,
                text=True,
                cwd=ROOT,
            ).stdout
        )

        self.assertEqual(
            {
                name: {
                    "restartIfChanged": False,
                    "stopIfChanged": True,
                    "wantedBy": ["multi-user.target"],
                }
                for name in (
                    "hermes-agent",
                    "homelab-compose-traefik",
                    "homelab-compose-sabnzbd",
                    "homelab-compose-sonarr",
                    "homelab-compose-radarr",
                    "homelab-compose-syncthing",
                    "homelab-compose-monitoring",
                )
            },
            actual,
        )

    def test_nas_uses_immutable_homelab_source_not_a_home_checkout(self):
        agent = AGENT_MODULE.read_text(encoding="utf-8")
        compose = COMPOSE_MODULE.read_text(encoding="utf-8")
        combined = agent + compose

        self.assertNotIn("/home/cormacc/homelab-agent", combined)
        self.assertIn("homelabAgentRepo = ../../sources/homelab-agent;", agent)
        self.assertIn('"${homelabAgentRepo}:/opt/homelab-agent:ro"', agent)
        self.assertIn("homelabAgentRepo = ../../sources/homelab-agent;", compose)
        self.assertIn("repoRoot = homelabAgentRepo;", compose)

    def test_health_collectors_come_from_locked_homelab_source(self):
        agent = AGENT_MODULE.read_text(encoding="utf-8")

        self.assertIn("${homelabAgentRepo}/scripts/health_snapshot.py", agent)
        self.assertIn("${homelabAgentRepo}/scripts/watch_health.py", agent)
        self.assertFalse((HEALTH_DIR / "health_snapshot.py").exists())
        self.assertFalse((HEALTH_DIR / "watch_health.py").exists())

    def test_unifi_collectors_come_from_locked_homelab_source(self):
        agent = AGENT_MODULE.read_text(encoding="utf-8")

        self.assertIn("${homelabAgentRepo}/scripts/unifi_snapshot.py", agent)
        self.assertIn("${homelabAgentRepo}/scripts/watch_unifi.py", agent)
        self.assertIn(
            'LoadCredential = [ "unifi-api-key:/var/lib/homelab-unifi/api-key" ];',
            agent,
        )
        self.assertIn('"$CREDENTIALS_DIRECTORY/unifi-api-key"', agent)
        self.assertIn("--config /var/lib/homelab-unifi/config.json", agent)
        self.assertIn("--state /var/lib/homelab-unifi-state/health.json", agent)
        self.assertIn(
            '"C /var/lib/homelab-unifi/config.json 0440 root homelab-health - ${disabledUnifiConfig}"',
            agent,
        )

    def test_unifi_service_is_hardened_and_declaratively_disabled(self):
        flake_url = json.dumps(f"path:{ROOT}")
        expression = f"""
          let
            flake = builtins.getFlake {flake_url};
            services = flake.nixosConfigurations.nas.config.systemd.services;
            timers = flake.nixosConfigurations.nas.config.systemd.timers;
            service = services.homelab-unifi-watch or null;
            timer = timers.homelab-unifi-watch or null;
          in
            if service == null || timer == null then null else {{
              service = {{
                inherit (service) wantedBy restartIfChanged stopIfChanged;
                serviceConfig = {{
                  inherit (service.serviceConfig)
                    BindReadOnlyPaths
                    Group
                    InaccessiblePaths
                    LoadCredential
                    NoNewPrivileges
                    ProtectSystem
                    StateDirectory
                    StateDirectoryMode
                    User;
                }};
              }};
              timer = {{
                inherit (timer) wantedBy;
                inherit (timer.timerConfig) Unit;
              }};
            }}
        """
        actual = json.loads(
            subprocess.run(
                ["nix", "eval", "--json", "--impure", "--expr", expression],
                check=True,
                capture_output=True,
                text=True,
                cwd=ROOT,
            ).stdout
        )

        self.assertEqual(
            {
                "service": {
                    "wantedBy": [],
                    "restartIfChanged": False,
                    "stopIfChanged": True,
                    "serviceConfig": {
                        "BindReadOnlyPaths": [
                            "/var/lib/homelab-unifi/hosts:/etc/hosts"
                        ],
                        "Group": "homelab-health",
                        "InaccessiblePaths": [
                            "-/var/lib/hermes",
                            "/run/nscd/socket",
                        ],
                        "LoadCredential": [
                            "unifi-api-key:/var/lib/homelab-unifi/api-key"
                        ],
                        "NoNewPrivileges": True,
                        "ProtectSystem": "strict",
                        "StateDirectory": "homelab-unifi-state",
                        "StateDirectoryMode": "0700",
                        "User": "homelab-health",
                    },
                },
                "timer": {
                    "wantedBy": [],
                    "Unit": "homelab-unifi-watch.service",
                },
            },
            actual,
        )

        agent = AGENT_MODULE.read_text(encoding="utf-8")
        self.assertIn(
            '"/var/lib/homelab-unifi/hosts:/etc/hosts"',
            agent,
        )
        self.assertIsNone(re.search(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", agent))

    def test_monitoring_secret_stays_outside_immutable_source(self):
        compose = COMPOSE_MODULE.read_text(encoding="utf-8")

        self.assertNotIn('${repoRoot}/monitoring/.env', compose)
        self.assertIn(
            'monitoringEnvironmentFile = "/var/lib/homelab-monitoring/grafana.env";',
            compose,
        )
        self.assertIn(
            '"d /var/lib/homelab-monitoring 0700 cormacc users - -"',
            compose,
        )
        self.assertIn("environmentFile = monitoringEnvironmentFile;", compose)


if __name__ == "__main__":
    unittest.main()
