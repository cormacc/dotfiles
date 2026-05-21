#!/usr/bin/env bash
# bootstrap.sh — apply a NixOS host profile from this flake onto a fresh
# NixOS install (post live-CD `nixos-install`).
#
# Usage:
#   ./bootstrap.sh <profile> [--hm-config <name>] [--skip-hm] [--yes]
#
# Required arg:
#   <profile>            Name of a `nixosConfigurations.<profile>` entry in
#                        flake.nix. Must also have a `hosts/<profile>/`
#                        directory containing nixos-configuration.nix and
#                        a (post-bootstrap) hardware-configuration.nix.
#
# Optional:
#   --hm-config <name>   Home Manager configuration to apply after the
#                        NixOS rebuild. Defaults to `default`. Use
#                        `--skip-hm` to skip Home Manager entirely.
#   --skip-hm            Don't run `home-manager switch`.
#   --yes                Don't prompt before destructive steps.
#
# What it does:
#   1. Validates that `hosts/<profile>/` exists in this checkout.
#   2. Ensures NAME, EMAIL, GITLAB are populated (prompts if missing).
#      These are consumed via builtins.getEnv in home-core.nix and must
#      survive `sudo nixos-rebuild` (which is why we use
#      `sudo --preserve-env=...` in step 5).
#   3. Copies /etc/nixos/hardware-configuration.nix over
#      hosts/<profile>/hardware-configuration.nix (after backing up the
#      existing placeholder). Skipped if the source file is already in
#      place (idempotent re-runs).
#   4. Refuses to proceed if the result still contains the literal
#      `BOOTSTRAP_PLACEHOLDER` sentinel — that means step 3 didn't run
#      against a generated file and the rebuild would explode.
#   5. Applies `sudo nixos-rebuild switch --flake .#<profile> --impure`.
#   6. Applies `home-manager switch --flake .#<hm-config> --impure -b backup`
#      (unless --skip-hm).
#
# Pre-conditions on the target machine:
#   - NixOS already installed (so /etc/nixos/hardware-configuration.nix
#     exists from `nixos-generate-config`).
#   - This repo cloned (`git clone --recurse-submodules ...`).
#   - The user running the script has sudo for nixos-rebuild and read
#     access to /etc/nixos/hardware-configuration.nix.

set -euo pipefail

# -----------------------------------------------------------------------------
# Arg parsing
# -----------------------------------------------------------------------------
profile=""
hm_config="default"
skip_hm=0
assume_yes=0

usage() {
    sed -n '2,40p' "$0"
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage 0 ;;
        --hm-config)
            [ $# -ge 2 ] || { echo "error: --hm-config needs an argument" >&2; exit 2; }
            hm_config="$2"; shift 2 ;;
        --skip-hm) skip_hm=1; shift ;;
        --yes|-y) assume_yes=1; shift ;;
        --) shift; break ;;
        -*)
            echo "error: unknown flag: $1" >&2
            usage 2 ;;
        *)
            if [ -z "$profile" ]; then
                profile="$1"; shift
            else
                echo "error: unexpected positional arg: $1" >&2
                usage 2
            fi ;;
    esac
done

if [ -z "$profile" ]; then
    echo "error: profile name required" >&2
    usage 2
fi

# -----------------------------------------------------------------------------
# Locate repo + paths
# -----------------------------------------------------------------------------
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

host_dir="hosts/$profile"
hw_target="$host_dir/hardware-configuration.nix"
hw_source="/etc/nixos/hardware-configuration.nix"
placeholder_marker="BOOTSTRAP_PLACEHOLDER"

