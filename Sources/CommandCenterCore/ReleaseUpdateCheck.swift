import Foundation

/// Compares GitHub's latest **published release** to the running app version.
/// Pushing to `main` does nothing until you publish a new release with a `.zip` asset.
public struct ReleaseUpdateOffer: Sendable, Equatable {
    public let version: String
    public let tagName: String
    public let downloadURL: URL
    public let releasePageURL: URL

    public init(version: String, tagName: String, downloadURL: URL, releasePageURL: URL) {
        self.version = version
        self.tagName = tagName
        self.downloadURL = downloadURL
        self.releasePageURL = releasePageURL
    }
}

public enum ReleaseUpdateCheck {
    public static let repoOwner = "chenmardixrichter"
    public static let repoName = "cursor-command-center"

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    /// Returns an update only if the latest GitHub release is newer than `currentVersion`.
    public static func fetchUpdateIfNewer(currentVersion: String) async -> ReleaseUpdateOffer? {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("Command-Center-UpdateCheck/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remoteVersion = normalizeVersion(decoded.tag_name)
            guard isSemver(remoteVersion, greaterThan: normalizeVersion(currentVersion)) else {
                return nil
            }
            guard let zipAsset = decoded.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }),
                  let downloadURL = URL(string: zipAsset.browser_download_url),
                  let pageURL = URL(string: decoded.html_url)
            else {
                return nil
            }
            return ReleaseUpdateOffer(
                version: remoteVersion,
                tagName: decoded.tag_name,
                downloadURL: downloadURL,
                releasePageURL: pageURL
            )
        } catch {
            return nil
        }
    }

    public static func normalizeVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    public static func isSemver(_ a: String, greaterThan b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int(String($0).filter(\.isNumber)) }
        let pb = b.split(separator: ".").compactMap { Int(String($0).filter(\.isNumber)) }
        let n = max(pa.count, pb.count, 1)
        for i in 0 ..< n {
            let ai = i < pa.count ? pa[i] : 0
            let bi = i < pb.count ? pb[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }

    public static func downloadZip(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("Command-Center-UpdateCheck/1.0", forHTTPHeaderField: "User-Agent")
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("Command Center", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("Command-Center-update.zip")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }
}
