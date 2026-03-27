import ApplicationServices
import AppKit
import CoreFoundation
import Foundation

/// Accessibility scan for the **Composer interrupt control** (dark circle, **Stop** / square icon next to the prompt).
/// **Thinking** = this button is present in the AX tree; **done** (elsewhere) = it disappeared — not generic Cancel buttons elsewhere in the window.
public enum CursorAXSignals {
    public struct PerTile: Equatable, Sendable {
        /// `true` when the **Composer Stop / interrupt** button is visible (square icon — exposed as a Stop-style control in AX).
        public var composerStopButtonVisible: Bool
        public var minimized: Bool
    }

    /// Returns per-tile AX info keyed by [`CursorWindow.id`]. Empty if Cursor isn’t running, AX fails, or accessibility isn’t trusted.
    public static func scan(cursorPID: pid_t, tiles: [CursorWindow]) -> [Int: PerTile] {
        guard cursorPID > 0, !tiles.isEmpty else { return [:] }
        guard AXIsProcessTrusted() else { return [:] }

        let app = AXUIElementCreateApplication(cursorPID)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == AXError.success, let windows = windowsRef as? [AXUIElement] else { return [:] }

        /// Balance: too low → wrong window; too high → no AX row for a tile (stuck idle).
        let minimumWindowMatchScore = 6

        struct Candidate {
            let tileId: Int
            let windowIndex: Int
            let score: Int
        }

        var candidates: [Candidate] = []
        for tile in tiles {
            for (i, w) in windows.enumerated() {
                let title = axTitle(w) ?? ""
                let s = matchScore(windowTitle: title, tile: tile)
                if s >= minimumWindowMatchScore {
                    candidates.append(Candidate(tileId: tile.id, windowIndex: i, score: s))
                }
            }
        }
        candidates.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.tileId < b.tileId
        }

        var usedWin = Set<Int>()
        var usedTile = Set<Int>()
        var tileToWindowIndex: [Int: Int] = [:]
        for c in candidates {
            if usedWin.contains(c.windowIndex) || usedTile.contains(c.tileId) { continue }
            usedWin.insert(c.windowIndex)
            usedTile.insert(c.tileId)
            tileToWindowIndex[c.tileId] = c.windowIndex
        }

        var result: [Int: PerTile] = [:]
        for tile in tiles {
            guard let winIdx = tileToWindowIndex[tile.id] else { continue }
            let winEl = windows[winIdx]
            let minimized = axBool(winEl, attribute: kAXMinimizedAttribute as CFString)
            let stopVisible = !minimized && findComposerInterruptStopButton(in: winEl)
            result[tile.id] = PerTile(composerStopButtonVisible: stopVisible, minimized: minimized)
        }

