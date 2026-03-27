import AppKit
import Foundation

// MARK: - Workspace entries (disk)

public struct WorkspaceEntry: Equatable, Sendable {
    public let hash: String
    public let folderPath: String
    public let leaf: String
    public let modified: Date

    public init(hash: String, folderPath: String, leaf: String, modified: Date) {
        self.hash = hash
        self.folderPath = folderPath
        self.leaf = leaf
        self.modified = modified
    }
}

public enum CursorDiscovery {
    private enum CursorProcessInfo {
        static let bundleID = "com.todesktop.230313mzl4w4u92"
    }

    public static func applicationSupportPathForDiagnostics() -> String {
        userApplicationSupportDirectoryURL().path
    }

    private static func userApplicationSupportDirectoryURL() -> URL {
        if let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return u.standardizedFileURL
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    /// `includeSlowScans: false` skips recursive `subpathsOfDirectory` under `Cursor*` and full sandbox container walks
    /// (those can block a very long time and made the UI look permanently stuck).
    public static func loadWorkspaceEntries(includeSlowScans: Bool = true) -> [WorkspaceEntry] {
        let appSupport = userApplicationSupportDirectoryURL()
        let storageSubpaths = [
            "Cursor/User/workspaceStorage",
            "Cursor Nightly/User/workspaceStorage",
            "Cursor - Insiders/User/workspaceStorage",
            "Code/User/workspaceStorage",
            "VSCodium/User/workspaceStorage",
        ]
        var entries: [WorkspaceEntry] = []
        var seenPath = Set<String>()

        let directCursor = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage", isDirectory: true)
        entries.append(contentsOf: loadWorkspaceEntriesFromStorageDir(base: directCursor, seenPath: &seenPath))

        for sub in storageSubpaths {
            let base = appSupport.appendingPathComponent(sub, isDirectory: true)
            entries.append(contentsOf: loadWorkspaceEntriesFromStorageDir(base: base, seenPath: &seenPath))
        }
        // Full Application Support scan + recursive + sandbox can block a long time (cloud drives, many containers).
        if includeSlowScans {
            entries.append(contentsOf: loadWorkspaceEntriesFromAllTopLevelWorkspaceStorages(appSupport: appSupport, seenPath: &seenPath))
            entries.append(contentsOf: loadWorkspaceEntriesFromRecursiveCursorTrees(appSupport: appSupport, seenPath: &seenPath))
            entries.append(contentsOf: loadWorkspaceEntriesFromSandboxContainers(seenPath: &seenPath))
        }

        return entries.sorted { $0.modified > $1.modified }
    }

    private static func loadWorkspaceEntriesFromSandboxContainers(seenPath: inout Set<String>) -> [WorkspaceEntry] {
        guard let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return [] }
        let containers = lib.appendingPathComponent("Containers", isDirectory: true)
        guard let subs = try? FileManager.default.contentsOfDirectory(
            at: containers,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [WorkspaceEntry] = []
        for dir in subs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let asRoot = dir.appendingPathComponent("Data/Library/Application Support", isDirectory: true)
            guard FileManager.default.fileExists(atPath: asRoot.path) else { continue }
            let cursorWS = asRoot.appendingPathComponent("Cursor/User/workspaceStorage", isDirectory: true)
            guard FileManager.default.fileExists(atPath: cursorWS.path) else { continue }
            entries.append(contentsOf: loadWorkspaceEntriesFromStorageDir(base: cursorWS, seenPath: &seenPath))
        }
        return entries
    }

