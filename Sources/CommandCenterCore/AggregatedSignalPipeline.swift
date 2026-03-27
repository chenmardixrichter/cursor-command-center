import Foundation

/// Which tier last justified **Thinking** for UI badges.
public enum AgentSignalTier: String, Equatable, Sendable {
    case none
    /// Accessibility: Composer interrupt **Stop** visible.
    case high
    /// FSEvents: recent writes under workspace storage hash, or under the project folder (source extensions).
    case medium
    /// Pulse / AppleScript hints.
    case low
}

public struct AggregatedSignalConfig: Equatable, Sendable {
    public var fsRecentWindowSeconds: TimeInterval
    public var pulseCpuThreshold: Double
    public var pulseSustainPolls: Int
    public var coolPollsToDone: Int
    public var minimumSecondsInThinkingBeforeDone: TimeInterval
    /// When `true`, recent edits to source files under the workspace folder count toward “thinking.” **Default `false`:** indexers / formatters / multi-repo activity caused many false positives.
    public var countProjectSourceEditsAsThinking: Bool

    public init(
        fsRecentWindowSeconds: TimeInterval = 2.5,
        pulseCpuThreshold: Double = 5.0,
        pulseSustainPolls: Int = 2,
        coolPollsToDone: Int = 12,
        minimumSecondsInThinkingBeforeDone: TimeInterval = 4.0,
        countProjectSourceEditsAsThinking: Bool = false
    ) {
        self.fsRecentWindowSeconds = fsRecentWindowSeconds
        self.pulseCpuThreshold = pulseCpuThreshold
        self.pulseSustainPolls = pulseSustainPolls
        self.coolPollsToDone = coolPollsToDone
        self.minimumSecondsInThinkingBeforeDone = minimumSecondsInThinkingBeforeDone
        self.countProjectSourceEditsAsThinking = countProjectSourceEditsAsThinking
    }
}

/// Per-tile runtime for aggregated transitions (extension/cloud short-circuit before this runs).
public struct AggregatedTileRuntimeState: Equatable, Sendable {
    public var pulseStreak: Int = 0
    public var coolPollsAfterThinkingDrop: Int = 0
    public var thinkingEnteredAt: Date?
    public var doneEnteredAt: Date?
    /// While **Thinking**, keep showing tier badges during cooldown polls where `thinkingClass` is briefly false.
    public var lastTierBadge: AgentSignalTier = .none
}

public enum AggregatedSignalPipeline {
    public static func updatePulseStreak(
        priorStreak: Int,
        pluginCpuPercent: Double,
        config: AggregatedSignalConfig
    ) -> Int {
        if pluginCpuPercent >= config.pulseCpuThreshold {
            return priorStreak + 1
        }
        return 0
    }

    public static func pulseSustained(streak: Int, config: AggregatedSignalConfig) -> Bool {
        streak >= config.pulseSustainPolls
    }

    public static func step(
        prior: CursorWindow.AgentState,
        runtime: inout AggregatedTileRuntimeState,
        thinkingClassSignal: Bool,
        config: AggregatedSignalConfig,
        now: Date = Date()
    ) -> CursorWindow.AgentState {
        if thinkingClassSignal {
            if prior != .thinking {
                runtime.thinkingEnteredAt = now
            }
            runtime.coolPollsAfterThinkingDrop = 0
            runtime.doneEnteredAt = nil
            return .thinking
        }

        switch prior {
        case .thinking:
            let dwell: TimeInterval = {
                guard let t = runtime.thinkingEnteredAt else {
                    return config.minimumSecondsInThinkingBeforeDone
                }
                return now.timeIntervalSince(t)
            }()
            if dwell < config.minimumSecondsInThinkingBeforeDone {
                runtime.coolPollsAfterThinkingDrop = 0
                return .thinking
            }
            runtime.coolPollsAfterThinkingDrop += 1
            if runtime.coolPollsAfterThinkingDrop >= config.coolPollsToDone {
                runtime.coolPollsAfterThinkingDrop = 0
                runtime.thinkingEnteredAt = nil
                runtime.doneEnteredAt = now
                return .recentlyCompleted
            }
            return .thinking

        case .recentlyCompleted:
            return .recentlyCompleted

        case .idle:
            return .idle
        }
    }

    public static func strongestTier(
        axStop: Bool,
        fsRecent: Bool,
        projectSourceRecent: Bool,
        pulse: Bool,
        scriptHint: Bool
    ) -> AgentSignalTier {
        if axStop { return .high }
        if fsRecent || projectSourceRecent { return .medium }
        if pulse || scriptHint { return .low }
        return .none
    }

    public static func scriptThinkingHint(tile: CursorWindow, windowTitles: [String]) -> Bool {
        for t in windowTitles {
            let leaf = tile.leafName
            let pathBase = (tile.projectPath.map { ($0 as NSString).lastPathComponent }) ?? ""
            let matches =
                (leaf.count >= 2 && t.localizedCaseInsensitiveContains(leaf))
                || (pathBase.count >= 2 && t.localizedCaseInsensitiveContains(pathBase))
                || (tile.projectName.count >= 2 && t.localizedCaseInsensitiveContains(tile.projectName))
            guard matches else { continue }
            let u = t.lowercased()
            // "…" at end or standalone = progress indicator (not normal title separator).
            // "—" alone is a normal Cursor title separator ("file — workspace — Cursor") — do NOT match it.
            if u.hasSuffix("…") || u.contains("…\u{00a0}") || u.contains("… ") { return true }
            if u.contains("generating") || u.contains("planning") { return true }
            if u.contains("streaming") || u.contains("responding") || u.contains("processing") { return true }
        }
        return false
    }
}
