{ config, lib, pkgs, ... }:

let
  repoRoot = "/home/cormacc/homelab-agent";
  stateRoot = "/data/services";
  backupPoolGuid = "18052638822605016933";
  moosefsSource = "mfs#mfsmaster:9421";
  compose = "${pkgs.docker-compose}/bin/docker-compose";

  verifyMount = pkgs.writeShellApplication {
    name = "verify-homelab-mount";
    runtimeInputs = [ pkgs.util-linux ];
    text = ''
      set -euo pipefail
      readonly path="$1"
      readonly expected_source="$2"
      readonly expected_fstype="$3"
      actual_source="$(findmnt -n -o SOURCE --target "$path")"
      actual_fstype="$(findmnt -n -o FSTYPE --target "$path")"
      if [ "$expected_source" != - ] && [ "$actual_source" != "$expected_source" ]; then
        echo "$path source is $actual_source, expected $expected_source" >&2
        exit 1
      fi
      if [ "$actual_fstype" != "$expected_fstype" ]; then
        echo "$path filesystem is $actual_fstype, expected $expected_fstype" >&2
        exit 1
      fi
    '';
  };

  verifyComposeContainer = pkgs.writeShellApplication {
    name = "verify-homelab-compose-container";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      set -euo pipefail

      readonly container="$1"
      readonly expected_source="$2"
      readonly expected_destination="$3"
      readonly port="$4"

      for _attempt in $(seq 1 30); do
        inspect="$(docker inspect "$container" 2>/dev/null || true)"
        if [ -n "$inspect" ] && jq -e '.[0].State.Running == true' <<<"$inspect" >/dev/null; then
          jq -e \
            --arg source "$expected_source" \
            --arg destination "$expected_destination" \
            'any(.[0].Mounts[]; .Source == $source and .Destination == $destination and .RW == true)' \
            <<<"$inspect" >/dev/null

          while IFS= read -r address; do
            code="$(curl --silent --show-error --output /dev/null \
              --write-out '%{http_code}' --max-time 5 \
              "http://$address:$port/" || true)"
            case "$code" in
              1??|2??|3??|4??) exit 0 ;;
            esac
          done < <(jq -r '.[0].NetworkSettings.Networks[]?.IPAddress | select(length > 0)' <<<"$inspect")
        fi
        sleep 2
      done

      echo "verification failed for $container" >&2
      exit 1
    '';
  };

  verifyMonitoring = pkgs.writeShellApplication {
    name = "verify-homelab-monitoring";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      set -euo pipefail
      for _attempt in $(seq 1 30); do
        if curl --fail --silent --show-error --max-time 5 http://127.0.0.1:9090/-/ready >/dev/null \
          && curl --fail --silent --show-error --max-time 5 http://127.0.0.1:9093/-/ready >/dev/null \
          && curl --fail --silent --show-error --max-time 5 http://127.0.0.1:3000/api/health >/dev/null \
          && curl --fail --silent --show-error --max-time 5 http://127.0.0.1:9115/ >/dev/null; then
          exit 0
        fi
        sleep 2
      done
      echo "monitoring readiness verification failed" >&2
      exit 1
    '';
  };

  mkComposeService = {
    project,
    directory ? "${repoRoot}/services/${project}",
    composeFile ? "${directory}/compose.yaml",
    mounts ? [ "${stateRoot}/${project}" ],
    mountChecks ? [
      {
        path = "${stateRoot}/${project}";
        source = "data/services/${project}";
        fstype = "zfs";
      }
    ],
    after ? [ ],
    wants ? [ ],
    requires ? [ ],
    environmentFile ? null,
    verify ? null,
  }:
    let
      mountVerificationCommands = map (check:
        "${verifyMount}/bin/verify-homelab-mount ${lib.escapeShellArgs [ check.path check.source check.fstype ]}"
      ) mountChecks;
      postStartCommands = mountVerificationCommands ++ lib.optional (verify != null) verify;
    in {
      description = "Homelab Compose project: ${project}";
      wantedBy = [ "multi-user.target" ];
      after = [
        "docker.service"
        "network-online.target"
        "homelab-compose-network.service"
      ] ++ after;
      wants = [ "network-online.target" ] ++ wants;
      requires = [
        "docker.service"
        "homelab-compose-network.service"
      ] ++ requires;
      unitConfig.RequiresMountsFor = mounts;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "cormacc";
        Group = "docker";
        WorkingDirectory = directory;
        ExecStartPre = [ "${pkgs.coreutils}/bin/test -r ${composeFile}" ] ++ mountVerificationCommands;
        ExecStart = "${compose} --project-name ${project} --project-directory ${directory} --file ${composeFile} up -d --remove-orphans";
        ExecStop = "${compose} --project-name ${project} --project-directory ${directory} --file ${composeFile} stop --timeout 30";
        TimeoutStartSec = "5min";
        TimeoutStopSec = "2min";
      } // lib.optionalAttrs (environmentFile != null) {
        EnvironmentFile = environmentFile;
      } // lib.optionalAttrs (postStartCommands != [ ]) {
        ExecStartPost = postStartCommands;
      };
    };

  backupServiceState = pkgs.writeShellApplication {
    name = "backup-homelab-service-state";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      moosefs
      restic
      util-linux
      zfs
    ];
    text = ''
      set -euo pipefail

      readonly password_file=/var/lib/homelab-service-backup/restic-password
      readonly local_repo=/backup/restic/nas-services
      readonly mfs_repo=/mnt/mfs/infra/backups/restic/nas-services
      readonly snapshot=homelab-backup
      readonly datasets=(
        data/services/traefik
        data/services/sabnzbd
        data/services/sonarr
        data/services/radarr
      )

      test -r "$password_file"
      test "$(${pkgs.zfs}/bin/zpool get -H -o value guid backup)" = ${backupPoolGuid}
      ${pkgs.util-linux}/bin/mountpoint -q /backup/restic
      ${pkgs.util-linux}/bin/mountpoint -q /mnt/mfs
      test "$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE --target /backup/restic)" = backup/restic
      test "$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE --target /mnt/mfs)" = ${lib.escapeShellArg moosefsSource}
      test "$(${pkgs.util-linux}/bin/findmnt -n -o FSTYPE --target /mnt/mfs)" = fuse

      mfs_json="$(${pkgs.moosefs}/bin/mfscli -H mfsmaster -SIC -j)"
      ${pkgs.jq}/bin/jq -e '
        (.errors | length) == 0 and
        .dataset.info.chunks.summary.allchunks.missing == 0 and
        .dataset.info.chunks.summary.allchunks.endangered == 0 and
        .dataset.info.chunks.summary.allchunks.undergoal == 0
      ' <<<"$mfs_json" >/dev/null

      for dataset in "''${datasets[@]}"; do
        ${pkgs.zfs}/bin/zfs list -H "$dataset" >/dev/null
        expected_mountpoint="/data/services/''${dataset##*/}"
        dataset_mountpoint="$(${pkgs.zfs}/bin/zfs get -H -o value mountpoint "$dataset")"
        test "$dataset_mountpoint" = "$expected_mountpoint"
        ${pkgs.util-linux}/bin/mountpoint -q "$expected_mountpoint"
        test "$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE --target "$expected_mountpoint")" = "$dataset"
        test "$(${pkgs.util-linux}/bin/findmnt -n -o FSTYPE --target "$expected_mountpoint")" = zfs
      done

      export RESTIC_PASSWORD_FILE="$password_file"
      export RESTIC_CACHE_DIR=/var/cache/homelab-service-backup
      ${pkgs.restic}/bin/restic -r "$local_repo" snapshots --no-lock >/dev/null
      ${pkgs.restic}/bin/restic -r "$mfs_repo" snapshots --no-lock >/dev/null

      created_snapshots=()
      cleanup() {
        for created_snapshot in "''${created_snapshots[@]}"; do
          ${pkgs.zfs}/bin/zfs destroy "$created_snapshot" 2>/dev/null || true
        done
      }
      trap cleanup EXIT INT TERM

      sources=()
      for dataset in "''${datasets[@]}"; do
        snapshot_name="$dataset@$snapshot"
        if ${pkgs.zfs}/bin/zfs list -H -t snapshot "$snapshot_name" >/dev/null 2>&1; then
          echo "refusing to replace pre-existing snapshot $snapshot_name" >&2
          exit 1
        fi
      done
      for dataset in "''${datasets[@]}"; do
        snapshot_name="$dataset@$snapshot"
        ${pkgs.zfs}/bin/zfs snapshot "$snapshot_name"
        created_snapshots+=("$snapshot_name")
        expected_mountpoint="/data/services/''${dataset##*/}"
        sources+=("$expected_mountpoint/.zfs/snapshot/$snapshot")
      done

      ${pkgs.restic}/bin/restic -r "$local_repo" backup \
        --host nas \
        --tag homelab-service-state \
        --one-file-system \
        "''${sources[@]}"

      ${pkgs.restic}/bin/restic -r "$mfs_repo" copy \
        --from-repo "$local_repo" \
        --from-password-file "$password_file"

      ${pkgs.restic}/bin/restic -r "$local_repo" check --read-data-subset=1/100
      ${pkgs.restic}/bin/restic -r "$mfs_repo" check --read-data-subset=1/100
    '';
  };