    private static func loadWorkspaceEntriesFromAllTopLevelWorkspaceStorages(
        appSupport: URL,
        seenPath: inout Set<String>
    ) -> [WorkspaceEntry] {
        guard let subs = try? FileManager.default.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [WorkspaceEntry] = []
        for top in subs {
            guard (try? top.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = top.lastPathComponent
            let relevant =
                name.localizedCaseInsensitiveContains("cursor")
                || name == "Code"
                || name == "VSCodium"
            guard relevant else { continue }
            let ws = top.appendingPathComponent("User/workspaceStorage", isDirectory: true)
            guard FileManager.default.fileExists(atPath: ws.path) else { continue }
            entries.append(contentsOf: loadWorkspaceEntriesFromStorageDir(base: ws, seenPath: &seenPath))
        }
        return entries
    }

    private static func loadWorkspaceEntriesFromRecursiveCursorTrees(
        appSupport: URL,
        seenPath: inout Set<String>
    ) -> [WorkspaceEntry] {
        guard let subs = try? FileManager.default.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [WorkspaceEntry] = []
        for dir in subs {
            guard let isDir = try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir else { continue }
            guard dir.lastPathComponent.hasPrefix("Cursor") else { continue }
            guard let subpaths = try? FileManager.default.subpathsOfDirectory(atPath: dir.path) else { continue }
            for sp in subpaths where sp.hasSuffix("workspace.json") {
                let url = dir.appendingPathComponent(sp)
                guard let data = try? Data(contentsOf: url),
                      let path = parseWorkspaceFolderPath(from: data)
                else { continue }
                guard seenPath.insert(path).inserted else { continue }
                let leaf = (path as NSString).lastPathComponent
                let folder = url.deletingLastPathComponent()
                let modified = workspaceModified(at: folder)
                entries.append(WorkspaceEntry(
                    hash: folder.lastPathComponent,
                    folderPath: path,
                    leaf: leaf,
                    modified: modified
                ))
            }
        }
        return entries
    }

    private static func parseWorkspaceFolderPath(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let raw = json["folder"] as? String, let p = normalizeWorkspacePathString(raw) { return p }
        if let raw = json["folderUri"] as? String, let p = normalizeWorkspacePathString(raw) { return p }
        if let folders = json["folders"] as? [[String: Any]] {
            for f in folders {
                if let u = f["uri"] as? String, let p = normalizeWorkspacePathString(u) { return p }
                if let pth = f["path"] as? String, pth.hasPrefix("/"), let p = normalizeWorkspacePathString(pth) { return p }
            }
        }
        return nil
    }

    private static func normalizeWorkspacePathString(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let url = URL(string: t), url.isFileURL { return url.path }
        if t.hasPrefix("file://"), let url = URL(string: t) { return url.path }
        if t.hasPrefix("/") { return t }
        return nil
    }

    private static func loadWorkspaceEntriesFromStorageDir(
        base: URL,
        seenPath: inout Set<String>
    ) -> [WorkspaceEntry] {
        guard FileManager.default.fileExists(atPath: base.path) else { return [] }
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [WorkspaceEntry] = []
        for dir in dirs {
            let wsFile = dir.appendingPathComponent("workspace.json")
            guard FileManager.default.fileExists(atPath: wsFile.path) else { continue }
            guard let data = try? Data(contentsOf: wsFile),
                  let path = parseWorkspaceFolderPath(from: data)
            else { continue }

            guard seenPath.insert(path).inserted else { continue }

            let leaf = (path as NSString).lastPathComponent
            let modified = workspaceModified(at: dir)
            entries.append(WorkspaceEntry(
                hash: dir.lastPathComponent,
                folderPath: path,
                leaf: leaf,
                modified: modified
            ))
        }
        return entries
    }

    private static func workspaceModified(at folder: URL) -> Date {
        let candidates = [
            folder.appendingPathComponent("state.vscdb"),
            folder.appendingPathComponent("workspace.json"),
        ]
        var newest = Date.distantPast
        for c in candidates {
            if let d = try? c.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                newest = max(newest, d)
            }
        }
        return newest
    }

