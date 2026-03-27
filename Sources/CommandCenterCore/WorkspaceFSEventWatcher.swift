import CoreServices
import Foundation

/// Watches Cursor `workspaceStorage` trees via FSEvents and records recent write activity per **workspace storage hash**
/// (folder name under `…/workspaceStorage/<hash>/…`). Used as a **medium-confidence** “Thinking” signal when the
/// Stop/Cancel control isn’t visible (e.g. minimized window).
public final class WorkspaceFSEventWatcher: @unchecked Sendable {
    public static let shared = WorkspaceFSEventWatcher()

    private let lock = NSLock()
    private var lastEventAtByHash: [String: Date] = [:]
    private var stream: FSEventStreamRef?
    private let eventQueue = DispatchQueue(label: "commandcenter.workspace.fsevents", qos: .utility)

    private init() {}

    public func lastEventDate(forWorkspaceStorageHash hash: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return lastEventAtByHash[hash]
    }

    /// True if any filesystem event was recorded for this hash within `window` seconds of `now`.
    public func isRecentActivity(forWorkspaceStorageHash hash: String, within window: TimeInterval, now: Date = Date()) -> Bool {
        guard let t = lastEventDate(forWorkspaceStorageHash: hash) else { return false }
        return now.timeIntervalSince(t) <= window
    }

    public func start() {
        lock.lock()
        if stream != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        let paths = CursorDiscovery.workspaceStorageBaseDirectoryURLs()
            .map(\.path)
            .filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }

        let pathArray = paths as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
            guard let clientCallBackInfo else { return }
            let watcher = Unmanaged<WorkspaceFSEventWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            guard numEvents > 0 else { return }
            let arr = unsafeBitCast(eventPaths, to: NSArray.self)
            for i in 0..<numEvents {
                guard let path = arr.object(at: i) as? String else { continue }
                guard !WorkspaceFSEventWatcher.isEditorStateNoise(path) else { continue }
                if let hash = WorkspaceFSEventWatcher.hashSegment(fromWorkspaceStoragePath: path) {
                    DiagnosticLog.log("FS_EVENT hash=\(hash) path=\((path as NSString).lastPathComponent)")
                    watcher.record(hash: hash)
                }
            }
        }

        let sinceNow = FSEventStreamEventId(UInt64.max)
        guard
            let s = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                pathArray,
                sinceNow,
                0.35,
                FSEventStreamCreateFlags(
                    UInt32(kFSEventStreamCreateFlagFileEvents)
                        | UInt32(kFSEventStreamCreateFlagUseCFTypes)
                        | UInt32(kFSEventStreamCreateFlagNoDefer)
                )
            )
        else { return }

        lock.lock()
        stream = s
        lock.unlock()

        FSEventStreamSetDispatchQueue(s, eventQueue)
        FSEventStreamStart(s)
    }

    private func record(hash: String) {
        lock.lock()
        lastEventAtByHash[hash] = Date()
        lock.unlock()
    }

    /// Files Cursor writes on every keystroke / navigation — not agent activity.
    private static let noiseFilenames: Set<String> = [
        "state.vscdb",
        "state.vscdb.backup",
        "state.vscdb-journal",
        "state.vscdb-wal",
        "state.vscdb-shm",
        "backup.vscdb",
        "backup.vscdb-journal",
        "backup.vscdb-wal",
        "backup.vscdb-shm",
    ]

    /// True for paths that are normal editor state writes, not agent activity.
    static func isEditorStateNoise(_ path: String) -> Bool {
        let filename = (path as NSString).lastPathComponent.lowercased()
        return noiseFilenames.contains(filename)
    }

    /// `…/workspaceStorage/<hash>/…` → `hash`
    public static func hashSegment(fromWorkspaceStoragePath path: String) -> String? {
        let norm = path.replacingOccurrences(of: "\\", with: "/")
        guard let range = norm.range(of: "/workspaceStorage/", options: .caseInsensitive) else { return nil }
        let after = norm[range.upperBound...]
        let part = after.split(separator: "/").first.map(String.init) ?? ""
        guard !part.isEmpty, part != "..", part != "." else { return nil }
        return part
    }
}
