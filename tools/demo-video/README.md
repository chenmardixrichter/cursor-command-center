# Command Center — video demo simulator

Use this to drive fake tiles while you record the app — no real Cursor agent needed.

## Quick start

```bash
cd tools/demo-video
cp demo-scenario.example.json demo-scenario.json
python3 demo-simulate.py --reset
```

`--reset` deletes `~/.cursor/command-center-agents/demo-slot-*.json` and `~/.cursor/command-center-registry.json` so you start clean. Omit `--reset` if you’re continuing a run.

Keep **Command Center** open; it polls about once per second.

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

**Note:** A tile that is already **done** usually stays “DONE” until you click it in the UI (acknowledge) or you `--reset`. For a scripted **done → idle** story, use `--reset` between takes or click during recording.

## Tips

- Use **fewer tiles** first, then add phases to show state changes.
- Long **wait_seconds** between phases gives you time to narrate.
- Run `python3 demo-simulate.py` again without `--reset` to apply only the next scenario if you keep the same slots.

## Clearing demo tiles

- **Dismiss (×)** on a tile should work even if the JSON still says `thinking` (fixed in app ≥ the dismiss-resurrection bugfix).
- Or delete the files: `rm ~/.cursor/command-center-agents/demo-slot-*.json`
- Full reset: `python3 demo-simulate.py --reset` (also clears the registry file).

## Requirements

`~/.cursor/command-center-agents/.enabled` must exist (open the real Command Center once so it installs the inbox + marker).