    /// Bases for `workspaceStorage/<hash>/…` (same discovery order as workspace enumeration).
    public static func workspaceStorageBaseDirectoryURLs() -> [URL] {
        var urls: [URL] = []
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        urls.append(home.appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage", isDirectory: true))
        let appSupport = userApplicationSupportDirectoryURL()
        for sub in [
            "Cursor/User/workspaceStorage",
            "Cursor Nightly/User/workspaceStorage",
            "Cursor - Insiders/User/workspaceStorage",
            "Code/User/workspaceStorage",
            "VSCodium/User/workspaceStorage",
        ] {
            urls.append(appSupport.appendingPathComponent(sub, isDirectory: true))
        }
        return urls
    }

    /// `state.vscdb` for a workspace storage folder hash, if present on disk.
    public static func stateVscdbURL(storageFolderHash: String) -> URL? {
        for base in workspaceStorageBaseDirectoryURLs() {
            let u = base.appendingPathComponent(storageFolderHash).appendingPathComponent("state.vscdb")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// Synthetic CPU boost from `state.vscdb` mtime (agent/UI writes) when extension-host `ps` is near zero — e.g. model work
    /// often runs outside the extension host, so this is a critical second signal.
    /// **Tiered** so a DB touched 1–5 minutes ago still nudges above the hot band; only the strongest tier wins per key.
    /// Keys: leaf name, folder basename, and `#<workspaceStorageHash>` so lookups match even when `ps` spells the path differently.
    public static func workspaceStateActivityBoost(
        entries: [WorkspaceEntry],
        /// Ignored; tiers are fixed (≤30s / ≤120s / ≤300s). Kept for API compatibility.
        recentWithin: TimeInterval = 30
    ) -> [String: Double] {
        let now = Date()
        var out: [String: Double] = [:]
        func put(_ key: String, value: Double) {
            let k = key.lowercased()
            out[k, default: 0] = max(out[k] ?? 0, value)
        }
        func boostForAge(_ age: TimeInterval) -> Double? {
            if age <= 30 { return 5.0 }
            if age <= 120 { return 3.0 }
            if age <= 300 { return 1.5 }
            return nil
        }
        for e in entries {
            guard let url = stateVscdbURL(storageFolderHash: e.hash) else { continue }
            guard let mod = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
            let age = now.timeIntervalSince(mod)
            guard let boost = boostForAge(age) else { continue }
            put(e.leaf, value: boost)
            if !e.folderPath.isEmpty {
                let base = (e.folderPath as NSString).lastPathComponent
                put(base, value: boost)
            }
            put("#\(e.hash)", value: boost)
        }
        return out
    }

    /// Narrows the full workspace list to folders that are plausibly **open now**: match extension-host `ps` keys, **recent** storage mtime, or recent `state.vscdb` writes.
    /// When `pluginCpu` is non-empty, we **do not** use loose “storage mtime” alone — that often adds an extra stale workspace (e.g. 3 tiles for 2 windows).
    /// If nothing matches (pathological), falls back to the newest workspaces by `modified` so the UI is not empty.
    public static func filterLikelyOpenWorkspaces(
        entries: [WorkspaceEntry],
        pluginCpu: [String: Double],
        modifiedWithin: TimeInterval = 20 * 60,
        stateDbWithin: TimeInterval = 25 * 60,
        /// Tighter `state.vscdb` window when we already have `ps` data (reduces spurious “third” tiles).
        stateDbWithinWhenPluginPresent: TimeInterval = 10 * 60,
        maxShown: Int = 10
    ) -> [WorkspaceEntry] {
        let now = Date()
        let pluginKeys = pluginCpu.keys.map { $0.lowercased() }
        let hasPlugin = !pluginCpu.isEmpty

        func matchesPlugin(_ e: WorkspaceEntry) -> Bool {
            let leaf = e.leaf.lowercased()
            for k in pluginKeys {
                if k == leaf { return true }
                if !e.folderPath.isEmpty {
                    let base = (e.folderPath as NSString).lastPathComponent.lowercased()
                    if k == base { return true }
                }
                // Avoid short substring matches (e.g. unrelated folders sharing a suffix).
                if leaf.count >= 5, k.count >= 5, abs(leaf.count - k.count) <= 4 {
                    if leaf.hasSuffix(k) || k.hasSuffix(leaf) { return true }
                }
            }
            return false
        }

        func recentStateDb(_ e: WorkspaceEntry, within: TimeInterval) -> Bool {
            guard let url = stateVscdbURL(storageFolderHash: e.hash) else { return false }
            guard let mod = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return false }
            return now.timeIntervalSince(mod) <= within
        }

        let filtered = entries.filter { e in
            if hasPlugin {
                return matchesPlugin(e) || recentStateDb(e, within: stateDbWithinWhenPluginPresent)
            }
            return matchesPlugin(e)
                || now.timeIntervalSince(e.modified) <= modifiedWithin
                || recentStateDb(e, within: stateDbWithin)
        }
        if filtered.isEmpty {
            return Array(entries.sorted { $0.modified > $1.modified }.prefix(min(8, maxShown)))
        }
        let sorted = filtered.sorted { a, b in
            let ap = matchesPlugin(a) ? 1 : 0
            let bp = matchesPlugin(b) ? 1 : 0
            if ap != bp { return ap > bp }
            return a.modified > b.modified
        }
        return Array(sorted.prefix(maxShown))
    }

    // MARK: - Tiles from workspaces + ps filter

    public static func buildSyntheticWindows(
        pluginCpu: [String: Double],
        workspaceEntries: [WorkspaceEntry],
        mainPid: Int32,
        activeLeavesFilter: Set<String>? = nil
    ) -> [CursorWindow] {
        guard !workspaceEntries.isEmpty else { return [] }

        let hotLeaves = Set(pluginCpu.keys.map { $0.lowercased() })

        var seenPathKeys = Set<String>()
        var rows: [WorkspaceEntry] = []
        for e in workspaceEntries.sorted(by: { $0.modified > $1.modified }) {
            let pathKey: String
            if !e.folderPath.isEmpty {
                pathKey = e.folderPath.lowercased()
            } else {
                pathKey = e.leaf.lowercased()
            }
            guard !pathKey.isEmpty else { continue }
            guard seenPathKeys.insert(pathKey).inserted else { continue }
            rows.append(e)
            if rows.count >= 32 { break }
        }

        if rows.isEmpty {
            var seenHash = Set<String>()
            for e in workspaceEntries {
                guard seenHash.insert(e.hash).inserted else { continue }
                rows.append(e)
                if rows.count >= 32 { break }
            }
        }

        guard !rows.isEmpty else { return [] }

        if let filter = activeLeavesFilter, !filter.isEmpty {
            let filtered = rows.filter { e in
                let leaf = e.leaf.lowercased()
                let base = e.folderPath.isEmpty ? leaf : (e.folderPath as NSString).lastPathComponent.lowercased()
                return filter.contains(leaf) || filter.contains(base)
            }
            if !filtered.isEmpty {
                rows = filtered
            }
        }

        rows.sort { a, b in
            let aHot = hotLeaves.contains(a.leaf.lowercased())
            let bHot = hotLeaves.contains(b.leaf.lowercased())
            if aHot != bHot { return aHot && !bHot }
            return a.modified > b.modified
        }

        return rows.map { e in
            let path = e.folderPath.isEmpty ? nil : e.folderPath
            let name: String
            if !e.leaf.isEmpty {
                name = e.leaf
            } else if let path {
                name = (path as NSString).lastPathComponent
            } else {
                name = "Workspace"
            }
            return CursorWindow(
                id: syntheticIdFromWorkspaceStorageHash(e.hash),
                pid: mainPid,
                projectName: name,
                projectPath: path,
                storageFolderHash: e.hash
            )
        }
    }

    private static func syntheticIdFromWorkspaceStorageHash(_ storageFolderHash: String) -> Int {
        var h = 5381
        for u in storageFolderHash.utf8 {
            h = ((h &<< 5) &+ h) &+ Int(u)
        }
        let m = abs(h % 2_000_000_000)
        return m == 0 ? -1 : -m
    }

    public static func cursorApplicationPIDs() -> [Int32] {
        var seen = Set<Int32>()
        var ordered: [Int32] = []
        for app in NSWorkspace.shared.runningApplications {
            let path = app.bundleURL?.path ?? ""
            let bid = app.bundleIdentifier ?? ""
            let match =
                bid == CursorProcessInfo.bundleID
                || path.contains("/Cursor.app/")
                || path.hasSuffix("/Cursor.app")
                || app.localizedName == "Cursor"
            guard match else { continue }
            let pid = app.processIdentifier
            guard seen.insert(pid).inserted else { continue }
            ordered.append(pid)
        }
        return ordered
    }

    private static func allPgrepCursorPids() -> [Int32] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "/Cursor.app/"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return [] }
        var pids: [Int32] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pid = Int32(trimmed.split(separator: " ").first ?? "") else { continue }
            pids.append(pid)
        }
        return pids
    }

    public static func cursorMainPid() -> Int32 {
        cursorApplicationPIDs().first ?? allPgrepCursorPids().first ?? 0
    }

    // MARK: - Activity (ps)

    public static func collectPluginCpu() -> [String: Double] {
        let pipe = Pipe()
        let process = Process()
        // Pipe deadlock: full `ps` output can fill the 64KB pipe buffer while we wait in `waitUntilExit`
        // before reading — `ps` then blocks on write forever. Pre-filter to Cursor plugin lines only.
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            """
            /bin/ps -axww -o pid=,pcpu=,command= 2>/dev/null | /usr/bin/grep -F 'Cursor Helper (Plugin)' | /usr/bin/grep -F extension-host || true
            """,
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var sums: [String: Double] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.contains("Cursor Helper (Plugin)"),
                  line.contains("extension-host")
            else { continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 3,
                  let cpu = Double(parts[1])
            else { continue }

            guard let workspace = extractWorkspaceLeafFromPluginCommand(String(parts[2])) else { continue }
            let key = workspace.lowercased()
            sums[key, default: 0] += cpu
        }
        return sums
    }

    private static func extractWorkspaceLeafFromPluginCommand(_ cmd: String) -> String? {
        let patterns = [
            #"extension-host\s+\([^)]+\)\s+(.+?)\s+\["#,
            #"extension-host\s+\([^)]+\)\s+(\S+)\s+\["#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: cmd, range: NSRange(cmd.startIndex..., in: cmd)),
                  match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: cmd)
            else { continue }
            let s = String(cmd[range]).trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { return s }
        }
        return nil
    }

    public static func pluginCpuValue(for window: CursorWindow, pluginCpu: [String: Double]) -> Double {
        let leaf = window.leafName.lowercased()
        if let v = pluginCpu[leaf] { return v }
        var baseKey = ""
        if let path = window.projectPath, !path.isEmpty {
            baseKey = (path as NSString).lastPathComponent.lowercased()
            if let v = pluginCpu[baseKey] { return v }
        }
        var best = 0.0
        guard leaf.count >= 3 else { return 0 }
        for (k, v) in pluginCpu where k.count >= 3 {
            if k == leaf || (!baseKey.isEmpty && k == baseKey) { continue }
            if leaf.hasSuffix(k) || k.hasSuffix(leaf) {
                best = max(best, v)
            }
        }
        if best == 0, leaf.count >= 4 {
            for (k, v) in pluginCpu where k.count >= 4 {
                if leaf.contains(k) || k.contains(leaf) {
                    best = max(best, v)
                }
            }
        }
        return best
    }

    /// When `ps` workspace tokens don’t match disk names, attribution is ambiguous. This picks a **deterministic** % per tile:
    /// 1) normal [`pluginCpuValue`], 2) single-tile pool = max bucket, 3) if **all** tiles score 0, assign buckets by **UI order** (sorted CPU, highest to first tile).
    public static func attributedPluginCpu(
        windows: [CursorWindow],
        pluginCpu: [String: Double]
    ) -> (byId: [Int: Double], mode: String) {
        guard !windows.isEmpty else { return ([:], "empty") }
        var result: [Int: Double] = [:]
        for w in windows {
            result[w.id] = pluginCpuValue(for: w, pluginCpu: pluginCpu)
        }
        if pluginCpu.isEmpty {
            return (result, "no ps buckets")
        }

        if windows.count == 1, let w = windows.first {
            let direct = pluginCpuValue(for: w, pluginCpu: pluginCpu)
            if direct > 0 {
                result[w.id] = direct
                return (result, "1×name")
            }
            if let mx = pluginCpu.values.max() {
                result[w.id] = mx
                return (result, "1×pool")
            }
            return (result, "1×zero")
        }

        let allZero = windows.allSatisfy { (result[$0.id] ?? 0) == 0 }
        if allZero {
            let vals = pluginCpu.values.sorted(by: >)
            for (i, w) in windows.enumerated() {
                if i < vals.count {
                    result[w.id] = vals[i]
                }
            }
            return (result, "rank \(windows.count)×\(pluginCpu.count)")
        }
        return (result, "name")
    }

    /// Combined signal for agent inference: extension-host `%cpu` + optional `state.vscdb` recency boost.
    /// When `suppressStateActivityBoost` is true (e.g. right after the agent finished), boost is ignored so typing/UI doesn’t flip the tile back to “thinking”.
    public static func effectiveCpuPercent(
        for window: CursorWindow,
        pluginCpu: [String: Double],
        stateActivityBoost: [String: Double],
        suppressStateActivityBoost: Bool = false,
        pluginPercentOverride: Double? = nil
    ) -> Double {
        let p = pluginPercentOverride ?? pluginCpuValue(for: window, pluginCpu: pluginCpu)
        if suppressStateActivityBoost {
            return min(100, p)
        }
        let leaf = window.leafName.lowercased()
        var b = stateActivityBoost[leaf] ?? 0
        if b == 0, let path = window.projectPath, !path.isEmpty {
            let base = (path as NSString).lastPathComponent.lowercased()
            b = stateActivityBoost[base] ?? 0
        }
        if b == 0, let h = window.storageFolderHash, !h.isEmpty {
            b = stateActivityBoost["#\(h)".lowercased()] ?? 0
        }
        return min(100, p + b)
    }
}
