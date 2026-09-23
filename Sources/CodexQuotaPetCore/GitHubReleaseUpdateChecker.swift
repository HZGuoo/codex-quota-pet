import Foundation

public struct GitHubReleaseUpdate: Equatable, Sendable {
    public let currentVersion: String
    public let latestVersion: String
    public let releaseURL: URL

    public init(currentVersion: String, latestVersion: String, releaseURL: URL) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.releaseURL = releaseURL
    }
}

public enum GitHubReleaseUpdateError: LocalizedError, Equatable {
    case invalidRepository
    case invalidResponse
    case requestFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidRepository:
            "GitHub 仓库名称无效。"
        case .invalidResponse:
            "GitHub 返回了无法识别的版本信息。"
        case let .requestFailed(status):
            "GitHub 版本检查失败（HTTP \(status)）。"
        }
    }
}

public enum GitHubReleaseUpdateChecker {
    /// Returns a newer stable GitHub release, or `nil` when the current version
    /// is up to date. This method sends only a normal HTTPS request to GitHub.
    public static func check(
        currentVersion: String,
        repository: String = "HZGuoo/codex-quota-pet",
        session: URLSession = .shared
    ) async throws -> GitHubReleaseUpdate? {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2,
              let url = URL(string: "https://api.github.com/repos/\(parts[0])/\(parts[1])/releases/latest")
        else {
            throw GitHubReleaseUpdateError.invalidRepository
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("CodexQuotaPet/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubReleaseUpdateError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubReleaseUpdateError.requestFailed(http.statusCode)
        }

        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let releaseURL = URL(string: release.htmlURL) else {
            throw GitHubReleaseUpdateError.invalidResponse
        }
        let latestVersion = normalized(release.tagName)
        let installedVersion = normalized(currentVersion)
        guard isNewer(latestVersion, than: installedVersion) else { return nil }
        return GitHubReleaseUpdate(
            currentVersion: installedVersion,
            latestVersion: latestVersion,
            releaseURL: releaseURL
        )
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = components(normalized(candidate))
        let rhs = components(normalized(current))
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func normalized(_ version: String) -> String {
        var result = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.lowercased().hasPrefix("v") { result.removeFirst() }
        return result.split(separator: "-", maxSplits: 1).first.map(String.init) ?? result
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