in {
  # The slow three-disk mirror is a backup tier. Pool import and initial
  # dataset/repository creation are supervised one-time maintenance steps.
  boot.zfs.extraPools = [ backupPoolGuid ];

  environment.systemPackages = with pkgs; [
    docker-compose
    python3
    restic
  ];

  systemd.services.homelab-compose-network = {
    description = "Ensure the shared homelab Traefik network exists";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "cormacc";
      Group = "docker";
    };
    script = ''
      if ! ${config.virtualisation.docker.package}/bin/docker network inspect traefik-public >/dev/null 2>&1; then
        ${config.virtualisation.docker.package}/bin/docker network create traefik-public >/dev/null
      fi
    '';
  };

  systemd.services.homelab-compose-traefik = mkComposeService {
    project = "traefik";
    verify = "${verifyComposeContainer}/bin/verify-homelab-compose-container traefik-traefik-1 ${stateRoot}/traefik/acme.json /acme.json 8080";
  };

  systemd.services.homelab-compose-sabnzbd = mkComposeService {
    project = "sabnzbd";
    verify = "${verifyComposeContainer}/bin/verify-homelab-compose-container sabnzbd-sabnzbd-1 ${stateRoot}/sabnzbd/config /config 8080";
    after = [ "homelab-compose-traefik.service" ];
    wants = [ "homelab-compose-traefik.service" ];
  };

  systemd.services.homelab-compose-sonarr = mkComposeService {
    project = "sonarr";
    verify = "${verifyComposeContainer}/bin/verify-homelab-compose-container sonarr-sonarr-1 ${stateRoot}/sonarr/config /config 8989";
    mounts = [ "${stateRoot}/sonarr" "/mnt/mfs" ];
    mountChecks = [
      { path = "${stateRoot}/sonarr"; source = "data/services/sonarr"; fstype = "zfs"; }
      { path = "/mnt/mfs"; source = moosefsSource; fstype = "fuse"; }
    ];
    after = [
      "homelab-compose-traefik.service"
      "homelab-compose-sabnzbd.service"
    ];
    wants = [
      "homelab-compose-traefik.service"
      "homelab-compose-sabnzbd.service"
    ];
  };

  systemd.services.homelab-compose-radarr = mkComposeService {
    project = "radarr";
    verify = "${verifyComposeContainer}/bin/verify-homelab-compose-container radarr-radarr-1 ${stateRoot}/radarr/config /config 7878";
    mounts = [ "${stateRoot}/radarr" "/mnt/mfs" ];
    mountChecks = [
      { path = "${stateRoot}/radarr"; source = "data/services/radarr"; fstype = "zfs"; }
      { path = "/mnt/mfs"; source = moosefsSource; fstype = "fuse"; }
    ];
    after = [
      "homelab-compose-traefik.service"
      "homelab-compose-sabnzbd.service"
    ];
    wants = [
      "homelab-compose-traefik.service"
      "homelab-compose-sabnzbd.service"
    ];
  };

  systemd.services.homelab-compose-syncthing = mkComposeService {
    project = "syncthing";
    mounts = [ "${stateRoot}/syncthing" ];
    mountChecks = [
      { path = "${stateRoot}/syncthing"; source = "data/services"; fstype = "zfs"; }
    ];
    verify = "${verifyComposeContainer}/bin/verify-homelab-compose-container syncthing ${stateRoot}/syncthing/config /config 8384";
  };

  systemd.services.homelab-compose-monitoring = mkComposeService {
    project = "monitoring";
    directory = "${repoRoot}/monitoring";
    composeFile = "${repoRoot}/monitoring/docker-compose.yml";
    mounts = [ ];
    mountChecks = [ ];
    environmentFile = "${repoRoot}/monitoring/.env";
    verify = "${verifyMonitoring}/bin/verify-homelab-monitoring";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/homelab-service-backup 0700 root root - -"
  ];

  systemd.services.homelab-service-backup = {
    description = "Back up ZFS service-state snapshots to local HDD and MooseFS Restic repositories";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig = {
      ConditionPathExists = "/var/lib/homelab-service-backup/restic-password";
      RequiresMountsFor = [
        "${stateRoot}/traefik"
        "${stateRoot}/sabnzbd"
        "${stateRoot}/sonarr"
        "${stateRoot}/radarr"
        "/backup/restic"
        "/mnt/mfs"
      ];
    };
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      ExecStart = "${backupServiceState}/bin/backup-homelab-service-state";
      CacheDirectory = "homelab-service-backup";
      UMask = "0077";
      Nice = 10;
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 7;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadOnlyPaths = [ stateRoot ];
      ReadWritePaths = [
        "/backup/restic"
        "/mnt/mfs/infra/backups/restic"
        "/var/cache/homelab-service-backup"
      ];
      TimeoutStartSec = "6h";
    };
  };

  systemd.timers.homelab-service-backup = {
    description = "Nightly homelab service-state backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:30:00";
      RandomizedDelaySec = "30min";
      Persistent = true;
      Unit = "homelab-service-backup.service";
    };
  };
}
