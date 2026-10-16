# Standalone source-only gates. No host imports, activation or scheduling.
{ pkgs, collector }:
let
  mkGate = mode: name:
    let
      tag = if mode == "install" then "INSTALL" else "COLLECT";
      probe = pkgs.writeText "${name}.py" (builtins.replaceStrings
        [ "@MODE@" "@COLLECTOR_LIB@" "@SYSTEMCTL@" "@SYSTEMD_RUN@"
          "@JOURNALCTL@" "@LOGGER@" "@PYTHON@" "@TRUE@" ]
        [ mode "${collector}/libexec/homelab-unifi" "${pkgs.systemd}/bin/systemctl"
          "${pkgs.systemd}/bin/systemd-run" "${pkgs.systemd}/bin/journalctl"
          "${pkgs.util-linux}/bin/logger" "${pkgs.python3}/bin/python3"
          "${pkgs.coreutils}/bin/true" ]
        (builtins.readFile ./fixtures/unifi_native_acceptance.py));
    in pkgs.writeShellScriptBin name ''
      set -u
      export LC_ALL=C
      umask 077
      sudo=/run/wrappers/bin/sudo
      timeout=${pkgs.coreutils}/bin/timeout
      python=${pkgs.python3}/bin/python3
      logger=${pkgs.util-linux}/bin/logger
      mode=run
      complete=0
      cleaning=0
      if (( $# == 1 )) && [[ "$1" == --preflight ]]; then
        mode=preflight
      elif (( $# != 0 )); then
        printf 'UNIFI_ACCEPT_ABORT stage=arguments\n'
        exit 2
      fi
      if [[ ! -t 0 || ! -t 1 || ! -t 2 || $EUID == 0 ]]; then
        printf 'UNIFI_ACCEPT_ABORT stage=native-terminal\n'
        exit 2
      fi
      if [[ "$(${pkgs.coreutils}/bin/stat -Lc '%a:%u:%g:%F' "$sudo")" != '4511:0:0:regular file' ]]; then
        printf 'UNIFI_ACCEPT_ABORT stage=privilege-wrapper\n'
        exit 2
      fi
      cleanup() {
        original=$?
        cleaning=1
        outcome=UNIFI_ACCEPT_${tag}_ABORT
        if (( complete && original == 0 )); then
          if [[ "$mode" == preflight ]]; then
            outcome=UNIFI_ACCEPT_${tag}_PREFLIGHT_SUCCESS
          else
            outcome=UNIFI_ACCEPT_${tag}_SUCCESS
          fi
        fi
        "$timeout" --foreground --kill-after=2s 5s "$sudo" -K || outcome=UNIFI_ACCEPT_ABORT_REVOCATION_FAILED
        if ! "$timeout" --foreground --kill-after=2s 5s "$python" -I -B ${probe} --ticket-closed; then
          outcome=UNIFI_ACCEPT_ABORT_REVOCATION_FAILED
          "$timeout" --foreground --kill-after=2s 5s "$sudo" -K || :
        fi
        "$timeout" --foreground --kill-after=2s 5s "$logger" -t homelab-unifi-acceptance-01 -- "$outcome" || outcome=UNIFI_ACCEPT_ABORT_AUDIT_FAILED
        printf '%s\n' "$outcome"
        trap - EXIT
        if [[ "$outcome" == UNIFI_ACCEPT_${tag}_SUCCESS || "$outcome" == UNIFI_ACCEPT_${tag}_PREFLIGHT_SUCCESS ]]; then exit 0; fi
        exit 2
      }
      trap cleanup EXIT
      trap 'if (( ! cleaning )); then exit 130; fi' INT
      trap 'if (( ! cleaning )); then exit 143; fi' TERM
      trap 'if (( ! cleaning )); then exit 129; fi' HUP
      "$timeout" --foreground --kill-after=2s 5s "$sudo" -K || exit 2
      "$timeout" --foreground --kill-after=2s 60s "$sudo" -v || exit 2
      # No generic elevated tool/action interface; only this immutable helper.
      if [[ "$mode" == preflight ]]; then
        "$timeout" --foreground --kill-after=15s 30s "$sudo" -n -- "$python" -I -B ${probe} --preflight || exit 2
      else
        "$timeout" --foreground --kill-after=15s 200s "$sudo" -n -- "$python" -I -B ${probe} || exit 2
      fi
      complete=1
    '';
in pkgs.symlinkJoin {
  name = "unifi-native-acceptance";
  paths = [
    (mkGate "install" "unifi-native-install-validate")
    (mkGate "collect" "unifi-native-supervised-collect")
  ];
}
