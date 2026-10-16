# Standalone synthetic fixture. Not imported by any production host/module.
{ pkgs, collector }:
let
  hosts = pkgs.writeText "unifi-rehearsal-hosts" ''
    127.0.0.1 localhost
    192.0.2.23 unifi-rehearsal.invalid
  '';
  probe = pkgs.writeText "unifi-native-rehearsal.py" (builtins.replaceStrings
    [ "@COLLECTOR_LIB@" "@HOSTS@" "@SYSTEMCTL@" "@TRUE@" ]
    [ "${collector}/libexec/homelab-unifi" "${hosts}" "${pkgs.systemd}/bin/systemctl" "${pkgs.coreutils}/bin/true" ]
    (builtins.readFile ./fixtures/unifi_native_rehearsal.py));
in pkgs.writeShellScriptBin "unifi-native-rehearsal" ''
  set -u
  export LC_ALL=C
  sudo=/run/wrappers/bin/sudo
  timeout=${pkgs.coreutils}/bin/timeout
  python=${pkgs.python3}/bin/python3
  ctl=${pkgs.systemd}/bin/systemctl
  run=${pkgs.systemd}/bin/systemd-run
  logger=${pkgs.util-linux}/bin/logger
  positive=homelab-unifi-rehearsal-01.service
  negative=homelab-unifi-deadline-rehearsal-01.service
  owns=0
  complete=0
  cleaning=0
  mode=run
  if (( $# == 1 )) && [[ "$1" == --preflight ]]; then
    mode=preflight
  elif (( $# != 0 )); then
    printf 'UNIFI_REHEARSAL_ABORT stage=arguments\n'
    exit 2
  fi
  if [[ ! -t 0 || ! -t 1 || ! -t 2 || $EUID == 0 ]]; then
    printf 'UNIFI_REHEARSAL_ABORT stage=native-terminal\n'
    exit 2
  fi
  if [[ "$(${pkgs.coreutils}/bin/stat -Lc '%a:%u:%g:%F' "$sudo")" != '4511:0:0:regular file' ]]; then
    printf 'UNIFI_REHEARSAL_ABORT stage=privilege-wrapper\n'
    exit 2
  fi
  rootprobe() {
    "$timeout" --foreground --kill-after=2s 8s "$sudo" -n -- "$python" -I -B ${probe} "$1"
  }
  cleanup() {
    original=$?
    cleaning=1
    restored=1
    if (( owns )); then
      # Missing units are harmless here; the final preflight proves absence.
      "$timeout" --foreground --kill-after=2s 20s "$sudo" -n -- "$ctl" stop "$positive" "$negative" >/dev/null 2>&1 || :
      "$timeout" --foreground --kill-after=2s 5s "$sudo" -n -- "$ctl" reset-failed "$positive" "$negative" >/dev/null 2>&1 || :
      rootprobe cleanup || restored=0
      rootprobe preflight || restored=0
    fi
    if [[ "$mode" == preflight ]] && (( original == 0 && restored )); then
      outcome=UNIFI_REHEARSAL_PREFLIGHT_SUCCESS
    elif (( complete && restored && original == 0 )); then
      outcome=UNIFI_REHEARSAL_SUCCESS
    elif (( ! owns )); then
      outcome=UNIFI_REHEARSAL_ABORT_BEFORE_MUTATION
    elif (( restored )); then
      outcome=UNIFI_REHEARSAL_ABORT_ROLLBACK_VERIFIED
    else
      outcome=UNIFI_REHEARSAL_ABORT_ROLLBACK_FAILED
    fi
    if (( owns )); then
      audit="$outcome"
      if [[ "$audit" == UNIFI_REHEARSAL_SUCCESS ]]; then audit=UNIFI_REHEARSAL_CHECKS_PASS; fi
      "$timeout" --foreground --kill-after=2s 5s "$sudo" -n -- "$logger" -t homelab-unifi-rehearsal-01 -- "$audit" || outcome=UNIFI_REHEARSAL_ABORT_AUDIT_FAILED
    fi
    "$timeout" --foreground --kill-after=2s 5s "$sudo" -K || outcome=UNIFI_REHEARSAL_ABORT_REVOCATION_FAILED
    if ! "$timeout" --foreground --kill-after=2s 5s "$python" -I -B ${probe} ticket-closed; then
      outcome=UNIFI_REHEARSAL_ABORT_REVOCATION_FAILED
      "$timeout" --foreground --kill-after=2s 5s "$sudo" -K || :
    fi
    "$timeout" --foreground --kill-after=2s 5s "$logger" -t homelab-unifi-rehearsal-01 -- "$outcome" || outcome=UNIFI_REHEARSAL_ABORT_AUDIT_FAILED
    printf '%s\n' "$outcome"
    trap - EXIT
    if [[ "$outcome" == UNIFI_REHEARSAL_SUCCESS || "$outcome" == UNIFI_REHEARSAL_PREFLIGHT_SUCCESS ]]; then exit 0; fi
    exit 2
  }
  trap cleanup EXIT
  trap 'if (( ! cleaning )); then exit 130; fi' INT
  trap 'if (( ! cleaning )); then exit 143; fi' TERM
  trap 'if (( ! cleaning )); then exit 129; fi' HUP
  "$timeout" --foreground --kill-after=2s 5s "$sudo" -K || exit 2
  "$timeout" --foreground --kill-after=2s 60s "$sudo" -v || exit 2
  rootprobe preflight || exit 2
  printf 'UNIFI_REHEARSAL_PREFLIGHT_PASS\n'
  if [[ "$mode" == preflight ]]; then exit 0; fi
  owns=1
  common=(
    --system --wait --service-type=oneshot
    --property=User=root --property=Group=root --property=Restart=no
    --property=TimeoutStartFailureMode=terminate --property=TimeoutStopFailureMode=terminate
    --property=KillMode=control-group --property=KillSignal=SIGTERM
    --property=FinalKillSignal=SIGKILL --property=SendSIGKILL=yes
    --property=PrivateNetwork=yes --property=PrivateTmp=yes
    --property=ProtectSystem=strict --property=ProtectHome=yes
    --property=NoNewPrivileges=yes --property=UMask=0077 --property=LimitCORE=0
    --property=StateDirectory=homelab-unifi-rehearsal-01 --property=StateDirectoryMode=0700
    --property=BindReadOnlyPaths=${hosts}:/etc/hosts
    '--property=InaccessiblePaths=/run/nscd/socket -/var/lib/homelab-unifi -/var/lib/hermes'
  )
  "$timeout" --foreground --kill-after=5s 140s "$sudo" -n -- "$run" "''${common[@]}" \
    --pty --collect --unit="$positive" --property=TimeoutStartSec=120s --property=TimeoutStopSec=10s \
    "$python" -I -B ${probe} probe || exit 2
  if "$timeout" --foreground --kill-after=3s 15s "$sudo" -n -- "$run" "''${common[@]}" \
    --unit="$negative" --property=TimeoutStartSec=2s --property=TimeoutStopSec=1s \
    "$python" -I -B ${probe} hang; then exit 2; fi
  rootprobe verify || exit 2
  complete=1
''
