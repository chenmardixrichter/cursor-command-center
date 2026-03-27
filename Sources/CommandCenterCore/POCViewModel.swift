import Combine
import Foundation

@MainActor
public final class POCViewModel: ObservableObject {
    @Published public private(set) var tiles: [AgentTile] = []
    @Published public private(set) var statusLine: String = ""

    /// Set when GitHub `releases/latest` is newer than this build (and not dismissed for that version).
    @Published public private(set) var updateOffer: ReleaseUpdateOffer?
    @Published public private(set) var isDownloadingUpdate = false

    public let pollInterval: TimeInterval = 1.0

    private static let dismissedUpdateVersionKey = "commandCenter.dismissedUpdateVersion"
    private var updateCheckTask: Task<Void, Never>?

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
        updateCheckTask?.cancel()
        updateCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            await self?.refreshUpdateOffer()
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        updateCheckTask?.cancel()
        updateCheckTask = nil
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
        guard tiles[idx].agentState == .recentlyCompleted || tiles[idx].agentState == .waitingForInput else { return }
        tiles[idx].agentState = .idle
        registry.acknowledgeDone(agentId: agentId)
    }

    public func moveTile(fromId: String, toId: String) {
        guard let fromIndex = tiles.firstIndex(where: { $0.id == fromId }),
              let toIndex = tiles.firstIndex(where: { $0.id == toId }),
              fromIndex != toIndex else { return }
        let tile = tiles.remove(at: fromIndex)
        tiles.insert(tile, at: toIndex)
        registry.reorderTiles(orderedIds: tiles.map(\.id))
    }


    public func dismissUpdateBanner() {
        if let offer = updateOffer {
            UserDefaults.standard.set(offer.version, forKey: Self.dismissedUpdateVersionKey)
            updateOffer = nil
        }
    }

    /// Fetches GitHub latest release; shows banner only if newer than this app and not dismissed for that version.
    public func refreshUpdateOffer() async {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard let offer = await ReleaseUpdateCheck.fetchUpdateIfNewer(currentVersion: v) else {
            updateOffer = nil
            return
        }
        let dismissed = UserDefaults.standard.string(forKey: Self.dismissedUpdateVersionKey)
        if dismissed == offer.version {
            updateOffer = nil
        } else {
            updateOffer = offer
        }
    }

    @MainActor
    public func downloadUpdateArtifact() async throws -> URL {
        guard let offer = updateOffer else {
            throw URLError(.cancelled)
        }
        isDownloadingUpdate = true
        defer { isDownloadingUpdate = false }
        return try await ReleaseUpdateCheck.downloadZip(from: offer.downloadURL)
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
