import CoreGraphics
import Foundation

/// Window titles from **Window Server** (`CGWindowListCopyWindowInfo`) for Cursor’s main process.
/// Supplements Apple Script when Automation permission is missing or `osascript` is slow — same strings feed [`AggregatedSignalPipeline.scriptThinkingHint`].
public enum CursorWindowServerTitles {
    /// Titles of on-screen windows owned by `pid` (deduplicated, stable order).
    public static func windowTitles(forPid pid: pid_t) -> [String] {
        titlesForPid(pid, onScreenOnly: true)
    }

    /// Titles of **all** windows (including minimized/off-screen) owned by `pid`.
    public static func allWindowTitles(forPid pid: pid_t) -> [String] {
        titlesForPid(pid, onScreenOnly: false)
    }

    private static func titlesForPid(_ pid: pid_t, onScreenOnly: Bool) -> [String] {
        guard pid > 0 else { return [] }
        let opts: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly] : [.optionAll]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var seen = Set<String>()
        var out: [String] = []
        for row in raw {
            let ownerNum = row[kCGWindowOwnerPID as String] as? NSNumber
            guard let owner = ownerNum?.int32Value, owner == pid else { continue }
            if let layer = row[kCGWindowLayer as String] as? Int, layer != 0 { continue }
            let name = (row[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            out.append(name)
        }
        out.sort()
        return out
    }
}
