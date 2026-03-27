import Foundation

public enum Telemetry {
    private static let webhookURL = "https://script.google.com/macros/s/AKfycbzeo54WT_Xn8KPKqiOSr8ARAkG-6ACCyhaz535yb4vNsPFix6XMn0mgSFApamFQKUQ/exec"
    private static let debounceInterval: TimeInterval = 86400 // 24 hours

    private static var userIdKey = "cc_telemetry_user_id"
    private static var lastPingKey = "cc_telemetry_last_ping"

    public static var isConfigured: Bool {
        webhookURL != "WEBHOOK_URL_PLACEHOLDER" && !webhookURL.isEmpty
    }

    public static var anonymousUserId: String {
        if let existing = UserDefaults.standard.string(forKey: userIdKey) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: userIdKey)
        return newId
    }

    public static func sendInstallPing(version: String) {
        guard isConfigured else { return }
        let payload: [String: Any] = [
            "event": "install",
            "user": NSUserName(),
            "host": Host.current().localizedName ?? "unknown",
            "version": version,
            "userId": anonymousUserId,
            "ts": ISO8601DateFormatter().string(from: Date())
        ]
        post(payload)
    }

    public static func sendUninstallPing(version: String) {
        guard isConfigured else { return }
        let payload: [String: Any] = [
            "event": "uninstall",
            "user": NSUserName(),
            "host": Host.current().localizedName ?? "unknown",
            "version": version,
            "userId": anonymousUserId,
            "ts": ISO8601DateFormatter().string(from: Date())
        ]
        post(payload)
    }

    public static func sendDailyPingIfNeeded(version: String, activeTiles: Int, agentTurnsToday: Int) {
        guard isConfigured else { return }

        let lastPing = UserDefaults.standard.double(forKey: lastPingKey)
        let now = Date().timeIntervalSince1970
        guard now - lastPing > debounceInterval else { return }

        UserDefaults.standard.set(now, forKey: lastPingKey)

        let payload: [String: Any] = [
            "event": "daily_ping",
            "macUser": NSUserName(),
            "userId": anonymousUserId,
            "version": version,
            "activeTiles": activeTiles,
            "agentTurnsToday": agentTurnsToday,
            "sessionStart": ISO8601DateFormatter().string(from: Date())
        ]
        post(payload)
    }

    // MARK: - Private

    private static func post(_ payload: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8),
              let encoded = jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(webhookURL)?d=\(encoded)")
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }
}
