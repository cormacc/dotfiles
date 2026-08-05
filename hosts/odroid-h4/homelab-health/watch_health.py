#!/usr/bin/env python3
"""Print only health transitions; suitable for script-only cron delivery."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from health_snapshot import collect, load_inventory


def statuses(snapshot: dict) -> dict[str, bool]:
    return {host["id"]: host["ok"] for host in snapshot.get("hosts", [])}


def transition_message(previous: dict | None, current: dict) -> str:
    if previous is None:
        if current["overall"] == "degraded":
            failed = [name for name, ok in statuses(current).items() if not ok]
            return "HOMELAB ALERT: initial check is degraded: " + ", ".join(failed)
        return ""
    before, after = statuses(previous), statuses(current)
    changed = []
    for name in sorted(set(before) | set(after)):
        if before.get(name) != after.get(name):
            changed.append(f"{name}={'UP' if after.get(name) else 'DOWN'}")
    return "HOMELAB HEALTH CHANGE: " + ", ".join(changed) if changed else ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", default="inventory/hosts.json")
    parser.add_argument("--state", default="state/health.json")
    parser.add_argument("--timeout", type=float, default=3.0)
    args = parser.parse_args()
    try:
        current = collect(load_inventory(args.inventory), args.timeout)
        path = Path(args.state)
        previous = json.loads(path.read_text()) if path.exists() else None
        message = transition_message(previous, current)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(current, indent=2, sort_keys=True) + "\n")
        if message:
            print(message)
        return 1 if current["overall"] == "degraded" else 0
    except Exception as exc:
        print(f"HOMELAB WATCHDOG ERROR: {type(exc).__name__}: {exc}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
