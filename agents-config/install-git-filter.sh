#!/usr/bin/env bash
# Register the pi-settings clean filter for this clone of cormacc/dotfiles.
#
# Pi writes runtime preferences (defaultProvider, defaultModel,
# lastChangelogVersion) back into ~/.pi/agent/settings.json on every
# /model swap or pi upgrade. That file is symlinked from this checkout
# at agents-config/pi/settings.json, so without this filter every
# provider swap shows up as a tracked change.
#
# This script registers a git clean filter that drops those volatile
# fields when the file is staged, while leaving the working-tree copy
# untouched (smudge = cat). Pi keeps writing whatever it likes; git
# only ever sees the durable subset (notably `packages`,
# `hideThinkingBlock`, `defaultThinkingLevel`).
#
# Safe to re-run; idempotent.
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not installed." >&2
  echo "Install jq (e.g. 'nix profile install nixpkgs#jq' or via your" >&2
  echo "package manager) and re-run." >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "ERROR: not inside a git repository." >&2
  exit 1
fi
cd "$REPO_ROOT"

git config filter.pi-settings.clean \
  "jq 'del(.lastChangelogVersion, .defaultProvider, .defaultModel)' --indent 2"
git config filter.pi-settings.smudge "cat"
git config filter.pi-settings.required true

echo "Registered pi-settings clean filter for $REPO_ROOT/.git/config:"
git config --get-regexp '^filter\.pi-settings\.' | sed 's/^/  /'
echo
echo "If agents-config/pi/settings.json was committed unfiltered before"
echo "this filter was installed, renormalize it once:"
echo
echo "    git add --renormalize agents-config/pi/settings.json"
echo "    git commit -m 'chore(agents): renormalize settings.json under pi-settings filter'"
