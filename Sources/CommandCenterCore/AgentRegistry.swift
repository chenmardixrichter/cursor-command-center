import Foundation

public struct AgentRegistryEntry: Codable, Equatable, Sendable {
    public var agentId: String
    public var workspacePath: String
    public var displayName: String
    public var lastSignalFileId: String?
    public var state: String
    public var lastActiveAt: Date?
    public var dismissed: Bool
    /// When `dismissed` is true: if false, snooze (hide until a new cc-signal file appears); if true, also add `lastSignalFileId` to the persistent ignore list.
    public var dismissPermanent: Bool
    public var taskDescription: String?

    enum CodingKeys: String, CodingKey {
        case agentId, workspacePath, displayName, lastSignalFileId, state, lastActiveAt, dismissed, dismissPermanent, taskDescription
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agentId = try c.decode(String.self, forKey: .agentId)
        workspacePath = try c.decode(String.self, forKey: .workspacePath)
        displayName = try c.decode(String.self, forKey: .displayName)
        lastSignalFileId = try c.decodeIfPresent(String.self, forKey: .lastSignalFileId)
        state = try c.decode(String.self, forKey: .state)
        lastActiveAt = try c.decodeIfPresent(Date.self, forKey: .lastActiveAt)
        dismissed = try c.decode(Bool.self, forKey: .dismissed)
        taskDescription = try c.decodeIfPresent(String.self, forKey: .taskDescription)
        if let p = try c.decodeIfPresent(Bool.self, forKey: .dismissPermanent) {
            dismissPermanent = p
        } else {
            // Legacy: dismissed rows were “strong” hides — treat as permanent file ignore.
            dismissPermanent = dismissed
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(agentId, forKey: .agentId)
        try c.encode(workspacePath, forKey: .workspacePath)
        try c.encode(displayName, forKey: .displayName)
        try c.encodeIfPresent(lastSignalFileId, forKey: .lastSignalFileId)
        try c.encode(state, forKey: .state)
        try c.encodeIfPresent(lastActiveAt, forKey: .lastActiveAt)
        try c.encode(dismissed, forKey: .dismissed)
        try c.encode(dismissPermanent, forKey: .dismissPermanent)
        try c.encodeIfPresent(taskDescription, forKey: .taskDescription)
    }

    public init(
        agentId: String,
        workspacePath: String,
        displayName: String,
        lastSignalFileId: String?,
        state: String,
        lastActiveAt: Date?,
        dismissed: Bool,
        dismissPermanent: Bool,
        taskDescription: String?
    ) {
        self.agentId = agentId
        self.workspacePath = workspacePath
        self.displayName = displayName
        self.lastSignalFileId = lastSignalFileId
        self.state = state
        self.lastActiveAt = lastActiveAt
        self.dismissed = dismissed
        self.dismissPermanent = dismissPermanent
        self.taskDescription = taskDescription
    }
}

/// Persistent registry of agent tiles. Manages identity matching across agent turns
/// and stores user-editable display names.
///
/// **Real agents** (Cursor + `cc-signal`): each *stable* signal file id is one tile (`cc-signal` reuses the
/// same JSON name across turns when `CURSOR_TRACE_ID` or `.cursor/command-center-agent-id` applies).
/// Parallel agents in the same folder get separate ids/tiles. Dismiss: snooze or permanent ignore file id.
///
/// **Demo simulation** (`demo-slot-NN.json` only): appearance-only for recordings. Dismiss removes the demo row.
public final class AgentRegistry: @unchecked Sendable {
    private let filePath: URL
    private var entries: [AgentRegistryEntry] = []
    private var tileOrder: [String] = []
    /// Signal file ids (`cc-signal` JSON basename) that must never recreate a tile after permanent dismiss.
    private var permanentlyIgnoredSignalFileIds: Set<String> = []
    private let lock = NSLock()

    public init() {
        self.filePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("command-center-registry.json")
        load()
    }

    // MARK: - Persistence

    private struct RegistryFile: Codable {
        var entries: [AgentRegistryEntry]
        var tileOrder: [String]?
        var permanentlyIgnoredSignalFileIds: [String]?
    }

    private func load() {
        guard let data = try? Data(contentsOf: filePath) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(RegistryFile.self, from: data) {
            entries = file.entries
            tileOrder = file.tileOrder ?? []
            permanentlyIgnoredSignalFileIds = Set(file.permanentlyIgnoredSignalFileIds ?? [])
        } else if let legacy = try? decoder.decode([AgentRegistryEntry].self, from: data) {
            entries = legacy
            tileOrder = []
            permanentlyIgnoredSignalFileIds = []
        }
        for e in entries where e.dismissed && e.dismissPermanent {
            if let fid = e.lastSignalFileId, !fid.isEmpty {
                permanentlyIgnoredSignalFileIds.insert(fid)
            }
        }
        pruneDismissedDemoSlotEntries()
    }

    /// Demo tiles use fixed filenames (`demo-slot-NN`). Old behavior kept dismissed rows, which blocked
    /// those file IDs forever. Remove such rows so a new recording run can recreate demo tiles.
    private func pruneDismissedDemoSlotEntries() {
        let removedAgentIds = entries.compactMap { entry -> String? in
            guard entry.dismissed,
                  let fid = entry.lastSignalFileId,
                  fid.hasPrefix("demo-slot-")
            else { return nil }
            return entry.agentId
        }
        guard !removedAgentIds.isEmpty else { return }
        entries.removeAll {
            $0.dismissed && ($0.lastSignalFileId?.hasPrefix("demo-slot-") ?? false)
        }
        let removed = Set(removedAgentIds)
        tileOrder.removeAll { removed.contains($0) }
        save()
    }

