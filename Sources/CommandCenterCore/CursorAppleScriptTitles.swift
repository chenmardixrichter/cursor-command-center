import Foundation

/// **Stealth** window titles from Cursor without focusing windows — complements AX/FSEvents when the window is dock-minimized.
public enum CursorAppleScriptTitles {
    /// Returns one string per window (line-separated), or empty if Cursor isn’t running / script fails.
    public static func fetchWindowTitles() -> [String] {
        let script = """
        tell application "Cursor"
            set out to ""
            repeat with i from 1 to (count of windows)
                set out to out & name of window i & linefeed
            end repeat
            return out
        end tell
        """
        guard let out = runAppleScriptReturningString(script) else { return [] }
        return out.split(separator: "\n").map(String.init).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func runAppleScriptReturningString(_ source: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
