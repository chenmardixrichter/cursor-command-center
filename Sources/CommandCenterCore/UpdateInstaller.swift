import Foundation

/// Runs after the app quits: unzip, replace `/Applications/Command Center.app`, relaunch.
public enum UpdateInstaller {
    public static let bundleDisplayName = "Command Center"

    /// Spawns a detached install script and returns immediately. Call `NSApp.terminate` right after.
    public static func spawnInstallAfterQuit(zipPath: URL) throws {
        let script = """
#!/bin/bash
set -e
ZIP="${CC_UPDATE_ZIP:?missing CC_UPDATE_ZIP}"
sleep 0.5
killall "\(bundleDisplayName)" 2>/dev/null || true
sleep 2
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
/usr/bin/unzip -qo "$ZIP" -d "$TMP"
DEST="/Applications/\(bundleDisplayName).app"
if [[ -d "$DEST" ]]; then
  rm -rf "$DEST" 2>/dev/null || sudo rm -rf "$DEST"
fi
cp -R "$TMP/\(bundleDisplayName).app" "/Applications/" 2>/dev/null || sudo cp -R "$TMP/\(bundleDisplayName).app" "/Applications/"
xattr -rd com.apple.quarantine "$DEST" 2>/dev/null || true
open "$DEST"
"""
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("command-center-install-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        var env = ProcessInfo.processInfo.environment
        env["CC_UPDATE_ZIP"] = zipPath.path
        proc.environment = env
        proc.arguments = ["/bin/bash", url.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
    }
}