    private func save() {
        let file = RegistryFile(
            entries: entries,
            tileOrder: tileOrder,
            permanentlyIgnoredSignalFileIds: permanentlyIgnoredSignalFileIds.sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(file) else { return }
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
    /// 1. Signal file ID matches a known non-dismissed entry -> update that tile (same inbox JSON / agent session)
    /// 2. Otherwise -> new registry entry for this signal file id
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

        let visibleEntries = entries.filter { !$0.dismissed }
        let tiles = visibleEntries.map { entry in
            AgentTile(
                id: entry.agentId,
                workspacePath: entry.workspacePath,
                displayName: entry.displayName,
                taskDescription: entry.taskDescription,
                agentState: AgentTile.AgentState(rawValue: entry.state) ?? .idle,
                lastActiveAt: entry.lastActiveAt
            )
        }

        guard !tileOrder.isEmpty else { return tiles }
        return tiles.sorted { a, b in
            let ai = tileOrder.firstIndex(of: a.id) ?? Int.max
            let bi = tileOrder.firstIndex(of: b.id) ?? Int.max
            return ai < bi
        }
    }

    private static func normalizeWorkspacePath(_ p: String) -> String {
        URL(fileURLWithPath: p, isDirectory: true).standardizedFileURL.path
    }

    private func matchSignal(_ signal: AgentSignalV2, now: Date, matchedFileIds: inout Set<String>) {
        if matchedFileIds.contains(signal.fileId) { return }

        if !signal.isDemoSimulatedSignal, permanentlyIgnoredSignalFileIds.contains(signal.fileId) {
            matchedFileIds.insert(signal.fileId)
            return
        }

        // Real agents: if this file id was dismissed, ignore (stops respawn from stale JSON on disk).
        // Demo: strip any legacy dismissed rows for this file id so a new recording run can show tiles again.
        if signal.isDemoSimulatedSignal {
            entries.removeAll { $0.dismissed && $0.lastSignalFileId == signal.fileId }
        } else if entries.contains(where: { $0.lastSignalFileId == signal.fileId && $0.dismissed }) {
            matchedFileIds.insert(signal.fileId)
            return
        }

        // Legacy v1 inbox used `legacy-<leaf>` as file id — different folders with the same name collided.
        // Match by workspace path first and migrate `lastSignalFileId` to the stable id.
        if signal.fileId.hasPrefix("legacy-"), !signal.workspacePath.isEmpty {
            let normSig = Self.normalizeWorkspacePath(signal.workspacePath)
            if let idx = entries.firstIndex(where: { !$0.dismissed && Self.normalizeWorkspacePath($0.workspacePath) == normSig }) {
                entries[idx].lastSignalFileId = signal.fileId
                updateEntry(at: idx, from: signal, now: now)
                matchedFileIds.insert(signal.fileId)
                return
            }
        }

        if let idx = entries.firstIndex(where: { $0.lastSignalFileId == signal.fileId && !$0.dismissed }) {
            updateEntry(at: idx, from: signal, now: now)
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
            dismissPermanent: false,
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
        } else if signalState == "waitingForInput" {
            entries[index].state = "waitingForInput"
        } else if signalState == "recentlyCompleted" {
            if entries[index].state == "thinking" || entries[index].state == "waitingForInput" {
                entries[index].state = "recentlyCompleted"
            }
        } else if entries[index].state == "thinking" || entries[index].state == "waitingForInput" {
            entries[index].state = "idle"
        }
    }

    private func stateFromSignal(_ signal: AgentSignalV2, now: Date) -> String {
        if signal.agentTurnActive {
            return "thinking"
        }
        if signal.awaitingInput {
            return "waitingForInput"
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
        if let idx = entries.firstIndex(where: {
            $0.agentId == agentId && ($0.state == "recentlyCompleted" || $0.state == "waitingForInput")
        }) {
            entries[idx].state = "idle"
            save()
        }
    }

    /// - Parameter permanent: If `true`, this signal file id is added to the persistent ignore list (stays hidden even if the registry row is removed later). If `false`, snooze: hide this tile only; the next `cc-signal start` (new JSON file) can show a new tile for the same workspace.
    public func dismiss(agentId: String, permanent: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = entries.firstIndex(where: { $0.agentId == agentId }) else { return }
        let fileId = entries[idx].lastSignalFileId ?? ""
        if fileId.hasPrefix("demo-slot-") {
            entries.remove(at: idx)
            tileOrder.removeAll { $0 == agentId }
        } else {
            entries[idx].dismissed = true
            entries[idx].dismissPermanent = permanent
            if permanent, !fileId.isEmpty {
                permanentlyIgnoredSignalFileIds.insert(fileId)
            }
        }
        save()
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

    public func reorderTiles(orderedIds: [String]) {
        lock.lock()
        defer { lock.unlock() }
        tileOrder = orderedIds
        save()
    }

    /// Returns workspace paths of all non-dismissed entries (for legacy v1 signal scanning).
    public func knownWorkspacePaths() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(Set(entries.filter { !$0.dismissed }.map(\.workspacePath)))
    }
}
