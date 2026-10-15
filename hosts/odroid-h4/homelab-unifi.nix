{ pkgs, ... }:

let
  homelabAgentRepo = ../../sources/homelab-agent;
  unifiCollector = pkgs.runCommand "homelab-unifi-collector" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    install -Dm0555 ${homelabAgentRepo}/scripts/unifi_snapshot.py \
      $out/libexec/homelab-unifi/unifi_snapshot.py
    install -Dm0555 ${homelabAgentRepo}/scripts/watch_unifi.py \
      $out/libexec/homelab-unifi/watch_unifi.py
    install -Dm0555 ${homelabAgentRepo}/scripts/unifi_enroll.py \
      $out/libexec/homelab-unifi/unifi_enroll.py
    ${pkgs.python3}/bin/python3 -m py_compile \
      $out/libexec/homelab-unifi/unifi_snapshot.py \
      $out/libexec/homelab-unifi/watch_unifi.py \
      $out/libexec/homelab-unifi/unifi_enroll.py
  '';
  disabledUnifiConfig = pkgs.writeText "homelab-unifi-disabled.json" ''
    { "version": 1, "enabled": false }
  '';
in {
  # Expose the immutable package for focused builds and acceptance checks.
  # This does not add an enrollment service or authorize private discovery.
  system.build.homelabUnifiCollector = unifiCollector;

  systemd.tmpfiles.rules = [
    "d /var/lib/homelab-unifi 0750 root homelab-health - -"
    "C /var/lib/homelab-unifi/config.json 0440 root homelab-health - ${disabledUnifiConfig}"
  ];

  # Install UniFi collection without enabling periodic execution. The first
  # credentialed run is supervised; autostart is accepted in a later change.
  systemd.services.homelab-unifi-watch = {
    description = "Read-only UniFi Network health transition check";
    wantedBy = [ ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    restartIfChanged = false;
    stopIfChanged = true;
    serviceConfig = {
      Type = "oneshot";
      User = "homelab-health";
      Group = "homelab-health";
      LoadCredential = [ "unifi-api-key:/var/lib/homelab-unifi/api-key" ];
      StateDirectory = "homelab-unifi-state";
      StateDirectoryMode = "0700";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      InaccessiblePaths = [
        "-/var/lib/hermes"
        "/run/nscd/socket"
      ];
      BindReadOnlyPaths = [ "/var/lib/homelab-unifi/hosts:/etc/hosts" ];
      ReadWritePaths = [ "/var/lib/homelab-unifi-state" ];
    };
    script = ''
      exec ${pkgs.python3}/bin/python3 \
        ${unifiCollector}/libexec/homelab-unifi/watch_unifi.py \
        --config /var/lib/homelab-unifi/config.json \
        --credential-file "$CREDENTIALS_DIRECTORY/unifi-api-key" \
        --state /var/lib/homelab-unifi-state/health.json
    '';
  };

  systemd.timers.homelab-unifi-watch = {
    description = "Run read-only UniFi health checks every five minutes";
    wantedBy = [ ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      RandomizedDelaySec = "20s";
      Persistent = true;
      Unit = "homelab-unifi-watch.service";
    };
  };
}
