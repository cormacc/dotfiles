#!/usr/bin/env bash
set -euo pipefail

# Test runner for the tasks extension.
#
# Sanity-checks the extension's structural shape and runs the
# parser/scaffold unit tests via tsx. Designed to mirror
# emacsclient/test.sh in style.

cd "$(dirname "$0")"

# ── structural sanity ────────────────────────────────────────────────

if [ ! -f "index.ts" ]; then
  echo "not ok - index.ts not found"
  exit 1
fi

if ! grep -q "^export default function" index.ts; then
  echo "not ok - index.ts missing default export"
  exit 1
fi

if ! grep -q "pi.registerCommand" index.ts; then
  echo "not ok - index.ts does not register any commands"
  exit 1
fi

# ── unit tests ───────────────────────────────────────────────────────

CODE=0
echo "# Running parser/scaffold unit tests..."
tsx ./parser.test.ts || CODE=1
exit "$CODE"
