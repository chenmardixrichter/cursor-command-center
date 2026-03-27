import Foundation

public struct AgentRegistryEntry: Codable, Equatable, Sendable {
    public var agentId: String
    public var workspacePath: String
    public var displayName: String
    public var lastSignalFileId: String?
    public var state: String
    public var lastActiveAt: Date?
    public var dismissed: Bool
    public var taskDescription: String?
}

/// Persistent registry of agent tiles. Manages identity matching across agent turns
/// and stores user-editable display names. Tiles persist until manually dismissed.
public final class AgentRegistry: @unchecked Sendable {
    private let filePath: URL
    private var entries: [AgentRegistryEntry] = []
    private let lock = NSLock()

    public init() {
        self.filePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("command-center-registry.json")
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: filePath) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([AgentRegistryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: filePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: filePath, options: .atomic)
    }

    // MARK: - Core matching

    /// Processes incoming signals and returns the current tile list (excluding dismissed).
    ///
    /// Matching priority:
    /// 1. Signal file ID matches a known entry -> same agent, same turn
    /// 2. Same workspace path + idle/done + most recently active -> cross-turn continuity
    /// 3. No match -> new agent tile
    public func processSignals(_ signals: [AgentSignalV2], now: Date = Date()) -> [AgentTile] {
        lock.lock()
        defer { lock.unlock() }

        var matchedFileIds = Set<String>()
        for signal in signals {
            matchSignal(signal, now: now, matchedFileIds: &matchedFileIds)
        }

        let activeFileIds = Set(signals.map(\.fileId))
        for i in entries.indices {
            if entries[i].dismissed { continue }
            guard let fileId = entries[i].lastSignalFileId else { continue }
            if !activeFileIds.contains(fileId) && entries[i].state == "thinking" {
                entries[i].state = "idle"
            }
        }

        save()

        return entries.filter { !$0.dismissed }.map { entry in
            AgentTile(
                id: entry.agentId,
                workspacePath: entry.workspacePath,
                displayName: entry.displayName,
                taskDescription: entry.taskDescription,
                agentState: AgentTile.AgentState(rawValue: entry.state) ?? .idle,
                lastActiveAt: entry.lastActiveAt
            )
        }
    }

    private func matchSignal(_ signal: AgentSignalV2, now: Date, matchedFileIds: inout Set<String>) {
        if matchedFileIds.contains(signal.fileId) { return }

        // If a dismissed entry owns this signal file, ignore unless the agent is actively thinking again
        if let _ = entries.firstIndex(where: { $0.lastSignalFileId == signal.fileId && $0.dismissed }) {
            if !signal.agentTurnActive {
                matchedFileIds.insert(signal.fileId)
                return
            }
        }

        if let idx = entries.firstIndex(where: { $0.lastSignalFileId == signal.fileId && !$0.dismissed }) {
            updateEntry(at: idx, from: signal, now: now)
            matchedFileIds.insert(signal.fileId)
            return
        }

        let candidates = entries.enumerated().filter { _, entry in
            !entry.dismissed
                && entry.workspacePath == signal.workspacePath
                && (entry.state == "idle" || entry.state == "recentlyCompleted")
                && !matchedFileIds.contains(entry.lastSignalFileId ?? "")
        }
        if let best = candidates.max(by: {
            ($0.element.lastActiveAt ?? .distantPast) < ($1.element.lastActiveAt ?? .distantPast)
        }) {
            updateEntry(at: best.offset, from: signal, now: now)
            matchedFileIds.insert(signal.fileId)
            return
        }

        // Only create a new tile if the agent is actively thinking
        guard signal.agentTurnActive else {
            matchedFileIds.insert(signal.fileId)
            return
        }

        let newEntry = AgentRegistryEntry(
            agentId: UUID().uuidString,
            workspacePath: signal.workspacePath,
            displayName: signal.taskDescription ?? (signal.workspacePath as NSString).lastPathComponent,
            lastSignalFileId: signal.fileId,
            state: stateFromSignal(signal, now: now),
            lastActiveAt: signal.updatedAt,
            dismissed: false,
            taskDescription: signal.taskDescription
        )
        entries.append(newEntry)
        matchedFileIds.insert(signal.fileId)
    }

    private func updateEntry(at index: Int, from signal: AgentSignalV2, now: Date) {
        entries[index].lastSignalFileId = signal.fileId
        entries[index].lastActiveAt = signal.updatedAt
        if let desc = signal.taskDescription {
            entries[index].taskDescription = desc
        }

        let signalState = stateFromSignal(signal, now: now)
        if signalState == "thinking" {
            entries[index].state = "thinking"
        } else if signalState == "recentlyCompleted" {
            if entries[index].state == "thinking" {
                entries[index].state = "recentlyCompleted"
            }
        } else if entries[index].state == "thinking" {
            entries[index].state = "idle"
        }
    }

    private func stateFromSignal(_ signal: AgentSignalV2, now: Date) -> String {
        if signal.agentTurnActive {
            return "thinking"
        }
        if signal.lastResponseCompletedAt != nil {
            return "recentlyCompleted"
        }
        return "idle"
    }

    // MARK: - User actions

    public func acknowledgeDone(agentId: String) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = entries.firstIndex(where: { $0.agentId == agentId && $0.state == "recentlyCompleted" }) {
            entries[idx].state = "idle"
            save()
        }
    }

    public func dismiss(agentId: String) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = entries.firstIndex(where: { $0.agentId == agentId }) {
            entries[idx].dismissed = true
            save()
        }
    }

    public func setDisplayName(_ name: String, forAgentId agentId: String) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = entries.firstIndex(where: { $0.agentId == agentId }) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            entries[idx].displayName = trimmed.isEmpty ? entries[idx].workspacePath : trimmed
            save()
        }
    }

    public func displayName(forAgentId agentId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return entries.first(where: { $0.agentId == agentId })?.displayName
    }

    /// Returns workspace paths of all non-dismissed entries (for legacy v1 signal scanning).
    public func knownWorkspacePaths() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(Set(entries.filter { !$0.dismissed }.map(\.workspacePath)))
    }
}
