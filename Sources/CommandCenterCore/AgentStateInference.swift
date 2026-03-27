import Foundation

/// **Proxy** inference for “agent working on your turn” (see [`CursorWindow.AgentState`]).
/// True “thinking” = Cursor chat with a **queued** user message / agent still processing that turn; this module does **not** read that state—only `ps` + optional DB boosts—so results can diverge from the editor.
///
/// CPU-only inference of agent activity from extension-host `%cpu` sums per workspace.
/// Uses a **warm accumulator** so brief dips below the threshold do not zero progress (fixes “idle while working”).
/// After a **long idle** (many consecutive cool polls), the first hot polls add **+1** each so a **late post-reply CPU spike**
/// cannot jump straight to `.thinking` (fixes “thinking when done”).
/// Defaults use a **2%** hot band and **7** warm points to enter. While `.thinking`, use **plugin-only** % for “hot” so DB-activity boosts do not trap the tile in thinking.
/// Exiting thinking requires consecutive cool polls; `.recentlyCompleted` only becomes `.idle` after consecutive **cool** polls (not while “hot” is rebuilding warm).
public struct AgentStateInferenceConfig: Equatable, Sendable {
    /// Raw `%cpu` sum must meet or exceed this to count as “hot” for this poll (default 2%: extension-host often low while the model runs elsewhere).
    public var cpuHotThreshold: Double
    /// When not `.thinking`, each hot poll adds this much toward entering thinking (unless weak burst applies).
    public var warmIncrementOnHot: Int
    /// When not `.thinking`, each non-hot poll subtracts this much (floor at 0).
    public var warmDecrementOnCool: Int
    /// `warmAccum` needed to transition idle/recentlyCompleted → `.thinking`.
    public var warmAccumToEnterThinking: Int
    /// Cap so one long spike cannot enter without sustained activity.
    public var warmAccumMax: Int
    /// Consecutive non-hot (plugin-only) polls while `.thinking` before → `.recentlyCompleted` (default 2 for faster “done”).
    public var coolPollsToExitThinking: Int
    /// Cool polls while on `.recentlyCompleted` before → `.idle` (default 1).
    public var minPollsRecentlyCompletedBeforeIdle: Int
    /// This many consecutive cool polls (while idle) counts as “long idle”; the next hot burst uses weak increments first.
    public var longIdleColdPollsThreshold: Int
    /// After leaving `.thinking`, ignore `state.vscdb` activity boost for this many polls (~2s each) so the tile doesn’t jump back to “thinking” from editor noise.
    public var postThinkingActivityBoostSuppressPolls: Int

    public init(
        cpuHotThreshold: Double = 2.0,
        warmIncrementOnHot: Int = 2,
        warmDecrementOnCool: Int = 1,
        warmAccumToEnterThinking: Int = 7,
        warmAccumMax: Int = 14,
        coolPollsToExitThinking: Int = 2,
        minPollsRecentlyCompletedBeforeIdle: Int = 1,
        longIdleColdPollsThreshold: Int = 6,
        postThinkingActivityBoostSuppressPolls: Int = 18
    ) {
        self.cpuHotThreshold = cpuHotThreshold
        self.warmIncrementOnHot = warmIncrementOnHot
        self.warmDecrementOnCool = warmDecrementOnCool
        self.warmAccumToEnterThinking = warmAccumToEnterThinking
        self.warmAccumMax = warmAccumMax
        self.coolPollsToExitThinking = coolPollsToExitThinking
        self.minPollsRecentlyCompletedBeforeIdle = minPollsRecentlyCompletedBeforeIdle
        self.longIdleColdPollsThreshold = longIdleColdPollsThreshold
        self.postThinkingActivityBoostSuppressPolls = postThinkingActivityBoostSuppressPolls
    }
}

/// Per-window state for [`stepAgentState`] (not `@MainActor`; safe to use from inference tests).
public struct AgentInferenceWindowState: Equatable, Sendable {
    public var warmAccum: Int = 0
    public var coolWhileThinking: Int = 0
    /// Consecutive cool polls while idle / recently completed (resets on hot).
    public var idleColdPolls: Int = 0
    /// After long idle, counts consecutive hot polls in the current burst: 1–4 → +1 each; 5+ → full increment.
    public var weakHotBurstCount: Int = 0
    /// Polls spent in `.recentlyCompleted` before we may show `.idle`.
    public var pollsInRecentlyCompleted: Int = 0
    /// While > 0, [`CursorDiscovery.effectiveCpuPercent`] should ignore `state.vscdb` boost (counts down each idle/done poll).
    public var suppressActivityBoostPollsRemaining: Int = 0

    public init(
        warmAccum: Int = 0,
        coolWhileThinking: Int = 0,
        idleColdPolls: Int = 0,
        weakHotBurstCount: Int = 0,
        pollsInRecentlyCompleted: Int = 0,
        suppressActivityBoostPollsRemaining: Int = 0
    ) {
        self.warmAccum = warmAccum
        self.coolWhileThinking = coolWhileThinking
        self.idleColdPolls = idleColdPolls
        self.weakHotBurstCount = weakHotBurstCount
        self.pollsInRecentlyCompleted = pollsInRecentlyCompleted
        self.suppressActivityBoostPollsRemaining = suppressActivityBoostPollsRemaining
    }
}

