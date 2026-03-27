import Foundation

public enum FirstLaunchSetup {

    // MARK: - Public paths

    public static let cursorRulesDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cursor/rules", isDirectory: true)
    public static let cursorBinDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cursor/bin", isDirectory: true)
    public static let ruleFile = cursorRulesDir.appendingPathComponent("command-center-signal.mdc")
    public static let helperScript = cursorBinDir.appendingPathComponent("cc-signal")
    public static let enabledMarker = AgentSignalInbox.inboxDirectory.appendingPathComponent(".enabled")

    // MARK: - Status checks

    public static var isRuleInstalled: Bool {
        FileManager.default.fileExists(atPath: ruleFile.path)
    }

    public static var isHelperInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: helperScript.path)
    }

    public static var isInboxReady: Bool {
        FileManager.default.fileExists(atPath: AgentSignalInbox.inboxDirectory.path)
    }

    public static var isMarkerPresent: Bool {
        FileManager.default.fileExists(atPath: enabledMarker.path)
    }

    public static var isFullySetUp: Bool {
        isRuleInstalled && isHelperInstalled && isInboxReady && isMarkerPresent
    }

    // MARK: - Setup

    public struct SetupResult {
        public var ruleInstalled = false
        public var helperInstalled = false
        public var inboxCreated = false
        public var errors: [String] = []

        public var success: Bool { errors.isEmpty }
    }

    @discardableResult
    public static func performSetup() -> SetupResult {
        var result = SetupResult()
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: cursorRulesDir, withIntermediateDirectories: true)
            try ruleContent.write(to: ruleFile, atomically: true, encoding: .utf8)
            result.ruleInstalled = true
        } catch {
            result.errors.append("Cursor rule: \(error.localizedDescription)")
        }

        do {
            try fm.createDirectory(at: cursorBinDir, withIntermediateDirectories: true)
            try helperScriptContent.write(to: helperScript, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperScript.path)
            result.helperInstalled = true
        } catch {
            result.errors.append("Helper script: \(error.localizedDescription)")
        }

        do {
            try fm.createDirectory(at: AgentSignalInbox.inboxDirectory, withIntermediateDirectories: true)
            fm.createFile(atPath: enabledMarker.path, contents: Data("1\n".utf8))
            result.inboxCreated = true
        } catch {
            result.errors.append("Signal inbox: \(error.localizedDescription)")
        }

        return result
    }

    // MARK: - Uninstall

    public static func performUninstall() {
        let fm = FileManager.default
        try? fm.removeItem(at: ruleFile)
        try? fm.removeItem(at: helperScript)
        try? fm.removeItem(at: AgentSignalInbox.inboxDirectory)

        let registry = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/command-center-registry.json")
        try? fm.removeItem(at: registry)
    }

    // MARK: - Embedded file contents

    private static var ruleContent: String {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/rules/command-center-signal.mdc")
        if let existing = try? String(contentsOf: url, encoding: .utf8), !existing.isEmpty {
            return existing
        }
        return fallbackRuleContent
    }

    private static var helperScriptContent: String {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/bin/cc-signal")
        if let existing = try? String(contentsOf: url, encoding: .utf8), !existing.isEmpty {
            return existing
        }
        return fallbackHelperContent
    }

    private static let fallbackRuleContent = """
    ---
    description: "MANDATORY: Write Command Center agent signal at the START and END of EVERY turn"
    alwaysApply: true
    ---
    # Command Center — agent signal (MANDATORY, EVERY TURN)
    Run `source ~/.cursor/bin/cc-signal start "description"` at the START of every turn.
    Run `~/.cursor/bin/cc-signal done "description"` or `~/.cursor/bin/cc-signal waiting "description"` at the END.
    """

    private static let fallbackHelperContent = """
    #!/usr/bin/env bash
    set -uo pipefail
    INBOX="$HOME/.cursor/command-center-agents"
    ENABLED="$INBOX/.enabled"
    [[ -f "$ENABLED" ]] || { return 0 2>/dev/null || exit 0; }
    ACTION="${1:-}"; DESC="${2:-Agent working}"; DESC="${DESC:0:60}"
    _cc_now() { date -u +%Y-%m-%dT%H:%M:%S.000Z; }
    case "$ACTION" in
      start) export CC_AGENT_ID; CC_AGENT_ID="$(openssl rand -hex 4)"; mkdir -p "$INBOX"
        cat > "$INBOX/${CC_AGENT_ID}.json" <<S
    {"schemaVersion":2,"agentTurnActive":true,"updatedAt":"$(_cc_now)","workspacePath":"$(pwd)","taskDescription":"$DESC"}
    S
        ;;
      done) [[ -z "${CC_AGENT_ID:-}" ]] && { echo "No CC_AGENT_ID" >&2; return 1 2>/dev/null || exit 1; }
        local_now="$(_cc_now)"; cat > "$INBOX/${CC_AGENT_ID}.json" <<S
    {"schemaVersion":2,"agentTurnActive":false,"updatedAt":"$local_now","lastResponseCompletedAt":"$local_now","workspacePath":"$(pwd)","taskDescription":"$DESC"}
    S
        ;;
      waiting) [[ -z "${CC_AGENT_ID:-}" ]] && { echo "No CC_AGENT_ID" >&2; return 1 2>/dev/null || exit 1; }
        local_now="$(_cc_now)"; cat > "$INBOX/${CC_AGENT_ID}.json" <<S
    {"schemaVersion":2,"agentTurnActive":false,"awaitingInput":true,"updatedAt":"$local_now","workspacePath":"$(pwd)","taskDescription":"$DESC"}
    S
        ;;
      *) echo "Usage: source cc-signal start|done|waiting desc" >&2; return 1 2>/dev/null || exit 1 ;;
    esac
    """
}
