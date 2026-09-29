import Foundation

/// One chunk of transcript text to scan for references, with the event's
/// timestamp (ISO-8601, or empty when the event carries none).
public struct ContextRefBlob: Sendable {
    public let text: String
    public let timestamp: String

    public init(text: String, timestamp: String) {
        self.text = text
        self.timestamp = timestamp
    }
}

/// A GitHub pull request or issue the transcript named, by URL or by a
/// `gh pr`/`gh issue` command.
public struct ContextGitHubRef: Equatable, Sendable {
    public var host: String
    public var repo: String
    public var num: Int
    public var firstTimestamp: String
    public var lastTimestamp: String
    public var count: Int
    public var url: String
}

/// A generic link the transcript named, deduplicated by its URL with the
/// query string stripped.
public struct ContextLinkRef: Equatable, Sendable {
    public var count: Int
    public var lastTimestamp: String
}

public struct ContextExtractedRefs: Sendable {
    public var github: [String: ContextGitHubRef] = [:]
    public var links: [String: ContextLinkRef] = [:]

    public init() {}

    /// Folds another transcript's references into this one — a worktree
    /// session and its parent write to different files, and both count.
    public mutating func merge(_ other: ContextExtractedRefs) {
        for (key, ref) in other.github {
            if var kept = github[key] {
                kept.count += ref.count
                keepLatest(&kept.lastTimestamp, ref.lastTimestamp)
                github[key] = kept
            } else {
                github[key] = ref
            }
        }
        for (key, link) in other.links {
            if var kept = links[key] {
                kept.count += link.count
                keepLatest(&kept.lastTimestamp, link.lastTimestamp)
                links[key] = kept
            } else {
                links[key] = link
            }
        }
    }
}

/// Moves the kept timestamp forward, comparing as instants rather than
/// strings: a string compare puts `...00Z` above `...00.500Z`.
private func keepLatest(_ kept: inout String, _ candidate: String) {
    guard let candidateDate = ContextTimestamp.parse(candidate) else { return }
    if let keptDate = ContextTimestamp.parse(kept), keptDate >= candidateDate { return }
    kept = candidate
}

public enum ContextTimestamp {
    private nonisolated(unsafe) static let formatterWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private nonisolated(unsafe) static let formatter: ISO8601DateFormatter = ISO8601DateFormatter()

    public static func parse(_ ts: String) -> Date? {
        guard !ts.isEmpty else { return nil }
        return formatterWithFraction.date(from: ts) ?? formatter.date(from: ts)
    }
}

private let noiseExtensions = [".svg", ".png", ".ico", ".gif", ".css", ".js", ".woff", ".woff2"]
private let noiseHostPrefixes = ["static.", "cdn.", "assets."]

