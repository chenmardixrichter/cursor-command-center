import CommandCenterCore
import Foundation

enum AgentSignalScenarios {
    static func runAll() -> [String] {
        var issues: [String] = []
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cc-sig-test-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let cursorDir = tmp.appendingPathComponent(".cursor", isDirectory: true)
            try FileManager.default.createDirectory(at: cursorDir, withIntermediateDirectories: true)
            let file = cursorDir.appendingPathComponent("command-center-agent-signal.json")
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime]
            let payload: [String: Any] = [
                "schemaVersion": 1,
                "agentTurnActive": true,
                "updatedAt": fmt.string(from: Date()),
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            try data.write(to: file)

            let sig = CommandCenterAgentSignalReader.load(projectPath: tmp.path, storageFolderHash: nil)
            if sig?.agentTurnActive != true {
                issues.append("signal_load: expected agentTurnActive true, got \(String(describing: sig))")
            }

            let old = Calendar.current.date(byAdding: .minute, value: -10, to: Date())!
            let stalePayload: [String: Any] = [
                "schemaVersion": 1,
                "agentTurnActive": true,
                "updatedAt": fmt.string(from: old),
            ]
            try JSONSerialization.data(withJSONObject: stalePayload).write(to: file)
            let stale = CommandCenterAgentSignalReader.load(projectPath: tmp.path, storageFolderHash: nil)
            if stale != nil {
                issues.append("signal_stale: expected nil for old updatedAt")
            }

            let donePayload: [String: Any] = [
                "schemaVersion": 1,
                "agentTurnActive": false,
                "updatedAt": fmt.string(from: Date()),
                "lastResponseCompletedAt": fmt.string(from: Date()),
            ]
            try JSONSerialization.data(withJSONObject: donePayload).write(to: file)
            let doneSig = CommandCenterAgentSignalReader.load(projectPath: tmp.path, storageFolderHash: nil)
            if doneSig?.lastResponseCompletedAt == nil {
                issues.append("signal_completion: expected lastResponseCompletedAt")
            }
        } catch {
            issues.append("signal_io: \(error)")
        }
        try? FileManager.default.removeItem(at: tmp)
        return issues
    }
}
