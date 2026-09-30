import Foundation

public struct HTTPResponse: Sendable, Equatable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public protocol HTTPFetching: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
}

/// The last answer and its `ETag`. GitHub does not count a `304` against
/// the 60 unauthenticated requests an hour, so a check that finds nothing new
/// costs nothing.
public struct CachedRelease: Codable, Equatable, Sendable {
    public let etag: String
    public let body: Data

    public init(etag: String, body: Data) {
        self.etag = etag
        self.body = body
    }
}

public enum ReleaseFeedError: LocalizedError, Equatable {
    case rateLimited
    case noRelease
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .rateLimited: return "GitHub is limiting requests from this network for now (HTTP 403/429)."
        case .noRelease: return "The releases repository has no published release yet (HTTP 404)."
        case .httpStatus(let status): return "GitHub answered HTTP \(status)."
        }
    }
}

public struct ReleaseFeed: Sendable {
    public static let appReleases = URL(
        string: "https://api.github.com/repos/mydevmachine/app-releases/releases/latest")!
    public static let cliReleases = URL(
        string: "https://api.github.com/repos/mydevmachine/devmachine/releases/latest")!

    public let url: URL
    public let fetcher: any HTTPFetching
    public let userAgent: String

    public init(url: URL, fetcher: any HTTPFetching, userAgent: String) {
        self.url = url
        self.fetcher = fetcher
        self.userAgent = userAgent
    }

    public func latest(cached: CachedRelease?) async throws -> (release: GitHubRelease, cache: CachedRelease?) {
        var headers = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": userAgent,
        ]
        if let cached { headers["If-None-Match"] = cached.etag }
        let response = try await fetcher.get(url, headers: headers)
        switch response.status {
        case 200:
            let release = try GitHubRelease.decode(response.body)
            let cache = response.header("ETag").map { CachedRelease(etag: $0, body: response.body) }
            return (release, cache)
        case 304:
            guard let cached else { throw ReleaseFeedError.httpStatus(304) }
            return (try GitHubRelease.decode(cached.body), cached)
        case 403, 429:
            throw ReleaseFeedError.rateLimited
        case 404:
            throw ReleaseFeedError.noRelease
        default:
            throw ReleaseFeedError.httpStatus(response.status)
        }
    }
}
