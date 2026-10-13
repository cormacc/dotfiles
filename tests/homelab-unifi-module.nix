{ config, modulePath, pkgs }:

let
  service = config.systemd.services.homelab-unifi-watch;
  timer = config.systemd.timers.homelab-unifi-watch;
  serviceConfig = service.serviceConfig;
  unifiTmpfiles = builtins.filter
    (rule: pkgs.lib.hasInfix "/var/lib/homelab-unifi" rule)
    config.systemd.tmpfiles.rules;
in
assert builtins.pathExists modulePath;
assert config.services.hermes-agent.workingDirectory == "/var/lib/hermes/workspace";
assert config.services.hermes-agent.settings.terminal.cwd == "/opt/homelab-agent";
assert config.systemd.services.hermes-agent.restartIfChanged == false;
assert builtins.length unifiTmpfiles == 2;
assert builtins.elem "d /var/lib/homelab-unifi 0750 root homelab-health - -" unifiTmpfiles;
assert builtins.any
  (rule: builtins.match "C /var/lib/homelab-unifi/config[.]json 0440 root homelab-health - /nix/store/[a-z0-9]+-homelab-unifi-disabled[.]json" rule != null)
  unifiTmpfiles;
assert service.wantedBy == [ ];
assert service.after == [ "network-online.target" ];
assert service.wants == [ "network-online.target" ];
assert service.restartIfChanged == false;
assert service.stopIfChanged == true;
assert serviceConfig.Type == "oneshot";
assert serviceConfig.User == "homelab-health";
assert serviceConfig.Group == "homelab-health";
assert serviceConfig.LoadCredential == [ "unifi-api-key:/var/lib/homelab-unifi/api-key" ];
assert serviceConfig.StateDirectory == "homelab-unifi-state";
assert serviceConfig.StateDirectoryMode == "0700";
assert serviceConfig.UMask == "0077";
assert serviceConfig.NoNewPrivileges == true;
assert serviceConfig.PrivateTmp == true;
assert serviceConfig.ProtectSystem == "strict";
assert serviceConfig.ProtectHome == "read-only";
assert serviceConfig.BindReadOnlyPaths == [ "/var/lib/homelab-unifi/hosts:/etc/hosts" ];
assert serviceConfig.InaccessiblePaths == [
  "-/var/lib/hermes"
  "/run/nscd/socket"
];
assert serviceConfig.ReadWritePaths == [ "/var/lib/homelab-unifi-state" ];
assert pkgs.lib.hasInfix
  (builtins.unsafeDiscardStringContext
    "${config.system.build.homelabUnifiCollector}/libexec/homelab-unifi/watch_unifi.py")
  service.script;
assert pkgs.lib.hasInfix "--config /var/lib/homelab-unifi/config.json" service.script;
assert pkgs.lib.hasInfix ''--credential-file "$CREDENTIALS_DIRECTORY/unifi-api-key"'' service.script;
assert pkgs.lib.hasInfix "--state /var/lib/homelab-unifi-state/health.json" service.script;
assert !(pkgs.lib.hasInfix "unifi_enroll.py" service.script);
assert timer.wantedBy == [ ];
assert timer.timerConfig.OnBootSec == "2min";
assert timer.timerConfig.OnUnitActiveSec == "5min";
assert timer.timerConfig.RandomizedDelaySec == "20s";
assert timer.timerConfig.Persistent == true;
assert timer.timerConfig.Unit == "homelab-unifi-watch.service";
pkgs.runCommand "homelab-unifi-module-contract" { } ''
  for script in unifi_snapshot.py watch_unifi.py unifi_enroll.py; do
    test -x ${config.system.build.homelabUnifiCollector}/libexec/homelab-unifi/$script
  done
  touch "$out"
''
