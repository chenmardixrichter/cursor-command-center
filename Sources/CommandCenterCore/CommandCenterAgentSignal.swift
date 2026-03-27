import Foundation

/// JSON written by the Command Center companion extension (see `cursor-extension/command-center-agent-signal`).
/// **Meaning:** `agentTurnActive` is true while the user’s message is queued or the agent is still working that turn (Cursor chat UX).
/// **`lastResponseCompletedAt`:** optional ISO timestamp when the extension observed a **response-complete** command (same product moment as Cursor’s optional completion chime — not detectable from the macOS app via audio).
public struct CommandCenterAgentSignal: Equatable, Sendable {
    public var schemaVersion: Int
    public var agentTurnActive: Bool
    public var updatedAt: Date
    public var lastResponseCompletedAt: Date?
}

public enum CommandCenterAgentSignalReader {
    /// Ignore files whose `updatedAt` is older than this. Agent turns routinely last several minutes;
    /// the explicit `agentTurnActive: false` write handles normal completion — this timeout is a crash/cancel safety net.
    public static let defaultMaxAge: TimeInterval = 300
    /// Treat `lastResponseCompletedAt` as meaningful only if this recent (extension writes it when a mapped “done” command runs).
    public static let completionPingMaxAge: TimeInterval = 15

    /// Resolve the signal file for a tile: prefer `{projectPath}/.cursor/command-center-agent-signal.json`, else `workspaceStorage/<hash>/command-center-agent-signal.json`.
    public static func signalFileURL(projectPath: String?, storageFolderHash: String?) -> URL? {
        if let p = projectPath, !p.isEmpty {
            let u = URL(fileURLWithPath: p, isDirectory: true)
                .appendingPathComponent(".cursor", isDirectory: true)
                .appendingPathComponent("command-center-agent-signal.json")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        if let h = storageFolderHash, !h.isEmpty {
            for base in CursorDiscovery.workspaceStorageBaseDirectoryURLs() {
                let u = base.appendingPathComponent(h).appendingPathComponent("command-center-agent-signal.json")
                if FileManager.default.fileExists(atPath: u.path) { return u }
            }
        }
        return nil
    }

    /// Reads and validates freshness. Returns `nil` if missing, corrupt, or stale.
    public static func load(
        projectPath: String?,
        storageFolderHash: String?,
        maxAge: TimeInterval = defaultMaxAge,
        now: Date = Date()
    ) -> CommandCenterAgentSignal? {
        guard let url = signalFileURL(projectPath: projectPath, storageFolderHash: storageFolderHash) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let version = obj["schemaVersion"] as? Int ?? 1
        guard version >= 1, let active = obj["agentTurnActive"] as? Bool else { return nil }

        let updated: Date?
        if let d = obj["updatedAt"] as? String {
            updated = parseISO8601(d)
        } else if let n = obj["updatedAt"] as? Double {
            updated = Date(timeIntervalSince1970: n / 1000.0)
        } else {
            updated = nil
        }
        guard let at = updated else { return nil }
        if now.timeIntervalSince(at) > maxAge { return nil }

        let completedAt: Date? = {
            if let d = obj["lastResponseCompletedAt"] as? String { return parseISO8601(d) }
            if let n = obj["lastResponseCompletedAt"] as? Double { return Date(timeIntervalSince1970: n / 1000.0) }
            return nil
        }()

        return CommandCenterAgentSignal(
            schemaVersion: version,
            agentTurnActive: active,
            updatedAt: at,
            lastResponseCompletedAt: completedAt
        )
    }

    private static func parseISO8601(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }
}
