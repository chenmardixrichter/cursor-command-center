# Command Center — video demo simulator

Use this to drive **fake** tiles while you record the app — no real Cursor agent needed.

## Reality vs demo (read this)

| | **Real Cursor agents** | **This demo simulator** |
|---|------------------------|-------------------------|
| **Purpose** | One tile per `cc-signal` JSON (multiple tiles per workspace possible); reflects live turns | **Appearance only** — simulate tiles for a screen recording |
| **Signal files** | Unique JSON name per turn (from `cc-signal`) | Fixed names: `demo-slot-01.json` … under your inbox |
| **Workspaces** | Your real project folders | Fake paths: `/tmp/command-center-demo/slot-NN` |
| **After you dismiss** | Snooze vs permanent (same as production); permanent ignores that signal file id until registry reset | Dismiss removes demo rows; use `--reset` before the next take for a clean slate |
| **When you’re done recording** | N/A | Dismiss demo tiles or run `--reset` — **normal behavior** for real agents is unchanged |

**Typical recording flow:** Manually dismiss or clear tiles so the board is empty → run `./run-demo-local.sh --reset` → demo tiles appear → record → dismiss or `--reset`. Your real project tiles then follow the **real** rules above.

## Important: run on your Mac

Command Center reads signals from **`$HOME/.cursor/command-center-agents/`** on **your Mac**.

If you ask a **Cursor AI agent** to run `demo-simulate.py`, it may execute in an environment where files are **not** written to that folder (e.g. remote or sandbox). The app would then only show **your real Cursor session** tile — not the demo tiles.

**For recording:** open **Terminal.app** (or iTerm), `cd` to this folder, and run:

```bash
./run-demo-local.sh --reset
```

`run-demo-local.sh` uses your shell’s `HOME` so paths match Command Center.

Verify: the script prints `inbox: /Users/you/.cursor/...`. Optionally check **Settings → Diagnostics** in Command Center: **`v2:`** should match how many `.json` signal files you expect.

## Quick start

```bash
cd tools/demo-video
cp demo-scenario.example.json demo-scenario.json
./run-demo-local.sh --reset
```

`--reset` deletes `demo-slot-*.json` and `~/.cursor/command-center-registry.json`. Omit `--reset` if you’re continuing a run.

### Troubleshooting: demo tiles vanished after I dismissed them

Demo signals use **fixed** filenames (`demo-slot-01.json`, …). The app used to remember a dismissed demo as “never show this file id again,” so the **same** filenames would not come back until the registry was cleared.

**Now:** dismissing a demo tile **removes** that row for `demo-slot-*` signals, so the next demo run can show tiles again **without** a full `--reset`. If something still looks stuck, run `./run-demo-local.sh --reset` or delete `~/.cursor/command-center-registry.json`.

**Verify the dismiss/registry theory:** dismiss demo tiles → run the scenario **without** `--reset` → tiles should appear again after the registry fix. A full `--reset` also clears any leftover state.

Keep **Command Center** open; it polls about once per second.

Optional env: `COMMAND_CENTER_INBOX=/absolute/path/to/command-center-agents`

## Scenario format

`demo-scenario.json` is a list of **phases**. Each phase:

- **`wait_seconds`** — sleep this long *before* applying this phase (0 = immediate).
- **`tiles`** — list of tiles to write in that phase.

Each tile:

| Field | Meaning |
|--------|--------|
| **`slot`** | Integer 1–99. Maps to file `demo-slot-NN.json` and a fake workspace `/tmp/command-center-demo/slot-NN`. Same slot in a later phase **updates** that tile. |
| **`name`** | Shown as the tile title (task line). |
| **`state`** | `thinking`, `waiting`, `done`, or `idle` |

### States

- **thinking** — teal “THINKING”
- **waiting** — amber “WAITING”
- **done** — green “DONE” (stays until you click the tile or reset)
- **idle** — gray “IDLE”

**Note:** A tile that is already **done** usually stays “DONE” until you click it in the UI (acknowledge) or you `--reset`.

## Tips

- Use **fewer tiles** first, then add phases to show state changes.
- Long **wait_seconds** between phases gives you time to narrate.

## Clearing demo tiles

- **Dismiss (×)** on a tile — works even if the JSON still says `thinking`.
- Or: `rm ~/.cursor/command-center-agents/demo-slot-*.json`
- Full reset: `./run-demo-local.sh --reset`

## Requirements

`~/.cursor/command-center-agents/.enabled` must exist (open Command Center once so it installs the inbox + marker).
