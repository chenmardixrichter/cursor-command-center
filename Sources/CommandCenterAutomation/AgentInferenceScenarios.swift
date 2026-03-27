import CommandCenterCore
import Foundation

/// Headless checks for [`stepAgentState`] (no XCTest in some SwiftPM environments).
enum AgentInferenceScenarios {
    static func runAll() -> [String] {
        var issues: [String] = []
        let cfg = AgentStateInferenceConfig()

        // Idle + noise stays idle
        do {
            var w = AgentInferenceWindowState()
            var state: CursorWindow.AgentState = .idle
            for _ in 0 ..< 30 {
                state = stepAgentState(prior: state, cpuPercent: 0.1, window: &w, config: cfg)
            }
            if state != .idle { issues.append("idle_low_cpu: expected idle, got \(state)") }
            if w.warmAccum != 0 { issues.append("idle_low_cpu: warmAccum should be 0") }
        }

        // Oscillating CPU above the hot threshold should still reach thinking (stop at first `.thinking`)
        do {
            var w = AgentInferenceWindowState()
            var state: CursorWindow.AgentState = .idle
            var pattern: [Double] = []
            for _ in 0 ..< 14 {
                pattern.append(4.0)
                pattern.append(0.5)
            }
            for cpu in pattern {
                state = stepAgentState(prior: state, cpuPercent: cpu, window: &w, config: cfg)
                if state == .thinking { break }
            }
            if state != .thinking {
                issues.append("oscillating_cpu: expected thinking, got \(state)")
            }
        }

        // Thinking exits after cool streak
        do {
            var w = AgentInferenceWindowState()
            var state: CursorWindow.AgentState = .thinking
            for _ in 0 ..< cfg.coolPollsToExitThinking {
                state = stepAgentState(prior: state, cpuPercent: 0, window: &w, config: cfg)
            }
            if state != .recentlyCompleted {
                issues.append("exit_thinking: expected recentlyCompleted, got \(state)")
            }
        }

        // While thinking, only plugin % counts — high “effective” (e.g. DB boost) must not block exit
        do {
            var w = AgentInferenceWindowState()
            var state: CursorWindow.AgentState = .thinking
            for _ in 0 ..< cfg.coolPollsToExitThinking {
                state = stepAgentState(
                    prior: state,
                    cpuEffectivePercent: 15,
                    cpuPluginPercent: 0,
                    window: &w,
                    config: cfg
                )
            }
            if state != .recentlyCompleted {
                issues.append("thinking_ignore_boost: expected recentlyCompleted when plugin cold, got \(state)")
            }
        }

        // Recently completed → idle preserves warm progress
        do {
            var w = AgentInferenceWindowState()
            var state: CursorWindow.AgentState = .recentlyCompleted
            state = stepAgentState(prior: state, cpuPercent: 4.0, window: &w, config: cfg)
            if state != .recentlyCompleted {
                issues.append("recent_done: expected recentlyCompleted after first hot poll from done, got \(state)")
            }
            var steps = 0
            while state != .thinking, steps < 20 {
                state = stepAgentState(prior: state, cpuPercent: 4.0, window: &w, config: cfg)
                steps += 1
            }
            if state != .thinking {
                issues.append("recent_done: failed to re-enter thinking from idle warm")
            }
        }

        // Long quiet then post-reply spike (must NOT enter thinking on 3–4 hot polls only)
        do {
            var w = AgentInferenceWindowState()
            var state: CursorWindow.AgentState = .idle
            for _ in 0 ..< 10 {
                state = stepAgentState(prior: state, cpuPercent: 0.1, window: &w, config: cfg)
            }
            for _ in 0 ..< 4 {
                state = stepAgentState(prior: state, cpuPercent: 8.0, window: &w, config: cfg)
            }
            if state == .thinking {
                issues.append("late_spike_4: expected idle after long idle + 4 hot polls, got thinking")
            }
        }

        // After long idle, five hot polls stay below enter threshold; six crosses it (weak burst + higher bar)
        do {
            var w = AgentInferenceWindowState()
            var state: CursorWindow.AgentState = .idle
            for _ in 0 ..< 10 {
                state = stepAgentState(prior: state, cpuPercent: 0.1, window: &w, config: cfg)
            }
            for _ in 0 ..< 5 {
                state = stepAgentState(prior: state, cpuPercent: 8.0, window: &w, config: cfg)
            }
            if state == .thinking {
                issues.append("late_spike_5: expected idle after 5 hot polls post long idle, got thinking")
            }
        }

        do {
            var w = AgentInferenceWindowState()
            var state: CursorWindow.AgentState = .idle
            for _ in 0 ..< 10 {
                state = stepAgentState(prior: state, cpuPercent: 0.1, window: &w, config: cfg)
            }
            for _ in 0 ..< 6 {
                state = stepAgentState(prior: state, cpuPercent: 8.0, window: &w, config: cfg)
            }
            if state != .thinking {
                issues.append("late_spike_6: expected thinking after 6th hot poll post long idle, got \(state)")
            }
        }

        // Background-ish hum strictly below hot threshold never enters thinking
        do {
            var w = AgentInferenceWindowState()
            var state: CursorWindow.AgentState = .idle
            let hum = cfg.cpuHotThreshold - 0.25
            for _ in 0 ..< 40 {
                state = stepAgentState(prior: state, cpuPercent: hum, window: &w, config: cfg)
            }
            if state == .thinking {
                issues.append("subthreshold_hum: expected idle at \(hum)% sustained, got thinking")
            }
        }

        return issues
    }
}
