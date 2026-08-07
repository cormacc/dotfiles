{ pkgs, ... }:

let
  homelabAgentRepo = ../../sources/homelab-agent;
  healthCollector = pkgs.runCommand "homelab-health-collector" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    install -Dm0555 ${homelabAgentRepo}/scripts/health_snapshot.py \
      $out/libexec/homelab-health/health_snapshot.py
    install -Dm0555 ${homelabAgentRepo}/scripts/watch_health.py \
      $out/libexec/homelab-health/watch_health.py
    ${pkgs.python3}/bin/python3 -m py_compile \
      $out/libexec/homelab-health/health_snapshot.py \
      $out/libexec/homelab-health/watch_health.py
  '';
  emptyInventory = pkgs.writeText "homelab-empty-inventory.json" ''
    { "version": 1, "hosts": [] }
  '';
in {
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;

    # The managed container gives the operations agent a mutable tool runtime
    # while NixOS remains declarative.  The reviewed homelab Gitlink revision is
    # materialized by Nix and mounted read-only from the Nix store;
    # SSH development checkouts are never production inputs.
    container = {
      enable = true;
      backend = "docker";
      hostUsers = [ "cormacc" ];
      extraVolumes = [
        "${homelabAgentRepo}:/opt/homelab-agent:ro"
      ];
    };

    settings = {
      model = {
        default = "gpt-5.6-sol";
        provider = "openai-codex";
      };
      approvals = {
        mode = "smart";
        cron_mode = "deny";
      };
      security.redact_secrets = true;
      terminal = {
        backend = "local";
        cwd = "/opt/homelab-agent";
        timeout = 180;
      };
      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
      };
      checkpoints.enabled = true;
    };

    extraPackages = with pkgs; [
      curl
      git
      jq
      openssh
      rsync
    ];

    documents."USER.md" = ''
      # Homelab operator context

      This agent maintains a private home network consisting of a UniFi Dream
      Machine Pro and access points, a MooseFS SBC storage cluster, two Intel
      service servers, Home Assistant on Raspberry Pi, an AMD Strix Halo
      Framework Desktop, and an NVIDIA DGX Spark.

      Start in observation mode. Follow /opt/homelab-agent/AGENTS.md and the
      runbooks in /opt/homelab-agent/runbooks. Never perform a mutating action
      without its required approval and verification steps.
    '';
  };

  # Keep NixOS activation from restarting Hermes alongside application units.
  # Restart and verify it as its own supervised maintenance step.
  systemd.services.hermes-agent.restartIfChanged = false;

  # Deterministic checks run independently of the LLM. A degraded snapshot is
  # recorded and reported to the journal but does not make the oneshot unit
  # fail; collector/configuration errors do fail the unit.
  users.groups.homelab-health = { };
  users.users.homelab-health = {
    isSystemUser = true;
    group = "homelab-health";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/homelab-agent 0750 homelab-health homelab-health - -"
    "C /var/lib/homelab-agent/hosts.json 0640 homelab-health homelab-health - ${emptyInventory}"
  ];

  systemd.services.homelab-health = {
    description = "Homelab deterministic health transition check";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "homelab-health";
      Group = "homelab-health";
      StateDirectory = "homelab-agent";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      InaccessiblePaths = [ "-/var/lib/hermes" ];
      ReadWritePaths = [ "/var/lib/homelab-agent" ];
    };
    script = ''
      set +e
      output="$(${pkgs.python3}/bin/python3 \
        ${healthCollector}/libexec/homelab-health/watch_health.py \
        --inventory /var/lib/homelab-agent/hosts.json \
        --state /var/lib/homelab-agent/health.json 2>&1)"
      status=$?
      if [ -n "$output" ]; then
        printf '%s\n' "$output"
      fi
      case "$status" in
        0|1) exit 0 ;;
        *) exit "$status" ;;
      esac
    '';
  };

  systemd.timers.homelab-health = {
    description = "Run homelab health checks every five minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      RandomizedDelaySec = "20s";
      Persistent = true;
      Unit = "homelab-health.service";
    };
  };
}