private let ghCommandRegex = try! NSRegularExpression(
    pattern: #"\bgh\s+(?:pr|issue)\s+(view|checks|merge|comment|diff|edit|close|reopen|ready|review)((?:\s+[^\s"';|&]+)*)"#
)
private let ghCommandRepoRegex = try! NSRegularExpression(pattern: #"(?:-R|--repo)[=\s]+([\w.-]+/[\w.-]+)"#)
private let urlRegex = try! NSRegularExpression(pattern: #"https?://[^\s"'<>)\\\]]+"#)
/// An issue key in the URL path — Linear (`/issue/ABC-123`), Jira
/// (`/browse/ABC-123`) and anything else that numbers issues the same way.
/// No tracker is named here.
private let issueKeyRegex = try! NSRegularExpression(pattern: #"/([A-Z][A-Z0-9]{1,9}-\d+)(?=[/?#]|$)"#)

private func prURLRegex(hosts: [String]) -> NSRegularExpression {
    let escaped = hosts.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
    return try! NSRegularExpression(pattern: "(\(escaped))/([\\w.-]+/[\\w.-]+)/(?:pull|issues)/(\\d+)")
}

extension NSRegularExpression {
    func matches(in text: String) -> [NSTextCheckingResult] {
        matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    func group(_ result: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard index < result.numberOfRanges, let range = Range(result.range(at: index), in: text) else {
            return nil
        }
        return String(text[range])
    }
}

/// The PR/issue number in a `gh` command's argument string, or nil.
///
/// `gh` takes it as the first argument, so only that one counts. Reading any
/// number in the command turns `--interval 15` into PR #15.
func contextPRNumber(fromArgs args: String) -> Int? {
    guard let first = args.split(separator: " ").first else { return nil }
    return Int(first)
}

public func contextExtractRefs(
    blobs: [ContextRefBlob], defaultRepo: String?, githubHosts: [String]
) -> ContextExtractedRefs {
    var refs = ContextExtractedRefs()
    let prRegex = prURLRegex(hosts: githubHosts)

    for blob in blobs {
        let text = blob.text
        let ts = blob.timestamp

        for m in prRegex.matches(in: text) {
            guard let host = prRegex.group(m, 1, in: text),
                  let repo = prRegex.group(m, 2, in: text),
                  let numStr = prRegex.group(m, 3, in: text), let num = Int(numStr)
            else { continue }
            recordGitHub(&refs, host: host, repo: repo, num: num, ts: ts)
        }

        for m in ghCommandRegex.matches(in: text) {
            guard let args = ghCommandRegex.group(m, 2, in: text) else { continue }
            let repoRange = ghCommandRepoRegex.matches(in: args).first
            let repo = repoRange.flatMap { ghCommandRepoRegex.group($0, 1, in: args) } ?? defaultRepo
            guard let repo else { continue }
            let numberArgs: String
            if repoRange != nil {
                numberArgs = ghCommandRepoRegex.stringByReplacingMatches(
                    in: args, range: NSRange(args.startIndex..., in: args), withTemplate: " "
                )
            } else {
                numberArgs = args
            }
            guard let num = contextPRNumber(fromArgs: numberArgs.trimmingCharacters(in: .whitespaces)) else {
                continue
            }
            recordGitHub(&refs, host: "github.com", repo: repo, num: num, ts: ts)
        }

        for m in urlRegex.matches(in: text) {
            guard let raw = urlRegex.group(m, 0, in: text) else { continue }
            var url = raw
            while let last = url.last, ".,;:`".contains(last) {
                url.removeLast()
            }
            if url.contains("{") { continue }
            if prRegex.matches(in: url).isEmpty == false { continue }
            let base = String(url.split(separator: "?", maxSplits: 1).first ?? Substring(url))
            let host = contextHost(of: base)
            let lowerBase = base.lowercased()
            if noiseExtensions.contains(where: { lowerBase.hasSuffix($0) }) { continue }
            if noiseHostPrefixes.contains(where: { host.hasPrefix($0) }) { continue }
            var link = refs.links[base] ?? ContextLinkRef(count: 0, lastTimestamp: ts)
            link.count += 1
            link.lastTimestamp = ts
            refs.links[base] = link
        }
    }
    return refs
}

private func recordGitHub(_ refs: inout ContextExtractedRefs, host: String, repo: String, num: Int, ts: String) {
    let key = "\(repo)#\(num)"
    var entry = refs.github[key] ?? ContextGitHubRef(
        host: host, repo: repo, num: num, firstTimestamp: ts, lastTimestamp: ts, count: 0,
        url: "https://\(host)/\(repo)/pull/\(num)"
    )
    entry.count += 1
    keepLatest(&entry.lastTimestamp, ts)
    refs.github[key] = entry
}

private func contextHost(of url: String) -> String {
    guard url.contains("://") else { return "" }
    let parts = url.split(separator: "/", omittingEmptySubsequences: false)
    return parts.count > 2 ? String(parts[2]) : ""
}

// MARK: - PR / link mapping

private let reviewMap: [String: String] = [
    "APPROVED": "approved", "CHANGES_REQUESTED": "changes", "REVIEW_REQUIRED": "required",
]

public func contextMapPRs(_ entries: [ContextGitHubPR]) -> [ContextEngineResult.PR] {
    entries.map { entry in
        let state = entry.isDraft ? "draft" : entry.state.lowercased()
        return ContextEngineResult.PR(
            number: entry.num, repo: entry.repo, title: entry.title, url: entry.url,
            ci: entry.ci, review: reviewMap[entry.review ?? ""] ?? "none", state: state,
            threads: entry.threads, lastSeen: entry.lastTimestamp.isEmpty ? nil : entry.lastTimestamp
        )
    }
}

private func contextLinkLabel(_ url: String) -> String {
    var s = url
    for prefix in ["https://", "http://"] {
        if s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
            break
        }
    }
    while s.hasSuffix("/") { s.removeLast() }
    return s.count <= 48 ? s : String(s.prefix(47)) + "…"
}

/// The service a URL belongs to, from its domain: linear, atlassian, github.
/// No tracker is special-cased — a new one names itself.
public func contextServiceOf(_ url: String) -> String {
    var s = url
    for prefix in ["https://", "http://"] {
        if s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
            break
        }
    }
    let host = String(s.split(separator: "/", maxSplits: 1).first ?? Substring(s))
        .split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
    let parts = host.split(separator: ".").map(String.init).filter { $0 != "www" }
    let name = parts.count >= 2 ? parts[parts.count - 2] : (parts.first ?? "web")
    return name.hasSuffix("usercontent") ? String(name.dropLast("usercontent".count)) : name
}

public func contextMapLinks(_ links: [(url: String, count: Int, lastTimestamp: String)]) -> [ContextEngineResult.Link] {
    var out: [ContextEngineResult.Link] = []
    var seenKeys = Set<String>()
    for l in links {
        if let m = issueKeyRegex.matches(in: l.url).first, let key = issueKeyRegex.group(m, 1, in: l.url) {
            if seenKeys.contains(key) { continue }
            seenKeys.insert(key)
            out.append(ContextEngineResult.Link(url: l.url, label: key, kind: contextServiceOf(l.url)))
        } else {
            out.append(ContextEngineResult.Link(url: l.url, label: contextLinkLabel(l.url), kind: contextServiceOf(l.url)))
        }
    }
    return out
}
