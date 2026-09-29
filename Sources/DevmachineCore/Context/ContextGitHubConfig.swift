import Foundation

/// A GitHub Enterprise host a PR reference may name, beyond `github.com`.
public struct GitHubHost: Decodable, Equatable, Sendable {
    public let host: String
    public let proxy: String?
}

/// Reads `~/.config/devmachine-app/config.json`'s `github_hosts`, the same
/// file and key `devmachine-infer` reads. Missing or malformed config means
/// `github.com` is the only host anyone resolves.
public enum ContextGitHubConfig {
    public static func configPath() -> URL {
        if let override = ProcessInfo.processInfo.environment["DEVMACHINE_APP_CONFIG"] {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/devmachine-app/config.json")
    }

    public static func githubHosts(path: URL = configPath()) -> [GitHubHost] {
        guard let data = try? Data(contentsOf: path) else { return [] }
        struct Root: Decodable { let github_hosts: [GitHubHost]? }
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { return [] }
        return root.github_hosts ?? []
    }

    /// `github.com` first, then the configured enterprise hosts.
    public static func allHosts(path: URL = configPath()) -> [String] {
        ["github.com"] + githubHosts(path: path).map(\.host)
    }
}