/// Single step: update `window` and return the new [`CursorWindow.AgentState`].
/// - `cpuEffectivePercent`: plugin CPU + activity boost — used to **enter** thinking from idle.
/// - `cpuPluginPercent`: extension-host CPU only — used to **stay** in thinking (so `state.vscdb` boost cannot block “done”).
public func stepAgentState(
    prior: CursorWindow.AgentState,
    cpuEffectivePercent: Double,
    cpuPluginPercent: Double,
    window: inout AgentInferenceWindowState,
    config: AgentStateInferenceConfig
) -> CursorWindow.AgentState {
    let hotEnter = cpuEffectivePercent >= config.cpuHotThreshold
    let hotThinking = cpuPluginPercent >= config.cpuHotThreshold

    switch prior {
    case .thinking:
        if hotThinking {
            window.coolWhileThinking = 0
            return .thinking
        }
        window.coolWhileThinking += 1
        if window.coolWhileThinking >= config.coolPollsToExitThinking {
            window.coolWhileThinking = 0
            window.warmAccum = 0
            window.idleColdPolls = 0
            window.weakHotBurstCount = 0
            window.pollsInRecentlyCompleted = 0
            window.suppressActivityBoostPollsRemaining = config.postThinkingActivityBoostSuppressPolls
            return .recentlyCompleted
        }
        return .thinking

    case .recentlyCompleted:
        if hotEnter {
            window.pollsInRecentlyCompleted = 0
            let longIdle = window.idleColdPolls >= config.longIdleColdPollsThreshold
            let inc: Int
            if longIdle {
                window.weakHotBurstCount = 1
                inc = 1
            } else if window.weakHotBurstCount > 0 {
                window.weakHotBurstCount += 1
                inc = window.weakHotBurstCount <= 4 ? 1 : config.warmIncrementOnHot
            } else {
                inc = config.warmIncrementOnHot
            }
            window.warmAccum = min(config.warmAccumMax, window.warmAccum + inc)
            window.idleColdPolls = 0
        } else {
            window.idleColdPolls += 1
            window.weakHotBurstCount = 0
            window.warmAccum = max(0, window.warmAccum - config.warmDecrementOnCool)
            window.pollsInRecentlyCompleted += 1
        }

        if window.warmAccum >= config.warmAccumToEnterThinking {
            window.warmAccum = hotEnter ? config.warmIncrementOnHot : 0
            window.coolWhileThinking = 0
            window.idleColdPolls = 0
            window.weakHotBurstCount = 0
            window.pollsInRecentlyCompleted = 0
            window.suppressActivityBoostPollsRemaining = 0
            return .thinking
        }
        if !hotEnter, window.pollsInRecentlyCompleted >= config.minPollsRecentlyCompletedBeforeIdle {
            window.pollsInRecentlyCompleted = 0
            if window.suppressActivityBoostPollsRemaining > 0 {
                window.suppressActivityBoostPollsRemaining -= 1
            }
            return .idle
        }
        if window.suppressActivityBoostPollsRemaining > 0 {
            window.suppressActivityBoostPollsRemaining -= 1
        }
        return .recentlyCompleted

    case .idle:
        if hotEnter {
            let longIdle = window.idleColdPolls >= config.longIdleColdPollsThreshold
            let inc: Int
            if longIdle {
                window.weakHotBurstCount = 1
                inc = 1
            } else if window.weakHotBurstCount > 0 {
                window.weakHotBurstCount += 1
                inc = window.weakHotBurstCount <= 4 ? 1 : config.warmIncrementOnHot
            } else {
                inc = config.warmIncrementOnHot
            }
            window.warmAccum = min(config.warmAccumMax, window.warmAccum + inc)
            window.idleColdPolls = 0
        } else {
            window.idleColdPolls += 1
            window.weakHotBurstCount = 0
            window.warmAccum = max(0, window.warmAccum - config.warmDecrementOnCool)
        }

        if window.warmAccum >= config.warmAccumToEnterThinking {
            window.warmAccum = hotEnter ? config.warmIncrementOnHot : 0
            window.coolWhileThinking = 0
            window.idleColdPolls = 0
            window.weakHotBurstCount = 0
            window.pollsInRecentlyCompleted = 0
            window.suppressActivityBoostPollsRemaining = 0
            return .thinking
        }
        if window.suppressActivityBoostPollsRemaining > 0 {
            window.suppressActivityBoostPollsRemaining -= 1
        }
        return .idle
    }
}

/// Tests and simple simulations: same value for effective and plugin CPU.
public func stepAgentState(
    prior: CursorWindow.AgentState,
    cpuPercent: Double,
    window: inout AgentInferenceWindowState,
    config: AgentStateInferenceConfig
) -> CursorWindow.AgentState {
    return stepAgentState(
        prior: prior,
        cpuEffectivePercent: cpuPercent,
        cpuPluginPercent: cpuPercent,
        window: &window,
        config: config
    )
}
