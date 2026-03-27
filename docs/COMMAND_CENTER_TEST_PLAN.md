# Command Center — automated test plan

This document describes what is verified **without manual steps**. Run everything in one shot:

```bash
bash scripts/automation/run-full-verification.sh
```

Or:

```bash
cd "$(dirname "$0")/.." && swift build -c release && swift run -c release CommandCenterAutomation
```

## 1. Agent state machine (pure logic)

**Source:** `Sources/CommandCenterAutomation/AgentInferenceScenarios.swift`

| ID | Intent |
|----|--------|
| idle_low_cpu | Stays idle on noise |
| oscillating_cpu | Reaches `.thinking` on alternating hot/cool pattern |
| exit_thinking | Leaves `.thinking` after configured cool streak |
| thinking_ignore_boost | Plugin-only signal exits thinking even if “effective” is high |
| recent_done | Can re-enter `.thinking` from done/idle with sustained hot |
| late_spike_* | Long idle + short burst does not false-enter; sustained burst can |
| subthreshold_hum | Sustained sub-threshold CPU stays idle |

## 2. UI pipeline (same code path as app)

**Source:** `Sources/CommandCenterAutomation/AutomationMain.swift`

| Step | Intent |
|------|--------|
| loadWorkspaceEntries(fast) | Disk enumeration completes (no slow scans) |
| collectPluginCpu | `ps` pipeline returns (no hang) |
| buildSyntheticWindows | Tiles build from mock workspace + plugin map |
| pollOnce | `POCViewModel.pollOnce()` completes; status line updates |

## 3. Synthetic “must reach thinking” (POCViewModel math)

**Source:** `Sources/CommandCenterAutomation/TileInferencePathScenarios.swift`

Exercises `effectiveCpuPercent` + `pluginCpuValue` + `stepAgentState` with **non-zero** plugin and `state.vscdb` boost maps (no live Cursor required). Fails if the tile never reaches `.thinking` under a realistic agent-like signal.

| Case | Signal |
|------|--------|
| tile_path_thinking | ~4% plugin + 5.0 boost (effective above hot threshold) |
| tile_path_plugin_only | ~2.8% plugin only (above default **2.5%** hot threshold) |

## 4. What is not automated

- Visual confirmation in the macOS app window
- Ground-truth alignment with Cursor’s internal “agent running” state (would need a Cursor extension)

## 5. Failure output

On failure, `CommandCenterAutomation` prints `AUTOMATION_FAIL` and `ISSUE:` lines. Logs from `scripts/automation/verify-loop.sh` (if used) go under `.automation/`.
