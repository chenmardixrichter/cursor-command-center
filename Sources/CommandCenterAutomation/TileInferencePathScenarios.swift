import CommandCenterCore
import Foundation

/// Mirrors [`POCViewModel.syncAgentStates`] math: effective (plugin + boost) for enter, plugin-only for thinking.
enum TileInferencePathScenarios {
    /// Agent-like signal: moderate plugin % + `state.vscdb` boost, no post-thinking suppress — tile must reach `.thinking`.
    static func runAll() -> [String] {
        var issues: [String] = []
        let cfg = AgentStateInferenceConfig()

        do {
            let win = CursorWindow(
                id: -42,
                pid: 1,
                projectName: "demo-ws",
                projectPath: "/tmp/demo-ws",
                storageFolderHash: "h"
            )
            let leaf = win.leafName.lowercased()
            let pluginCpu: [String: Double] = [leaf: 4.0]
            let boost: [String: Double] = [leaf: 5.0]

            var st = AgentInferenceWindowState()
            var state: CursorWindow.AgentState = .idle
            var steps = 0
            while state != .thinking, steps < 30 {
                let pluginOnly = CursorDiscovery.pluginCpuValue(for: win, pluginCpu: pluginCpu)
                let effective = CursorDiscovery.effectiveCpuPercent(
                    for: win,
                    pluginCpu: pluginCpu,
                    stateActivityBoost: boost,
                    suppressStateActivityBoost: st.suppressActivityBoostPollsRemaining > 0
                )
                state = stepAgentState(
                    prior: state,
                    cpuEffectivePercent: effective,
                    cpuPluginPercent: pluginOnly,
                    window: &st,
                    config: cfg
                )
                steps += 1
            }
            if state != .thinking {
                issues.append(
                    "tile_path_thinking: expected .thinking within 30 steps (plugin+boost path), got \(state) after \(steps) steps"
                )
            }
        }

        do {
            let win = CursorWindow(
                id: -43,
                pid: 1,
                projectName: "solo",
                projectPath: "/Volumes/solo",
                storageFolderHash: "h2"
            )
            let leaf = win.leafName.lowercased()
            let pluginCpu: [String: Double] = [leaf: 2.8]
            let boost: [String: Double] = [:]

            var st = AgentInferenceWindowState()
            var state: CursorWindow.AgentState = .idle
            var steps = 0
            while state != .thinking, steps < 40 {
                let pluginOnly = CursorDiscovery.pluginCpuValue(for: win, pluginCpu: pluginCpu)
                let effective = CursorDiscovery.effectiveCpuPercent(
                    for: win,
                    pluginCpu: pluginCpu,
                    stateActivityBoost: boost,
                    suppressStateActivityBoost: false
                )
                state = stepAgentState(
                    prior: state,
                    cpuEffectivePercent: effective,
                    cpuPluginPercent: pluginOnly,
                    window: &st,
                    config: cfg
                )
                steps += 1
            }
            if state != .thinking {
                issues.append(
                    "tile_path_plugin_only: expected .thinking with sustained ~2.8% plugin (above default hot threshold), got \(state)"
                )
            }
        }

        return issues
    }
}
