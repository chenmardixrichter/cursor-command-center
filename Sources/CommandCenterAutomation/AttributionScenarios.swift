import CommandCenterCore
import Foundation

enum AttributionScenarios {
    static func runAll() -> [String] {
        var issues: [String] = []
        let a = CursorWindow(id: 1, pid: 1, projectName: "alpha", projectPath: "/tmp/alpha", storageFolderHash: "ha")
        let b = CursorWindow(id: 2, pid: 1, projectName: "beta", projectPath: "/tmp/beta", storageFolderHash: "hb")
        // Keys that won’t match folder basenames → rank fallback
        let raw = ["unrelated-x": 8.0, "unrelated-y": 1.5]
        let (byId, mode) = CursorDiscovery.attributedPluginCpu(windows: [a, b], pluginCpu: raw)
        if !mode.contains("rank") {
            issues.append("attrib: expected rank mode, got \(mode)")
        }
        if (byId[1] ?? 0) != 8.0 || (byId[2] ?? 0) != 1.5 {
            issues.append("attrib: expected 8 and 1.5 ranked, got \(byId)")
        }
        return issues
    }
}
