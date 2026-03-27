import CoreServices
import Foundation

/// Watches **workspace project folders** (not `workspaceStorage`) for edits to source-like files — proxy for “Composer touched the repo,”
/// similar to an inotify watch on `.py` / `.tsx`, but integrated into Command Center instead of playing a sound.
public final class ProjectSourceFSEventWatcher: @unchecked Sendable {
    public static let shared = ProjectSourceFSEventWatcher()

    private let lock = NSLock()
    private var lastEventAtByRoot: [String: Date] = [:]
    private var watchedRoots: [String] = []
    private var stream: FSEventStreamRef?
    private let eventQueue = DispatchQueue(label: "commandcenter.projectsource.fsevents", qos: .utility)

    /// Path extensions to count (no leading dot, lowercased). Adjust to match stacks you care about.
    public var allowedExtensions: Set<String> = [
        "swift", "py", "ts", "tsx", "js", "jsx", "m", "mm", "go", "rs", "kt", "kts",
        "vue", "svelte", "css", "scss", "less", "html", "htm", "md", "mdx", "json",
        "yaml", "yml", "toml", "rb", "php", "cs", "java", "c", "h", "cpp", "cc", "hpp",
    ]

    private let excludePathSubstrings: [String] = [
        "/node_modules/", "/.git/", "/.svn/", "/.build/", "/build/", "/dist/", "/.next/",
        "/.vite/", "/DerivedData/", "/Pods/", "/Carthage/", "/vendor/", "/.gradle/",
        "/target/", "/__pycache__/", "/.venv/", "/venv/", "/.tox/",
    ]

    private init() {}

    public func lastEventDate(forProjectRoot path: String) -> Date? {
        let key = Self.normalizeProjectRoot(path)
        lock.lock()
        defer { lock.unlock() }
        return lastEventAtByRoot[key]
    }

    /// True if a watched source file under this project root was touched within `window` seconds of `now`.
    public func isRecentSourceEdit(forProjectPath path: String?, within window: TimeInterval, now: Date = Date()) -> Bool {
        guard let path, !path.isEmpty else { return false }
        let key = Self.normalizeProjectRoot(path)
        lock.lock()
        defer { lock.unlock() }
        guard let t = lastEventAtByRoot[key] else { return false }
        return now.timeIntervalSince(t) <= window
    }

    /// Point FSEvents at the current set of open workspace roots (from tiles). Recreates the stream when the set changes.
    public func setWatchedProjectRoots(_ paths: [String]) {
        let roots = Self.uniqueExistingRoots(paths)
        lock.lock()
        let prevSet = Set(watchedRoots)
        let nextSet = Set(roots)
        watchedRoots = roots.sorted()
        lastEventAtByRoot = lastEventAtByRoot.filter { nextSet.contains($0.key) }
        lock.unlock()

        guard prevSet != nextSet else { return }

        eventQueue.async { [weak self] in
            self?.restartStream(roots: roots)
        }
    }

    public func start() {
        // Streams are created when setWatchedProjectRoots is first called with non-empty paths.
    }

    private func restartStream(roots: [String]) {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            stream = nil
        }
        guard !roots.isEmpty else { return }

        let pathStrings = roots as NSArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
            guard let clientCallBackInfo, numEvents > 0 else { return }
            let watcher = Unmanaged<ProjectSourceFSEventWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            let arr = unsafeBitCast(eventPaths, to: NSArray.self)
            for i in 0..<numEvents {
                guard let path = arr.object(at: i) as? String else { continue }
                watcher.handleEventPath(path)
            }
        }

        let sinceNow = FSEventStreamEventId(UInt64.max)
        guard
            let s = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                pathStrings,
                sinceNow,
                0.35,
                FSEventStreamCreateFlags(
                    UInt32(kFSEventStreamCreateFlagFileEvents)
                        | UInt32(kFSEventStreamCreateFlagUseCFTypes)
                        | UInt32(kFSEventStreamCreateFlagNoDefer)
                )
            )
        else { return }

        stream = s
        FSEventStreamSetDispatchQueue(s, eventQueue)
        FSEventStreamStart(s)
    }

    private func handleEventPath(_ rawPath: String) {
        let norm = rawPath.replacingOccurrences(of: "\\", with: "/")
        guard shouldCountPath(norm) else { return }

        lock.lock()
        let roots = watchedRoots
        lock.unlock()

        let sortedRoots = roots.sorted { $0.count > $1.count }
        for root in sortedRoots {
            let r = root.hasSuffix("/") ? String(root.dropLast()) : root
            if norm == r || norm.hasPrefix(r + "/") {
                lock.lock()
                lastEventAtByRoot[root] = Date()
                lock.unlock()
                return
            }
        }
    }

    private func shouldCountPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        for ex in excludePathSubstrings {
            if lower.contains(ex) { return false }
        }
        let ext = (path as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        return allowedExtensions.contains(ext)
    }

    private static func normalizeProjectRoot(_ path: String) -> String {
        let u = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var p = u.path
        if p.hasSuffix("/"), p.count > 1 { p.removeLast() }
        return p
    }

    private static func uniqueExistingRoots(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in paths {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = normalizeProjectRoot(trimmed)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: key, isDirectory: &isDir), isDir.boolValue else { continue }
            guard seen.insert(key).inserted else { continue }
            out.append(key)
        }
        return out
    }
}
