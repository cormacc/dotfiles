#!/usr/bin/env python3
"""Dependency-free TCP and HTTP health snapshot collector."""
from __future__ import annotations

import argparse
import json
import socket
import ssl
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def load_inventory(path: str | Path) -> dict[str, Any]:
    data = json.loads(Path(path).read_text())
    if data.get("version") != 1 or not isinstance(data.get("hosts"), list):
        raise ValueError("inventory must have version 1 and a hosts array")
    ids: set[str] = set()
    for host in data["hosts"]:
        required = {"id", "role", "address", "enabled", "checks"}
        missing = required - host.keys()
        if missing:
            raise ValueError(f"host missing keys: {sorted(missing)}")
        if host["id"] in ids:
            raise ValueError(f"duplicate host id: {host['id']}")
        ids.add(host["id"])
        if not isinstance(host["checks"], list):
            raise ValueError(f"checks must be a list for {host['id']}")
    return data


def tcp_check(address: str, port: int, timeout: float) -> tuple[bool, str]:
    try:
        with socket.create_connection((address, int(port)), timeout=timeout):
            return True, "connected"
    except OSError as exc:
        return False, f"{type(exc).__name__}: {exc}"


def http_check(check: dict[str, Any], timeout: float) -> tuple[bool, str]:
    expected = set(check.get("expected_status", [200]))
    request = urllib.request.Request(check["url"], method="GET", headers={"User-Agent": "homelab-health/1"})
    context = None
    if check.get("tls_verify") is False:
        context = ssl._create_unverified_context()  # explicitly configured for private self-signed endpoints
    try:
        with urllib.request.urlopen(request, timeout=timeout, context=context) as response:
            code = response.getcode()
            return code in expected, f"HTTP {code}"
    except urllib.error.HTTPError as exc:
        return exc.code in expected, f"HTTP {exc.code}"
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return False, f"{type(exc).__name__}: {exc}"


def collect(inventory: dict[str, Any], timeout: float = 3.0) -> dict[str, Any]:
    started = time.monotonic()
    hosts = []
    for host in inventory["hosts"]:
        if not host["enabled"]:
            continue
        checks = []
        for spec in host["checks"]:
            check_started = time.monotonic()
            kind = spec.get("kind")
            if kind == "tcp":
                ok, detail = tcp_check(host["address"], spec["port"], timeout)
            elif kind == "http":
                ok, detail = http_check(spec, timeout)
            else:
                ok, detail = False, f"unsupported check kind: {kind}"
            checks.append({"name": spec.get("name", kind or "unknown"), "kind": kind, "ok": ok,
                           "detail": detail, "latency_ms": round((time.monotonic() - check_started) * 1000, 1)})
        host_ok = bool(checks) and all(item["ok"] for item in checks)
        hosts.append({"id": host["id"], "role": host["role"], "ok": host_ok, "checks": checks})
    enabled = len(hosts)
    overall = "unknown" if enabled == 0 else ("healthy" if all(h["ok"] for h in hosts) else "degraded")
    return {"schema_version": 1, "observed_at": datetime.now(timezone.utc).isoformat(), "overall": overall,
            "enabled_hosts": enabled, "duration_ms": round((time.monotonic() - started) * 1000, 1), "hosts": hosts}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", default="inventory/hosts.json")
    parser.add_argument("--timeout", type=float, default=3.0)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        snapshot = collect(load_inventory(args.inventory), args.timeout)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"overall": "error", "error": str(exc)}))
        return 2
    rendered = json.dumps(snapshot, indent=2, sort_keys=True)
    if args.output:
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered + "\n")
    print(rendered)
    return 1 if snapshot["overall"] == "degraded" else 0


if __name__ == "__main__":
    sys.exit(main())
