import Foundation

public struct AgentSignalV2: Equatable, Sendable {
    public var fileId: String
    public var agentTurnActive: Bool
    public var updatedAt: Date
    public var lastResponseCompletedAt: Date?
    public var workspacePath: String
    public var taskDescription: String?
}

/// Reads v2 signal files from `~/.cursor/command-center-agents/`.
/// Each agent turn writes a single JSON file; the Command Center scans this directory every poll cycle.
public enum AgentSignalInbox {
    public static let inboxDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("command-center-agents", isDirectory: true)
    }()

    public static let defaultMaxAge: TimeInterval = 300
    public static let completionPingMaxAge: TimeInterval = 15

    public static func scanInbox(now: Date = Date()) -> [AgentSignalV2] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: inboxDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var signals: [AgentSignalV2] = []
        for url in contents where url.pathExtension == "json" {
            if let signal = parseSignalFile(url: url, now: now) {
                signals.append(signal)
            }
        }
        return signals
    }

    public static func ensureInboxDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: inboxDirectory.path) {
            try? fm.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        }
    }

    /// Removes signal files older than `age` seconds (default 24h).
    public static func cleanupStaleFiles(olderThan age: TimeInterval = 86400) {
        let fm = FileManager.default
        let now = Date()
        guard let contents = try? fm.contentsOfDirectory(
            at: inboxDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let updatedStr = obj["updatedAt"] as? String,
                  let updatedAt = parseISO8601(updatedStr)
            else {
                try? fm.removeItem(at: url)
                continue
            }
            if now.timeIntervalSince(updatedAt) > age {
                try? fm.removeItem(at: url)
            }
        }
    }

    // MARK: - V1 backward compatibility

    /// Reads a legacy v1 signal file from a workspace path and converts it to a v2 signal.
    public static func readLegacySignal(workspacePath: String, now: Date = Date()) -> AgentSignalV2? {
        let url = URL(fileURLWithPath: workspacePath, isDirectory: true)
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("command-center-agent-signal.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        guard let active = obj["agentTurnActive"] as? Bool else { return nil }

        let updated: Date?
        if let d = obj["updatedAt"] as? String {
            updated = parseISO8601(d)
        } else if let n = obj["updatedAt"] as? Double {
            updated = Date(timeIntervalSince1970: n / 1000.0)
        } else {
            updated = nil
        }
        guard let at = updated, now.timeIntervalSince(at) <= defaultMaxAge else { return nil }

        let completedAt: Date? = {
            if let d = obj["lastResponseCompletedAt"] as? String { return parseISO8601(d) }
            if let n = obj["lastResponseCompletedAt"] as? Double { return Date(timeIntervalSince1970: n / 1000.0) }
            return nil
        }()

        let leafName = (workspacePath as NSString).lastPathComponent
        return AgentSignalV2(
            fileId: "legacy-\(leafName)",
            agentTurnActive: active,
            updatedAt: at,
            lastResponseCompletedAt: completedAt,
            workspacePath: workspacePath,
            taskDescription: nil
        )
    }

    // MARK: - Private

    private static func parseSignalFile(url: URL, now: Date) -> AgentSignalV2? {
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
        if now.timeIntervalSince(at) > defaultMaxAge { return nil }

        let completedAt: Date? = {
            if let d = obj["lastResponseCompletedAt"] as? String { return parseISO8601(d) }
            if let n = obj["lastResponseCompletedAt"] as? Double { return Date(timeIntervalSince1970: n / 1000.0) }
            return nil
        }()

        let workspacePath = obj["workspacePath"] as? String ?? ""
        let taskDescription = obj["taskDescription"] as? String

        let fileId = url.deletingPathExtension().lastPathComponent

        return AgentSignalV2(
            fileId: fileId,
            agentTurnActive: active,
            updatedAt: at,
            lastResponseCompletedAt: completedAt,
            workspacePath: workspacePath,
            taskDescription: taskDescription
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
