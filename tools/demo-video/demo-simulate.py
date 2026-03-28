#!/usr/bin/env python3
"""
Write Command Center v2 signal JSON files for screen recording demos.

Edit demo-scenario.json (copy from demo-scenario.example.json), then run:
  python3 demo-simulate.py
  python3 demo-simulate.py --reset   # remove demo signals + registry for a clean slate

Requires ~/.cursor/command-center-agents/.enabled (Command Center installed once).
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_SCENARIO = SCRIPT_DIR / "demo-scenario.json"

INBOX = Path.home() / ".cursor/command-center-agents"
ENABLED = INBOX / ".enabled"


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def build_payload(state: str, name: str, slot: int) -> dict:
    ws = f"/tmp/command-center-demo/slot-{slot:02d}"
    t = iso_now()
    st = state.lower().strip()
    if st == "thinking":
        return {
            "schemaVersion": 2,
            "agentTurnActive": True,
            "updatedAt": t,
            "workspacePath": ws,
            "taskDescription": name[:60],
        }
    if st == "waiting":
        return {
            "schemaVersion": 2,
            "agentTurnActive": False,
            "awaitingInput": True,
            "updatedAt": t,
            "workspacePath": ws,
            "taskDescription": name[:60],
        }
    if st == "done":
        return {
            "schemaVersion": 2,
            "agentTurnActive": False,
            "updatedAt": t,
            "lastResponseCompletedAt": t,
            "workspacePath": ws,
            "taskDescription": name[:60],
        }
    if st == "idle":
        return {
            "schemaVersion": 2,
            "agentTurnActive": False,
            "updatedAt": t,
            "workspacePath": ws,
            "taskDescription": name[:60],
        }
    raise ValueError(f"Unknown state: {state!r} (use thinking|waiting|done|idle)")


def write_slot(slot: int, name: str, state: str) -> None:
    payload = build_payload(state, name, slot)
    fname = f"demo-slot-{slot:02d}.json"
    path = INBOX / fname
    INBOX.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"  wrote {fname} → {state!r} {name!r}", file=sys.stderr)


def reset_demo_files() -> None:
    if INBOX.exists():
        for p in INBOX.glob("demo-slot-*.json"):
            p.unlink(missing_ok=True)
            print(f"  removed {p.name}", file=sys.stderr)
    reg = Path.home() / ".cursor/command-center-registry.json"
    if reg.exists():
        reg.unlink()
        print("  removed command-center-registry.json", file=sys.stderr)


def run_scenario(path: Path) -> None:
    if not ENABLED.exists():
        print(
            "Missing ~/.cursor/command-center-agents/.enabled — open Command Center once first.",
            file=sys.stderr,
        )
        sys.exit(1)

    data = json.loads(path.read_text(encoding="utf-8"))
    phases = data.get("phases") or []
    if not phases:
        print("No phases in scenario file.", file=sys.stderr)
        sys.exit(1)

    for i, phase in enumerate(phases):
        wait = float(phase.get("wait_seconds", 0) or 0)
        if wait > 0:
            print(f"-- waiting {wait}s (phase {i + 1})", file=sys.stderr)
            time.sleep(wait)
        tiles = phase.get("tiles") or []
        print(f"-- phase {i + 1}: {len(tiles)} tile(s)", file=sys.stderr)
        for tile in tiles:
            slot = int(tile["slot"])
            name = str(tile.get("name") or f"Slot {slot}")
            state = str(tile.get("state") or "idle")
            write_slot(slot, name, state)


def main() -> None:
    ap = argparse.ArgumentParser(description="Simulate Command Center tiles for video demos.")
    ap.add_argument(
        "scenario",
        nargs="?",
        type=Path,
        default=DEFAULT_SCENARIO,
        help=f"JSON scenario (default: {DEFAULT_SCENARIO})",
    )
    ap.add_argument(
        "--reset",
        action="store_true",
        help="Remove demo-slot-*.json signals and registry before running",
    )
    args = ap.parse_args()
    scenario: Path = args.scenario

    if args.reset:
        print("-- reset", file=sys.stderr)
        reset_demo_files()

    if not scenario.exists():
        print(f"Scenario not found: {scenario}", file=sys.stderr)
        print(f"Copy demo-scenario.example.json to demo-scenario.json", file=sys.stderr)
        sys.exit(1)

    run_scenario(scenario)
    print("Done. Watch Command Center (polls ~1s).", file=sys.stderr)


if __name__ == "__main__":
    main()
