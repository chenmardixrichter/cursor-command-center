import Foundation

/// Rolling diagnostic log at `/tmp/command-center-diagnostics.log`. Caps at ~500 KB — older content is trimmed.
public enum DiagnosticLog {
    public static let path = "/tmp/command-center-diagnostics.log"
    private static let maxBytes = 500_000
    private static let lock = NSLock()

    public static func log(_ message: String) {
        let ts = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        let line = "[\(ts)] \(message)\n"
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        guard let fh = FileHandle(forWritingAtPath: path) else { return }
        defer { try? fh.close() }
        fh.seekToEndOfFile()
        if let data = line.data(using: .utf8) {
            fh.write(data)
        }
        trimIfNeeded()
    }

    public static func section(_ title: String, _ lines: [String]) {
        var buf = "── \(title) ──"
        for l in lines { buf += "\n  \(l)" }
        log(buf)
    }

    private static func trimIfNeeded() {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attr[.size] as? Int, size > maxBytes else { return }
        guard let data = FileManager.default.contents(atPath: path) else { return }
        let keep = data.suffix(maxBytes / 2)
        if let trimIdx = keep.firstIndex(of: UInt8(ascii: "\n")) {
            let trimmed = keep.suffix(from: keep.index(after: trimIdx))
            try? trimmed.write(to: URL(fileURLWithPath: path))
        }
    }
}
