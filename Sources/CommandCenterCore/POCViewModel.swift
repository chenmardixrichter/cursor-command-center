import Combine
import Foundation

@MainActor
public final class POCViewModel: ObservableObject {
    @Published public private(set) var tiles: [AgentTile] = []
    @Published public private(set) var statusLine: String = ""

    public let pollInterval: TimeInterval = 1.0

    public init() {}

    private let registry = AgentRegistry()
    private var pollTask: Task<Void, Never>?
    private var lastCleanup: Date = .distantPast

    public func start() {
        AgentSignalInbox.ensureInboxDirectory()
        statusLine = "Scanning agent inbox…"
        pollTask?.cancel()
        pollTask = Task.detached { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func refreshNow() {
        statusLine = "Refreshing…"
        Task.detached { [weak self] in
            await self?.pollOnce()
        }
    }

    public func dismiss(agentId: String) {
        registry.dismiss(agentId: agentId)
        tiles.removeAll { $0.id == agentId }
    }

    public func setDisplayName(_ name: String, forAgentId agentId: String) {
        registry.setDisplayName(name, forAgentId: agentId)
        if let idx = tiles.firstIndex(where: { $0.id == agentId }) {
            tiles[idx].displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public func acknowledgeDone(forAgentId agentId: String) {
        guard let idx = tiles.firstIndex(where: { $0.id == agentId }) else { return }
        guard tiles[idx].agentState == .recentlyCompleted else { return }
        tiles[idx].agentState = .idle
        registry.acknowledgeDone(agentId: agentId)
    }

    public func pollOnce() async {
        let now = Date()

        let v2Signals = AgentSignalInbox.scanInbox(now: now)

        // Backward compat: read v1 signal files from workspaces already in the registry
        var legacySignals: [AgentSignalV2] = []
        let knownPaths = registry.knownWorkspacePaths()
        for path in knownPaths {
            if let sig = AgentSignalInbox.readLegacySignal(workspacePath: path, now: now) {
                let alreadyCoveredByV2 = v2Signals.contains { $0.workspacePath == path }
                if !alreadyCoveredByV2 {
                    legacySignals.append(sig)
                }
            }
        }

        let allSignals = v2Signals + legacySignals
        let newTiles = registry.processSignals(allSignals, now: now)

        tiles = newTiles

        // Periodic cleanup (every 30 minutes)
        if now.timeIntervalSince(lastCleanup) > 1800 {
            AgentSignalInbox.cleanupStaleFiles()
            lastCleanup = now
        }

        let thinking = tiles.filter { $0.agentState == .thinking }.count
        let done = tiles.filter { $0.agentState == .recentlyCompleted }.count
        let idle = tiles.filter { $0.agentState == .idle }.count
        let time = DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .medium)

        DiagnosticLog.section("POLL", [
            "v2 signals: \(v2Signals.count) · legacy: \(legacySignals.count) · tiles: \(tiles.count)",
            "thinking: \(thinking) · done: \(done) · idle: \(idle)",
        ])

        statusLine = "agents: \(tiles.count) · thinking: \(thinking) · done: \(done) · idle: \(idle) · v2: \(v2Signals.count) · legacy: \(legacySignals.count) · updated \(time)"
        if tiles.isEmpty {
            statusLine += " — no agents registered yet"
        }
    }
}
