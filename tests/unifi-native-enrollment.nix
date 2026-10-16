# Standalone private enrollment launcher. Not imported by a host/module.
# Build/review separately; execution requires fresh native-operator approval.
{ pkgs, collector }:
let
  probe = pkgs.writeText "unifi-native-enrollment.py" (builtins.replaceStrings
    [ "@COLLECTOR_LIB@" "@SYSTEMCTL@" "@TRUE@" "@LOGGER@" ]
    [ "${collector}/libexec/homelab-unifi" "${pkgs.systemd}/bin/systemctl" "${pkgs.coreutils}/bin/true" "${pkgs.util-linux}/bin/logger" ]
    (builtins.readFile ./fixtures/unifi_native_enrollment.py));
in pkgs.writeShellScriptBin "unifi-native-enrollment" ''
  set -u
  export LC_ALL=C
  sudo=/run/wrappers/bin/sudo
  timeout=${pkgs.coreutils}/bin/timeout
  python=${pkgs.python3}/bin/python3
  ctl=${pkgs.systemd}/bin/systemctl
  run=${pkgs.systemd}/bin/systemd-run
  logger=${pkgs.util-linux}/bin/logger
  unit=homelab-unifi-enroll-01.service
  owns=0
  complete=0
  cleaning=0
  mode=enroll
  if (( $# == 1 )) && [[ "$1" == --preflight ]]; then
    mode=preflight
  elif (( $# != 0 )); then
    printf 'UNIFI_ENROLL_ABORT stage=arguments\n'
    exit 2
  fi
  if [[ ! -t 0 || ! -t 1 || ! -t 2 || $EUID == 0 ]]; then
    printf 'UNIFI_ENROLL_ABORT stage=native-terminal\n'
    exit 2
  fi
  if [[ "$(${pkgs.coreutils}/bin/stat -Lc '%a:%u:%g:%F' "$sudo")" != '4511:0:0:regular file' ]]; then
    printf 'UNIFI_ENROLL_ABORT stage=privilege-wrapper\n'
    exit 2
  fi
  rootprobe() {
    "$timeout" --foreground --kill-after=2s 15s "$sudo" -n -- "$python" -I -B ${probe} "$1"
  }
  cleanup() {
    original=$?
    cleaning=1
    restored=1
    if (( owns )); then
      "$timeout" --foreground --kill-after=2s 20s "$sudo" -n -- "$ctl" stop "$unit" >/dev/null 2>&1 || :
      "$timeout" --foreground --kill-after=2s 5s "$sudo" -n -- "$ctl" reset-failed "$unit" >/dev/null 2>&1 || :
      if (( complete )); then
        rootprobe finish || restored=0
      else
        rootprobe cleanup || restored=0
      fi
    fi
    if [[ "$mode" == preflight ]] && (( original == 0 )); then
      outcome=UNIFI_ENROLL_PREFLIGHT_SUCCESS
    elif (( complete && restored && original == 0 )); then
      outcome=UNIFI_ENROLL_SUCCESS
    elif (( ! owns )); then
      outcome=UNIFI_ENROLL_ABORT_BEFORE_MUTATION
    elif (( restored )); then
      outcome=UNIFI_ENROLL_ABORT_CANDIDATE_PRESERVED_OR_EMPTY
    else
      outcome=UNIFI_ENROLL_ESCALATION_REQUIRED
    fi
    if [[ "$outcome" == UNIFI_ENROLL_SUCCESS ]]; then
      # Privileged candidate audit must precede ticket revocation.
      "$timeout" --foreground --kill-after=2s 5s "$sudo" -n -- "$logger" -t homelab-unifi-enroll-01 -- UNIFI_ENROLL_CANDIDATE_VERIFIED || outcome=UNIFI_ENROLL_ABORT_AUDIT_FAILED
    fi
    "$timeout" --foreground --kill-after=2s 5s "$sudo" -K || outcome=UNIFI_ENROLL_ABORT_REVOCATION_FAILED
    if ! "$timeout" --foreground --kill-after=2s 5s "$python" -I -B ${probe} ticket-closed; then
      outcome=UNIFI_ENROLL_ABORT_REVOCATION_FAILED
      "$timeout" --foreground --kill-after=2s 5s "$sudo" -K || :
    fi
    "$timeout" --foreground --kill-after=2s 5s "$logger" -t homelab-unifi-enroll-01 -- "$outcome" || outcome=UNIFI_ENROLL_ABORT_AUDIT_FAILED
    printf '%s\n' "$outcome"
    trap - EXIT
    if [[ "$outcome" == UNIFI_ENROLL_SUCCESS || "$outcome" == UNIFI_ENROLL_PREFLIGHT_SUCCESS ]]; then exit 0; fi
    exit 2
  }
  trap cleanup EXIT
  trap 'if (( ! cleaning )); then exit 130; fi' INT
  trap 'if (( ! cleaning )); then exit 143; fi' TERM
  trap 'if (( ! cleaning )); then exit 129; fi' HUP
  "$timeout" --foreground --kill-after=2s 5s "$sudo" -K || exit 2
  "$timeout" --foreground --kill-after=2s 60s "$sudo" -v || exit 2
  rootprobe preflight || exit 2
  printf 'UNIFI_ENROLL_PREFLIGHT_PASS\n'
  if [[ "$mode" == preflight ]]; then exit 0; fi
  owns=1
  "$timeout" --foreground --kill-after=5s 200s "$sudo" -n -- "$run" \
    --system --pty --wait --collect --service-type=oneshot --unit="$unit" \
    --property=User=root --property=Group=root --property=Restart=no \
    --property=TimeoutStartSec=180s --property=TimeoutStopSec=10s \
    --property=TimeoutStartFailureMode=terminate --property=TimeoutStopFailureMode=terminate \
    --property=KillMode=control-group --property=KillSignal=SIGTERM \
    --property=FinalKillSignal=SIGKILL --property=SendSIGKILL=yes \
    --property=PrivateTmp=yes --property=ProtectSystem=strict --property=ProtectHome=yes \
    --property=NoNewPrivileges=yes --property=UMask=0077 --property=LimitCORE=0 \
    --property=StateDirectory=homelab-unifi-enroll-01 --property=StateDirectoryMode=0700 \
    --property=BindReadOnlyPaths=/var/lib/homelab-unifi/hosts:/etc/hosts \
    '--property=InaccessiblePaths=/run/nscd/socket -/var/lib/hermes /var/lib/homelab-unifi/api-key' \
    --property=LoadCredential=unifi-api-key:/var/lib/homelab-unifi/api-key \
    "$python" -I -B ${probe} enroll || exit 2
  complete=1
''
