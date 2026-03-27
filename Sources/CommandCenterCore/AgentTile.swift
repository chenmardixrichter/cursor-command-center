import Foundation

public struct AgentTile: Identifiable, Equatable, Sendable {
    public let id: String
    public var workspacePath: String
    public var displayName: String
    public var taskDescription: String?
    public var agentState: AgentState
    public var lastActiveAt: Date?

    public enum AgentState: String, Sendable {
        case idle
        case thinking
        case waitingForInput
        case recentlyCompleted
    }

    public var leafName: String {
        (workspacePath as NSString).lastPathComponent
    }

    public init(
        id: String,
        workspacePath: String,
        displayName: String,
        taskDescription: String? = nil,
        agentState: AgentState = .idle,
        lastActiveAt: Date? = nil
    ) {
        self.id = id
        self.workspacePath = workspacePath
        self.displayName = displayName
        self.taskDescription = taskDescription
        self.agentState = agentState
        self.lastActiveAt = lastActiveAt
    }
}
