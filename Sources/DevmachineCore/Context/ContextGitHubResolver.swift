import Foundation

/// A GitHub reference (from `ContextGitHubRef`) enriched with `gh`'s live
/// state, or left `"unknown"` when `gh` never answered for it.
public struct ContextGitHubPR: Equatable, Sendable {
    public var host: String
    public var repo: String
    public var num: Int
    public var url: String
    public var lastTimestamp: String
    public var title: String
    public var isDraft: Bool
    public var state: String
    public var review: String?
    public var ci: String
    public var threads: Int?
}

/// Resolves GitHub references to live state via `gh api graphql`, caching
/// the answer on disk so a frequent poll (the panel refreshes every few
/// seconds) does not spend the account's rate limit. Mirrors
/// `devmachine-infer`'s cache file semantics
/// (`~/.cache/devmachine-infer/prs.json`) so both engines share one budget.
public struct ContextGitHubResolver: Sendable {
    public static let freshOpenSeconds: TimeInterval = 90
    public static let freshTerminalSeconds: TimeInterval = 24 * 3600
    public static let freshUnknownSeconds: TimeInterval = 600
    public static let rateLimitPauseSeconds: TimeInterval = 300
    public static let cacheKeepSeconds: TimeInterval = 7 * 24 * 3600
    private static let terminalStates: Set<String> = ["merged", "closed"]

    private let runner: any CommandRunner
    private let cachePath: URL
    private let hosts: [GitHubHost]

    public init(
        runner: any CommandRunner = ProcessRunner(),
        cachePath: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cache/devmachine-infer/prs.json"),
        hosts: [GitHubHost] = ContextGitHubConfig.githubHosts()
    ) {
        self.runner = runner
        self.cachePath = cachePath
        self.hosts = hosts
    }

    private struct CacheRow: Codable {
        var at: TimeInterval
        var pr: [String: ContextJSONValue]
    }
    private struct Cache: Codable {
        var prs: [String: CacheRow] = [:]
        var pausedUntil: TimeInterval = 0
    }

    private static func cacheKey(host: String, repo: String, num: Int) -> String {
        "\(host)|\(repo)#\(num)"
    }

    public func resolve(_ refs: [ContextGitHubRef], now: Date = Date()) -> [ContextGitHubPR] {
        let wanted = refs
        guard !wanted.isEmpty else { return [] }
        let nowInterval = now.timeIntervalSince1970
        var cache = loadCache()
        var rows = cache.prs

        let stale = wanted.filter { !isFresh(rows[Self.cacheKey(host: $0.host, repo: $0.repo, num: $0.num)], now: nowInterval) }

        if !stale.isEmpty && nowInterval >= cache.pausedUntil {
            var limitedOverall = false
            for (host, group) in groupByHost(stale) {
                let (resolved, limited, answered) = queryHost(host, entries: group)
                limitedOverall = limitedOverall || limited
                for (key, pr) in resolved {
                    rows[key] = CacheRow(at: nowInterval, pr: pr)
                }
                if answered {
                    for entry in group {
                        let key = Self.cacheKey(host: entry.host, repo: entry.repo, num: entry.num)
                        if resolved[key] == nil {
                            rows[key] = CacheRow(at: nowInterval, pr: encodeUnresolved(entry, bare: true))
                        }
                    }
                }
            }
            cache.pausedUntil = limitedOverall ? nowInterval + Self.rateLimitPauseSeconds : 0
            let keys = Set(wanted.map { Self.cacheKey(host: $0.host, repo: $0.repo, num: $0.num) })
            rows = rows.filter { keys.contains($0.key) || nowInterval - $0.value.at < Self.cacheKeepSeconds }
            cache.prs = rows
            saveCache(cache)
        }

        return wanted.map { entry in
            let key = Self.cacheKey(host: entry.host, repo: entry.repo, num: entry.num)
            guard let row = rows[key] else { return unresolvedPR(entry) }
            return decodePR(entry, row.pr) ?? unresolvedPR(entry)
        }
    }

    private func isFresh(_ row: CacheRow?, now: TimeInterval) -> Bool {
        guard let row else { return false }
        let state = row.pr["state"]?.stringValue ?? ""
        let ttl: TimeInterval = Self.terminalStates.contains(state)
            ? Self.freshTerminalSeconds
            : (state == "unknown" ? Self.freshUnknownSeconds : Self.freshOpenSeconds)
        return now - row.at < ttl
    }

    private func groupByHost(_ entries: [ContextGitHubRef]) -> [(String, [ContextGitHubRef])] {
        var byHost: [String: [ContextGitHubRef]] = [:]
        for e in entries { byHost[e.host, default: []].append(e) }
        return byHost.sorted { $0.key < $1.key }
    }

    private func env(for host: String) -> [String: String]? {
        guard host != "github.com" else { return nil }
        var env = ProcessInfo.processInfo.environment
        env["GH_HOST"] = host
        if let proxy = hosts.first(where: { $0.host == host })?.proxy, !proxy.isEmpty {
            env["HTTPS_PROXY"] = proxy
        }
        return env
    }

    private static let fields = "number state isDraft title url reviewDecision "
        + "reviewThreads(first: 100) { nodes { isResolved } } "
        + "commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }"

