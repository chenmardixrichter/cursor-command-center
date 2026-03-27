# Command Center

A "God View" of all active Cursor AI workflows on your Mac — instant navigation and a global ambient status indicator.

## Features

- **Window Grid Dashboard** — See every open Cursor instance at a glance
- **Custom Nicknames** — Label each project ("Legacy Cleanup", "Frontend Refactor")
- **AI Heartbeat** — Visual Thinking / Idle / Done states via CPU heuristic
- **Quick Focus** — Click any tile to bring that Cursor window to the front
- **Floating Status HUD** — Always-on-top icon reflecting aggregated agent state

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+
- Cursor IDE installed

## Build & Run

```bash
cd command-center
swift build
swift run CommandCenter
```

Or open in Xcode:

```bash
open Package.swift
```

Then **Cmd+R** to build and run.

## Permissions

On first launch you'll need to grant two permissions in **System Settings → Privacy & Security**:

| Permission | Why |
|---|---|
| **Screen Recording** | `CGWindowListCopyWindowInfo` needs it to read window titles |
| **Accessibility** | AppleScript uses it to raise specific Cursor windows |

## Architecture

```
Sources/
├── App/
│   ├── CommandCenterApp.swift        # @main SwiftUI entry point
│   └── AppDelegate.swift             # HUD panel setup, monitoring lifecycle
├── Models/
│   ├── CursorWindow.swift            # Per-window data model + AgentState
│   └── HUDState.swift                # Global HUD state enum
├── ViewModels/
│   └── CommandCenterViewModel.swift  # Polling, state machine, actions
├── Services/
│   ├── NicknameStore.swift           # JSON persistence (~/.../CommandCenter/nicknames.json)
│   └── WindowFocusService.swift      # NSRunningApplication + AppleScript focus
└── Views/
    ├── DashboardView.swift           # Adaptive grid + empty state
    ├── WindowTileView.swift          # Project tile with inline nickname editing
    ├── FloatingHUDView.swift         # Animated HUD icon (pulse, burst, glow)
    └── HUDPanelController.swift      # NSPanel wrapper (floating, all spaces)
```

### Data Flow

1. **Discovery** — Every 2 s, `CGWindowListCopyWindowInfo` finds Cursor windows by bundle ID
2. **Activity** — `ps -eo %cpu,comm` checks if any Cursor Helper process > 10 % CPU
3. **HUD State** — Active → Completed (3 s green burst) → Idle
4. **Focus** — `NSRunningApplication.activate()` + AppleScript `AXRaise`
5. **Nicknames** — Persisted to `~/Library/Application Support/CommandCenter/nicknames.json`

## Privacy

Fully on-premise. No data leaves your machine.
