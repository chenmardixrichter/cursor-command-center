import CommandCenterCore
import Foundation

@main
struct CommandCenterAutomation {
    static func main() async {
        setbuf(stdout, nil)
        print("CommandCenterAutomation starting…")
        var issues: [String] = []

        // 1) Inbox directory exists / can be created
        AgentSignalInbox.ensureInboxDirectory()
        let inboxPath = AgentSignalInbox.inboxDirectory.path
        if FileManager.default.fileExists(atPath: inboxPath) {
            print("check_inboxDirectory ok (\(inboxPath))")
        } else {
            issues.append("inboxDirectory: could not create \(inboxPath)")
        }

        // 2) Scan inbox (may be empty)
        let signals = AgentSignalInbox.scanInbox()
        print("check_scanInbox signals=\(signals.count)")

        // 3) Registry round-trip
        let registry = AgentRegistry()
        let tiles = registry.processSignals(signals)
        print("check_registry tiles=\(tiles.count)")

        // 4) Poll loop smoke test
        await runPollOnceCheck(&issues)

        if issues.isEmpty {
            print("")
            print("AUTOMATION_OK all checks passed")
            exit(0)
        } else {
            print("")
            print("AUTOMATION_FAIL")
            for i in issues {
                print("ISSUE: \(i)")
            }
            exit(1)
        }
    }

    @MainActor
    private static func runPollOnceCheck(_ issues: inout [String]) async {
        let vm = POCViewModel()
        await vm.pollOnce()
        if vm.statusLine.isEmpty {
            issues.append("pollOnce: statusLine empty")
        } else if !vm.statusLine.contains("updated") {
            issues.append("pollOnce: statusLine missing 'updated': \(vm.statusLine)")
        } else {
            print("check_pollOnce status=\(vm.statusLine)")
        }
    }
}