    private func batchQuery(_ entries: [ContextGitHubRef]) -> String {
        var parts: [String] = []
        for (i, e) in entries.enumerated() {
            let pieces = e.repo.split(separator: "/", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            let owner = jsonQuoted(pieces[0])
            let name = jsonQuoted(pieces[1])
            parts.append("a\(i): repository(owner: \(owner), name: \(name))"
                + " { pullRequest(number: \(e.num)) { \(Self.fields) } }")
        }
        return "query {" + parts.joined(separator: " ") + "}"
    }

    private func jsonQuoted(_ s: String) -> String {
        (try? String(data: JSONEncoder().encode(s), encoding: .utf8) ?? "\"\(s)\"") ?? "\"\(s)\""
    }

    private func queryHost(
        _ host: String, entries: [ContextGitHubRef]
    ) -> (resolved: [String: [String: ContextJSONValue]], limited: Bool, answered: Bool) {
        let query = batchQuery(entries)
        let output: String
        do {
            output = try runner.run(
                executable: "/usr/bin/env",
                args: ["gh", "api", "graphql", "-f", "query=\(query)"],
                environment: env(for: host)
            )
        } catch {
            return ([:], false, false)
        }
        return parseBatch(output, entries: entries)
    }

    private func parseBatch(
        _ output: String, entries: [ContextGitHubRef]
    ) -> (resolved: [String: [String: ContextJSONValue]], limited: Bool, answered: Bool) {
        guard let data = output.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ([:], output.lowercased().contains("rate limit"), false)
        }
        let errors = payload["errors"] as? [[String: Any]] ?? []
        let limited = errors.contains { ($0["type"] as? String) == "RATE_LIMIT" }
        let data2 = payload["data"] as? [String: Any] ?? [:]
        let answered = payload["data"] != nil && !limited

        var resolved: [String: [String: ContextJSONValue]] = [:]
        for (i, entry) in entries.enumerated() {
            guard let alias = data2["a\(i)"] as? [String: Any],
                  let node = alias["pullRequest"] as? [String: Any]
            else { continue }
            let isDraft = node["isDraft"] as? Bool ?? false
            let state = node["state"] as? String ?? ""
            let mappedState: String
            if state == "MERGED" { mappedState = "merged" } else if isDraft { mappedState = "draft" } else { mappedState = state.lowercased() }
            let key = Self.cacheKey(host: entry.host, repo: entry.repo, num: entry.num)
            resolved[key] = [
                "title": .string(node["title"] as? String ?? ""),
                "url": .string(node["url"] as? String ?? entry.url),
                "isDraft": .bool(isDraft),
                "state": .string(mappedState),
                "review": (node["reviewDecision"] as? String).map(ContextJSONValue.string) ?? .null,
                "ci": .string(rollupOf(node)),
                "threads": unresolvedThreads(node).map(ContextJSONValue.int) ?? .null,
            ]
        }
        return (resolved, limited, answered)
    }

    private func rollupOf(_ node: [String: Any]) -> String {
        guard let commits = (node["commits"] as? [String: Any])?["nodes"] as? [[String: Any]], !commits.isEmpty
        else { return "none" }
        guard let rollup = ((commits[0]["commit"] as? [String: Any])?["statusCheckRollup"] as? [String: Any])?["state"] as? String
        else { return "none" }
        switch rollup {
        case "SUCCESS": return "pass"
        case "FAILURE", "ERROR": return "fail"
        case "PENDING", "EXPECTED": return "pending"
        default: return "none"
        }
    }

    private func unresolvedThreads(_ node: [String: Any]) -> Int? {
        guard let nodes = (node["reviewThreads"] as? [String: Any])?["nodes"] as? [[String: Any]] else { return nil }
        return nodes.filter { !($0["isResolved"] as? Bool ?? false) }.count
    }

    private func encodeUnresolved(_ entry: ContextGitHubRef, bare: Bool) -> [String: ContextJSONValue] {
        [
            "title": .string(entry.repo), "url": .string(entry.url), "isDraft": .bool(false),
            "state": .string("unknown"), "review": .null, "ci": .string("none"), "threads": .null,
        ]
    }

    private func unresolvedPR(_ entry: ContextGitHubRef) -> ContextGitHubPR {
        ContextGitHubPR(
            host: entry.host, repo: entry.repo, num: entry.num, url: entry.url,
            lastTimestamp: entry.lastTimestamp, title: "", isDraft: false, state: "unknown",
            review: nil, ci: "none", threads: nil
        )
    }

    private func decodePR(_ entry: ContextGitHubRef, _ pr: [String: ContextJSONValue]) -> ContextGitHubPR? {
        ContextGitHubPR(
            host: entry.host, repo: entry.repo, num: entry.num,
            url: pr["url"]?.stringValue ?? entry.url, lastTimestamp: entry.lastTimestamp,
            title: pr["title"]?.stringValue ?? "", isDraft: pr["isDraft"]?.boolValue ?? false,
            state: pr["state"]?.stringValue ?? "unknown", review: pr["review"]?.stringValue,
            ci: pr["ci"]?.stringValue ?? "none", threads: pr["threads"]?.intValue
        )
    }

    private func loadCache() -> Cache {
        guard let data = try? Data(contentsOf: cachePath),
              let cache = try? JSONDecoder().decode(Cache.self, from: data)
        else { return Cache() }
        return cache
    }

    private func saveCache(_ cache: Cache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        let dir = cachePath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(ProcessInfo.processInfo.processIdentifier).tmp")
        do {
            try data.write(to: tmp)
            _ = try FileManager.default.replaceItemAt(cachePath, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}

/// A minimal JSON value, only so the cache file can round-trip an
/// arbitrary GraphQL-shaped PR row through `Codable`.
public enum ContextJSONValue: Codable, Equatable, Sendable {
    case string(String), int(Int), bool(Bool), null

    public var stringValue: String? { if case let .string(s) = self { return s }; return nil }
    public var intValue: Int? { if case let .int(i) = self { return i }; return nil }
    public var boolValue: Bool? { if case let .bool(b) = self { return b }; return nil }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .string(s): try c.encode(s)
        case let .int(i): try c.encode(i)
        case let .bool(b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }
}
