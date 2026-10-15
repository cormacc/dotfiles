{ lib, options, pkgs, ... }:

let
  homelabAgentRepo = ../../sources/homelab-agent;
  # Patch the Python leaf, not the assembled wrapper. Keep the pinned input and
  # other hosts unchanged; append after upstream's workspace overlays. Remove
  # this bridge when upstream exposes a direct Python override argument.
  patchedHermes = options.services.hermes-agent.package.default.override (args:
    let
      upstream = args.pyproject-nix;
      patchHermes = _final: prev:
        lib.optionalAttrs (prev ? hermes-agent) {
          hermes-agent = prev.hermes-agent.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [
              ./patches/hermes-shared-home-permissions.patch
            ];
          });
        };
    in {
      pyproject-nix = upstream // {
        build = upstream.build // {
          packages = lib.setFunctionArgs
            (buildArgs:
              let scope = upstream.build.packages buildArgs;
              in scope // {
                overrideScope = overlays:
                  scope.overrideScope
                    (lib.composeExtensions overlays patchHermes);
              })
            (builtins.functionArgs upstream.build.packages);
        };
      };
    });
  # Install collector scripts from the homelab-agent repo into
  # libexec/homelab-<name>/ and byte-compile them as a syntax check.
  mkCollector = name: scripts:
    let dir = "$out/libexec/homelab-${name}";
    in pkgs.runCommand "homelab-${name}-collector" { } ''
      ${lib.concatMapStrings (s: ''
        install -Dm0555 ${homelabAgentRepo}/scripts/${s} ${dir}/${s}
      '') scripts}
      ${pkgs.python3}/bin/python3 -m py_compile \
        ${lib.concatMapStringsSep " " (s: "${dir}/${s}") scripts}
    '';
  healthCollector = mkCollector "health" [ "health_snapshot.py" "watch_health.py" ];
  emptyInventory = pkgs.writeText "homelab-empty-inventory.json" ''
    { "version": 1, "hosts": [] }
  '';
in {
  services.hermes-agent = {
    enable = true;
    package = patchedHermes;
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

    # Source-owned identity, reinstalled on activation. Keep operator facts and
    # inventory out of this file; do not declaratively overwrite mutable memory.
    hermesHomeFiles."SOUL.md" = ''
      # Homelab operations assistant

      You are the operator's homelab operations assistant. Prefer observation
      and diagnosis before intervention. Be direct, evidence-based, and honest
      about uncertainty; distinguish verified results from assumptions.

      Follow /opt/homelab-agent/AGENTS.md and the runbooks in
      /opt/homelab-agent/runbooks for project-specific operating rules. Require
      the applicable approval before mutations, and verify outcomes before
      claiming success. Preserve operator data and keep secrets private.
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
