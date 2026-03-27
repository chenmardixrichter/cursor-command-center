import Foundation

public struct CursorWindow: Identifiable, Equatable, @unchecked Sendable {
    public let id: Int
    public let pid: Int32
    public var projectName: String
    public var projectPath: String?
    /// `workspaceStorage/<hash>` folder name; used for `state.vscdb` activity.
    public let storageFolderHash: String?
    public var agentState: AgentState = .idle
    /// True when [`CommandCenterAgentSignalReader`] says `agentTurnActive` (companion extension); overrides inferred CPU state for display.
    public var extensionAgentTurnOverride: Bool = false
    /// True when [Cursor Cloud Agents API](https://cursor.com/docs/background-agent/api/endpoints) reports a non-terminal `status` for the configured agent id.
    public var cloudAgentTurnOverride: Bool = false
    /// Last aggregated signal tier (AX / FSEvents / pulse); `.none` when extension or cloud override drives the tile.
    public var signalTier: AgentSignalTier = .none

    /// High-level status for the workspace tile.
    ///
    /// **Product meaning:** `.thinking` is the same notion as in Cursor’s chat when you’ve sent a new message and it is **still queued** or the agent is **actively working on that turn**—for as long as that UI state lasts, this tile should read `thinking`.
    ///
    /// **Implementation today:** Values are *inferred* from extension-host CPU and `state.vscdb` activity (`AgentStateInference`), not from Cursor’s internal queue. A future Cursor extension (or official API) is needed for a faithful match.
    public enum AgentState: String {
        case idle
        case thinking
        case recentlyCompleted
    }

    public init(
        id: Int,
        pid: Int32,
        projectName: String,
        projectPath: String?,
        storageFolderHash: String? = nil,
        agentState: AgentState = .idle,
        extensionAgentTurnOverride: Bool = false,
        cloudAgentTurnOverride: Bool = false,
        signalTier: AgentSignalTier = .none
    ) {
        self.id = id
        self.pid = pid
        self.projectName = projectName
        self.projectPath = projectPath
        self.storageFolderHash = storageFolderHash
        self.agentState = agentState
        self.extensionAgentTurnOverride = extensionAgentTurnOverride
        self.cloudAgentTurnOverride = cloudAgentTurnOverride
        self.signalTier = signalTier
    }

    public var leafName: String {
        if let path = projectPath, !path.isEmpty {
            return (path as NSString).lastPathComponent
        }
        return projectName
    }
}