        return result
    }

    public static func accessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Opens **System Settings → Privacy & Security → Accessibility** (or the legacy System Preferences pane) so the user can enable Command Center.
    public static func openAccessibilityPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func matchScore(windowTitle: String, tile: CursorWindow) -> Int {
        let t = windowTitle
        let leaf = tile.leafName
        if leaf.count >= 2, t.localizedCaseInsensitiveContains(leaf) { return min(100, leaf.count + 10) }
        if let path = tile.projectPath, !path.isEmpty {
            let base = (path as NSString).lastPathComponent
            if base.count >= 2, t.localizedCaseInsensitiveContains(base) { return min(100, base.count + 8) }
        }
        if t.localizedCaseInsensitiveContains(tile.projectName), tile.projectName.count >= 2 {
            return tile.projectName.count
        }
        return 0
    }

    private static func axTitle(_ el: AXUIElement) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &v) == AXError.success else { return nil }
        return v as? String
    }

    private static func axBool(_ el: AXUIElement, attribute: CFString) -> Bool {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute, &v) == AXError.success else { return false }
        if let n = v as? NSNumber { return n.boolValue }
        return false
    }

    private static func axParent(_ el: AXUIElement) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &v) == AXError.success else { return nil }
        return (v as! AXUIElement)
    }

    private static func axPlaceholder(_ el: AXUIElement) -> String? {
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXPlaceholderValueAttribute as CFString, &v) == AXError.success,
           let s = v as? String, !s.isEmpty { return s }
        return nil
    }

    private static func axRole(_ el: AXUIElement) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &v) == AXError.success else { return nil }
        return v as? String
    }

    /// Finds the Composer prompt field (e.g. “Add a follow-up”, “Plan, @ for context”) to scope search near the Stop control.
    private static func findComposerInputAnchor(in root: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > 22 { return nil }

        if let role = axRole(root), role == "AXTextArea" || role == "AXTextField" || role == "AXComboBox" {
            let ph = axPlaceholder(root) ?? ""
            let desc = axString(root, kAXDescriptionAttribute as CFString) ?? ""
            if placeholderLooksLikeComposerInput(ph) || placeholderLooksLikeComposerInput(desc) {
                return root
            }
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &children) == AXError.success,
              let ch = children as? [AXUIElement]
        else { return nil }

        for c in ch {
            if let a = findComposerInputAnchor(in: c, depth: depth + 1) { return a }
        }
        return nil
    }

    private static func axString(_ el: AXUIElement, _ attr: CFString) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &v) == AXError.success else { return nil }
        return v as? String
    }

    private static func placeholderLooksLikeComposerInput(_ s: String) -> Bool {
        let u = s.lowercased()
        if u.contains("follow-up") || u.contains("follow up") || u.contains("add a follow") { return true }
        if u.contains("plan,") || u.contains("plan, @") || u.contains("@ for context") || u.contains("/ for commands") {
            return true
        }
        // Newer Cursor / locale variants — keep loose so we still anchor Stop search near the prompt.
        if u.contains("ask cursor") || u.contains("ask anything") || u.contains("type a message") { return true }
        if u.contains("composer") && (u.contains("message") || u.contains("prompt") || u.contains("chat")) { return true }
        return false
    }

    /// Dumps all AX buttons found in a window for diagnostics. Writes to `/tmp/command-center-ax-dump.txt`.
    public static func dumpButtons(cursorPID: pid_t, tiles: [CursorWindow]) {
        guard cursorPID > 0, AXIsProcessTrusted() else { return }
        let app = AXUIElementCreateApplication(cursorPID)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == AXError.success,
              let windows = windowsRef as? [AXUIElement] else { return }

        var lines: [String] = ["AX Button Dump @ \(Date())"]
        for (i, w) in windows.enumerated() {
            let title = axTitle(w) ?? "(no title)"
            lines.append("--- Window [\(i)] \(title) ---")
            collectButtons(in: w, depth: 0, maxDepth: 22, lines: &lines, indent: "  ")
        }
        try? lines.joined(separator: "\n").write(toFile: "/tmp/command-center-ax-dump.txt", atomically: true, encoding: .utf8)
    }

    private static func collectButtons(in el: AXUIElement, depth: Int, maxDepth: Int, lines: inout [String], indent: String) {
        if depth > maxDepth { return }
        let role = axRole(el) ?? ""
        let title = axTitle(el) ?? ""
        let desc = axString(el, kAXDescriptionAttribute as CFString) ?? ""
        if role == "AXButton" && (!title.isEmpty || !desc.isEmpty) {
            lines.append("\(indent)[\(depth)] AXButton title=\"\(title)\" desc=\"\(desc)\"")
        }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == AXError.success,
              let ch = children as? [AXUIElement] else { return }
        for c in ch {
            collectButtons(in: c, depth: depth + 1, maxDepth: maxDepth, lines: &lines, indent: indent)
        }
    }

    /// Prefer Stop **near** the Composer input; fall back to a **strict** Stop-only match in the window (Electron may omit placeholders).
    private static func findComposerInterruptStopButton(in window: AXUIElement) -> Bool {
        if let anchor = findComposerInputAnchor(in: window, depth: 0) {
            var cur: AXUIElement? = anchor
            for _ in 0 ..< 8 {
                guard let node = cur else { break }
                if findStrictInterruptStopButton(in: node, depth: 0, maxDepth: 14) { return true }
                cur = axParent(node)
            }
        }
        return findStrictInterruptStopButton(in: window, depth: 0, maxDepth: 22)
    }

    /// **Interrupt** Stop only (the square “stop generation” control). Excludes unrelated “Stop” strings and **does not** use Cancel as a substitute.
    private static func findStrictInterruptStopButton(in root: AXUIElement, depth: Int, maxDepth: Int) -> Bool {
        if depth > maxDepth { return false }

        var role: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(root, kAXRoleAttribute as CFString, &role)
        let roleStr = role as? String ?? ""

        var title: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(root, kAXTitleAttribute as CFString, &title)
        let titleStr = (title as? String) ?? ""

        var desc: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(root, kAXDescriptionAttribute as CFString, &desc)
        let descStr = (desc as? String) ?? ""

        if roleStr == "AXButton", composerInterruptStopMatches(title: titleStr, description: descStr) {
            return true
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &children) == AXError.success,
              let ch = children as? [AXUIElement]
        else { return false }

        for c in ch {
            if findStrictInterruptStopButton(in: c, depth: depth + 1, maxDepth: maxDepth) { return true }
        }
        return false
    }

    /// The **square** control is the Stop **interrupt** in Composer; AX usually exposes “Stop” and/or a shortcut hint like `^c`.
    private static func composerInterruptStopMatches(title: String, description: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if t.contains("undo") || t.contains("review") || t.contains("keep all") { return false }
        if t.contains("stop all") || t.contains("non-stop") { return false }

        func isInterruptStop(_ s: String) -> Bool {
            guard !s.isEmpty, s.count < 56 else { return false }
            if s.contains("stop all") { return false }
            if s == "stop" { return true }
            if s.hasPrefix("stop ") && (s.contains("^") || s.contains("⌘") || s.contains("⌃") || s.count <= 14) {
                return true
            }
            if s.contains("stop") && !s.contains("cancel") && s.count <= 24 {
                return true
            }
            return false
        }

        return isInterruptStop(t) || isInterruptStop(d)
    }
}