confirm() {
    [ "$assume_yes" -eq 1 ] && return 0
    local prompt="$1"
    read -r -p "$prompt [y/N] " ans
    case "$ans" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

say() { printf '\n==> %s\n' "$*"; }
run() { printf '    $ %s\n' "$*"; "$@"; }

# Ensure an identity variable is set in the environment, prompting the user
# for a value if it isn't. Exports the result so child processes inherit it.
#   ensure_var NAME    "Full name (e.g. 'Jane Doe')" required
#   ensure_var GITLAB  "Self-hosted GitLab host"     optional
ensure_var() {
    local var="$1" prompt="$2" mode="${3:-required}"
    local current="${!var-}"
    if [ -n "$current" ]; then
        echo "    ok: \$$var already set"
        export "$var=$current"
        return 0
    fi
    local ans=""
    if [ -t 0 ]; then
        # Interactive: loop until we get a value (or accept empty if optional).
        while :; do
            read -r -p "    $prompt: " ans || ans=""
            if [ -n "$ans" ] || [ "$mode" = "optional" ]; then
                break
            fi
            echo "    (required — please provide a value)" >&2
        done
    else
        # Non-interactive: consume one line from stdin if available.
        read -r ans || ans=""
        if [ -z "$ans" ] && [ "$mode" = "required" ]; then
            echo "error: \$$var not set and no value supplied on stdin" >&2
            exit 1
        fi
    fi
    export "$var=$ans"
}

# -----------------------------------------------------------------------------
# 1. Validate profile directory
# -----------------------------------------------------------------------------
say "Validating profile: $profile"
if [ ! -d "$host_dir" ]; then
    echo "error: no such host directory: $host_dir" >&2
    echo "       Available profiles:" >&2
    for d in hosts/*/; do echo "         - $(basename "$d")" >&2; done
    exit 1
fi
if [ ! -f "$host_dir/nixos-configuration.nix" ]; then
    echo "error: missing $host_dir/nixos-configuration.nix" >&2
    exit 1
fi
echo "    ok: $host_dir present"

# -----------------------------------------------------------------------------
# 2. Ensure identity env vars (consumed by home-core.nix via builtins.getEnv)
# -----------------------------------------------------------------------------
say "Ensuring identity env vars (NAME, EMAIL, GITLAB)"
ensure_var NAME   "Your name (used in git config)"                  required
ensure_var EMAIL  "Your email (used in git config)"                 required
ensure_var GITLAB "Self-hosted GitLab host (blank if none)"         optional

# -----------------------------------------------------------------------------
# 3. Refresh hardware-configuration.nix from /etc/nixos
# -----------------------------------------------------------------------------
say "Refreshing $hw_target from $hw_source"

if [ ! -r "$hw_source" ]; then
    echo "error: cannot read $hw_source" >&2
    echo "       This script is intended to run on the target machine after" >&2
    echo "       a fresh NixOS install. Run 'nixos-generate-config' first if" >&2
    echo "       the file is missing." >&2
    exit 1
fi

needs_copy=1
if [ -f "$hw_target" ] && ! grep -q "$placeholder_marker" "$hw_target" && cmp -s "$hw_source" "$hw_target"; then
    needs_copy=0
    echo "    ok: $hw_target already matches $hw_source"
fi

if [ "$needs_copy" -eq 1 ]; then
    if [ -f "$hw_target" ]; then
        backup="$hw_target.bak.$(date +%Y%m%d%H%M%S)"
        echo "    backing up existing file -> $backup"
        cp -a "$hw_target" "$backup"
    fi
    confirm "Overwrite $hw_target with $hw_source?" || { echo "aborted by user"; exit 1; }
    run cp "$hw_source" "$hw_target"
fi

# -----------------------------------------------------------------------------
# 4. Refuse to proceed if placeholder is still present
# -----------------------------------------------------------------------------
if grep -q "$placeholder_marker" "$hw_target"; then
    echo "error: $hw_target still contains $placeholder_marker sentinel" >&2
    echo "       Refusing to invoke nixos-rebuild." >&2
    exit 1
fi
echo "    ok: $hw_target is a real hardware-configuration"

# -----------------------------------------------------------------------------
# 5. nixos-rebuild switch
# -----------------------------------------------------------------------------
# `--impure` makes nixos-rebuild read NAME/EMAIL/GITLAB from the env. `sudo`
# strips the env by default, so explicitly preserve the identity vars (host
# configs that bake in home-manager.nixosModules — e.g. t470p — evaluate
# home-core.nix during this step and would otherwise see empty strings).
say "Applying NixOS configuration: .#$profile"
confirm "Run: sudo nixos-rebuild switch --flake .#$profile --impure ?" \
    || { echo "aborted by user"; exit 1; }
run sudo --preserve-env=NAME,EMAIL,GITLAB nixos-rebuild switch --flake ".#$profile" --impure

# -----------------------------------------------------------------------------
# 6. Home Manager
# -----------------------------------------------------------------------------
if [ "$skip_hm" -eq 1 ]; then
    say "Skipping Home Manager (--skip-hm)"
else
    say "Applying Home Manager configuration: .#$hm_config"
    confirm "Run: home-manager switch --flake .#$hm_config --impure -b backup ?" \
        || { echo "aborted by user"; exit 1; }
    run home-manager switch --flake ".#$hm_config" --impure -b backup
fi

say "Bootstrap complete for profile '$profile'."
