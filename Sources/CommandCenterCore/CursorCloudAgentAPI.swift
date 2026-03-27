import Foundation

/// [Cloud Agents API](https://cursor.com/docs/background-agent/api/endpoints): `GET https://api.cursor.com/v0/agents/{id}` with Basic auth (API key as username, empty password).
public enum CursorCloudAgentConfig {
    public static var apiKey: String? {
        if let e = ProcessInfo.processInfo.environment["CURSOR_API_KEY"], !e.isEmpty { return e }
        let v = UserDefaults.standard.string(forKey: "CommandCenter.cursorApiKey") ?? ""
        return v.isEmpty ? nil : v
    }

    public static var agentId: String? {
        if let e = ProcessInfo.processInfo.environment["CURSOR_CLOUD_AGENT_ID"], !e.isEmpty { return e }
        let v = UserDefaults.standard.string(forKey: "CommandCenter.cursorCloudAgentId") ?? ""
        return v.isEmpty ? nil : v
    }
}

public struct AgentStatusPayload: Codable, Sendable {
    public let id: String
    public let status: String
    public let name: String?
    public let source: Source?
    public struct Source: Codable, Sendable {
        public let repository: String?
        public let ref: String?
    }
}

public enum CursorCloudAgentFetchResult: Sendable {
    case notConfigured
    /// API key works but `GET /v0/agents` returned an empty list — user has not started a cloud agent yet.
    case noAgentsInAccount
    case success(AgentStatusPayload)
    case failure(String)
}

private struct AgentsListResponse: Codable, Sendable {
    let agents: [AgentStatusPayload]
}

public enum CursorCloudAgentAPI {

    /// Terminal-ish statuses from Cursor docs / OpenAPI (extend if new values appear).
    public static func isWorkingStatus(_ status: String) -> Bool {
        let u = status.uppercased()
        let terminal: Set<String> = [
            "FINISHED", "FAILED", "STOPPED", "CANCELLED", "DELETED", "ERROR",
        ]
        return !terminal.contains(u)
    }

    /// Prefer a tile whose folder name matches the GitHub `owner/repo` tail; else first tile.
    public static func targetTileIndex(tiles: [AgentTile], payload: AgentStatusPayload) -> Int? {
        guard !tiles.isEmpty else { return nil }
        guard let repo = payload.source?.repository, !repo.isEmpty else {
            return tiles.indices.first
        }
        let r = repo.lowercased()
        if let idx = tiles.indices.first(where: { i in
            let p = tiles[i].workspacePath
            guard !p.isEmpty else { return false }
            let leaf = (p as NSString).lastPathComponent.lowercased()
            return r.contains(leaf) || r.hasSuffix("/\(leaf)") || r.hasSuffix(leaf)
        }) {
            return idx
        }
        return tiles.indices.first
    }

    /// With API key only: `GET /v0/agents`, prefer a **working** agent, else newest in list. With agent id set: `GET /v0/agents/{id}` only.
    public static func pollIfConfigured() async -> CursorCloudAgentFetchResult {
        guard let key = CursorCloudAgentConfig.apiKey, !key.isEmpty else {
            return .notConfigured
        }
        let explicitId = CursorCloudAgentConfig.agentId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitId.isEmpty {
            do {
                let p = try await fetchAgent(apiKey: key, agentId: explicitId)
                return .success(p)
            } catch {
                return .failure(error.localizedDescription)
            }
        }
        do {
            let agents = try await listAgents(apiKey: key, limit: 25)
            let pick = agents.first(where: { isWorkingStatus($0.status) }) ?? agents.first
            guard let agent = pick else {
                return .noAgentsInAccount
            }
            return .success(agent)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    public static func listAgents(apiKey: String, limit: Int = 25) async throws -> [AgentStatusPayload] {
        let lim = min(max(limit, 1), 100)
        guard let url = URL(string: "https://api.cursor.com/v0/agents?limit=\(lim)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let auth = "\(apiKey):"
        let b64 = Data(auth.utf8).base64EncodedString()
        request.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard 200 ..< 300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "CommandCenter",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body.prefix(200))"]
            )
        }
        return try JSONDecoder().decode(AgentsListResponse.self, from: data).agents
    }

    public static func fetchAgent(apiKey: String, agentId: String) async throws -> AgentStatusPayload {
        let trimmed = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "CommandCenter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty agent id"])
        }
        guard let url = URL(string: "https://api.cursor.com/v0/agents/\(trimmed)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let auth = "\(apiKey):"
        let b64 = Data(auth.utf8).base64EncodedString()
        request.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard 200 ..< 300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "CommandCenter",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body.prefix(200))"]
            )
        }
        return try JSONDecoder().decode(AgentStatusPayload.self, from: data)
    }
}
