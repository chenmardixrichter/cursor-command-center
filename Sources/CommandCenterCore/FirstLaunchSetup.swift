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

    private static let ruleContent = """
    ---
    description: "MANDATORY: Write Command Center agent signal at the START and END of EVERY turn"
    alwaysApply: true
    ---

    # Command Center — agent signal (MANDATORY, EVERY TURN)

    > **YOU MUST RUN THE START SIGNAL BEFORE DOING ANYTHING ELSE.**
    > **This applies to EVERY user message — not just the first one in a conversation.**
    > **If you are unsure whether you already wrote the signal this turn, write it again. Duplicate writes are harmless; missing writes break the dashboard.**

    ## START of turn — mark thinking

    Run this as your **absolute first action** when you receive a user message:

    ```bash
    source ~/.cursor/bin/cc-signal start "BRIEF_TASK_DESCRIPTION"
    ```

    Replace `BRIEF_TASK_DESCRIPTION` with a 3–8 word summary (e.g. "Fixing lint errors", "Reviewing PR changes"). Under 60 chars.

    The `source` command sets `$CC_AGENT_ID` in your shell session so the end signal can find it.

    ## END of turn — mark done

    After all work is finished, right before your final reply:

    ```bash
    ~/.cursor/bin/cc-signal done "BRIEF_TASK_DESCRIPTION"
    ```

    Uses the same `$CC_AGENT_ID` from the start signal automatically.

    ## Rules

    - **EVERY turn. EVERY workspace. No exceptions.** Even trivial tasks. Even plan-mode-only turns. Even clarifying questions.
    - Run `source ~/.cursor/bin/cc-signal start` BEFORE any other shell command or tool call.
    - Run `~/.cursor/bin/cc-signal done` AFTER all work is complete, alongside the osascript notification.
    - If the shell session resets mid-turn and `$CC_AGENT_ID` is lost, generate a new one: `source ~/.cursor/bin/cc-signal start "..."` again.
    - The signal file expires after 5 minutes of no update — if your turn takes longer, the dashboard loses track. For long turns, re-run the start command periodically.
    """

    private static let helperScriptContent = """
    #!/usr/bin/env bash
    # Command Center agent signal helper.
    # Usage:
    #   source cc-signal start "Brief task description"   (sets CC_AGENT_ID in caller's env)
    #   cc-signal done  "Brief task description"           (uses CC_AGENT_ID from env)

    set -uo pipefail

    INBOX="$HOME/.cursor/command-center-agents"
    ENABLED="$INBOX/.enabled"

    # If Command Center has been uninstalled, silently do nothing.
    [[ -f "$ENABLED" ]] || { return 0 2>/dev/null || exit 0; }

    ACTION="${1:-}"
    DESC="${2:-Agent working}"
    DESC="${DESC:0:60}"

    _cc_now() { date -u +%Y-%m-%dT%H:%M:%S.000Z; }

    case "$ACTION" in
      start)
        export CC_AGENT_ID
        CC_AGENT_ID="$(openssl rand -hex 4)"
        mkdir -p "$INBOX"
        cat > "$INBOX/${CC_AGENT_ID}.json" <<SIGNAL
    {"schemaVersion":2,"agentTurnActive":true,"updatedAt":"$(_cc_now)","workspacePath":"$(pwd)","taskDescription":"$DESC"}
    SIGNAL
        ;;
      done)
        if [[ -z "${CC_AGENT_ID:-}" ]]; then
          echo "cc-signal: CC_AGENT_ID not set — did you 'source cc-signal start' first?" >&2
          return 1 2>/dev/null || exit 1
        fi
        local_now="$(_cc_now)"
        cat > "$INBOX/${CC_AGENT_ID}.json" <<SIGNAL
    {"schemaVersion":2,"agentTurnActive":false,"updatedAt":"$local_now","lastResponseCompletedAt":"$local_now","workspacePath":"$(pwd)","taskDescription":"$DESC"}
    SIGNAL
        ;;
      *)
        echo "Usage: source cc-signal start \\"description\\"  |  cc-signal done \\"description\\"" >&2
        return 1 2>/dev/null || exit 1
        ;;
    esac
    """
}
