# Command Center

A "God View" dashboard for all active Cursor AI agent sessions on your Mac.

See which agents are **thinking**, which just finished (**done**), and which are **idle** — all in one floating window. Click any tile to jump straight to that Cursor window.

## Install

### Option A: Download (recommended for non-technical users)

1. Download the latest `.zip` from [GitHub Releases](https://github.com/chenmardixrichter/cursor-command-center/releases)
2. Unzip and drag **Command Center.app** to `/Applications`
3. Open it — macOS may warn "unidentified developer":
   - **Right-click** the app > **Open** > click **Open** in the dialog
   - This is a one-time step; subsequent launches work normally
4. Done — the app auto-installs everything Cursor needs on first launch

### Option B: Build from source

```bash
git clone https://github.com/chenmardixrichter/cursor-command-center.git
cd cursor-command-center
bash install-to-applications.sh --open
```

Requires Xcode Command Line Tools (`xcode-select --install`).

## How It Works

1. **On first launch**, Command Center installs a small Cursor rule file (`~/.cursor/rules/command-center-signal.mdc`) and a helper script (`~/.cursor/bin/cc-signal`)
2. **Every time an AI agent starts or finishes work** in Cursor, the rule tells the agent to write a tiny JSON file to `~/.cursor/command-center-agents/`
3. **Command Center polls that directory** every 2 seconds and updates the dashboard tiles

No data leaves your machine. No cloud. No accounts. Fully local.

## Permissions

On first launch, macOS may ask for **Accessibility** permission in **System Settings > Privacy & Security**. This is used to raise specific Cursor windows when you click a tile.

## Features

- **Live agent tiles** — one tile per agent conversation, showing thinking/done/idle status
- **Persistent tiles** — tiles stay until you dismiss them (click the X)
- **Sticky "Done"** — done status stays until you click the tile to acknowledge
- **Custom names** — double-click any tile name to rename it
- **Quick focus** — click a tile to bring that Cursor window to the front
- **Floating window** — always visible on top, across all Spaces
- **Animated radar empty state** — when no agents are active

## Troubleshooting

**No tiles showing up?**
- Check the Cursor rule exists: `ls ~/.cursor/rules/command-center-signal.mdc`
- Check the helper script exists: `ls ~/.cursor/bin/cc-signal`
- Open Settings (gear icon) > click "Reinstall Cursor Rule"
- Start a new agent conversation in Cursor — a tile should appear within seconds

**Tiles stuck on "THINKING"?**
- The agent may not have written the "done" signal. Click the tile to acknowledge.
- Signal files expire after 5 minutes of no update.

**Want to remove it?**
- Open Settings (gear icon) > "Uninstall Command Center..."
- This removes the app, the Cursor rule, and all signal data. Your projects are untouched.

## Requirements

- macOS 14 (Sonoma) or later
- Cursor IDE

## Privacy

Fully on-premise. No code, prompts, or file contents are ever transmitted. The app sends anonymous usage pings (user ID, tile count, version) to help improve the product. No opt-out needed for the initial rollout.

## Architecture

```
~/.cursor/
├── rules/command-center-signal.mdc    # Cursor rule (installed by app)
├── bin/cc-signal                      # Helper script (installed by app)
├── command-center-agents/             # Signal inbox (JSON files per agent turn)
│   ├── .enabled                       # Marker file (signals stop if removed)
│   ├── a1b2c3d4.json                 # Active agent signal
│   └── ...
└── command-center-registry.json       # Persistent tile state

/Applications/Command Center.app       # The dashboard app
```
