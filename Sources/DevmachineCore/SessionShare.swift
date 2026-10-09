import Foundation

/// What a guest may do in a shared session: watch, or type along.
public enum SessionShareMode: String, Codable, CaseIterable, Sendable {
    case read
    case write

    public var title: String {
        switch self {
        case .read: return "Read only"
        case .write: return "Can type"
        }
    }
}

/// The durations the Share dialog offers, as the `--for` value the tool reads.
public enum SessionShareDuration: String, CaseIterable, Sendable {
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case twoHours = "2h"
    case fourHours = "4h"
    case eightHours = "8h"

    public var title: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        case .eightHours: return "8 hours"
        }
    }
}

public struct SessionShareViewer: Codable, Equatable, Sendable {
    public let connID: String
    public let kind: String
    public let guest: String?
    public let remote: String?

    enum CodingKeys: String, CodingKey {
        case connID = "conn_id"
        case kind, guest, remote
    }

    public init(connID: String, kind: String, guest: String? = nil, remote: String? = nil) {
        self.connID = connID
        self.kind = kind
        self.guest = guest
        self.remote = remote
    }
}

/// One share as `session-share` reports it (JSON contract version 1).
public struct SessionShareInfo: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let session: String
    public let mode: SessionShareMode
    public let createdAt: Date
    public let expiresAt: Date
    public let active: Bool
    public let endedAt: Date?
    public let endReason: String?
    public let url: String?
    public let viewers: [SessionShareViewer]

    enum CodingKeys: String, CodingKey {
        case id, name, session, mode, active, url, viewers
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case endedAt = "ended_at"
        case endReason = "end_reason"
    }

    public init(
        id: String, name: String? = nil, session: String, mode: SessionShareMode, createdAt: Date,
        expiresAt: Date, active: Bool, endedAt: Date? = nil, endReason: String? = nil, url: String? = nil,
        viewers: [SessionShareViewer] = []
    ) {
        self.id = id
        self.name = name
        self.session = session
        self.mode = mode
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.active = active
        self.endedAt = endedAt
        self.endReason = endReason
        self.url = url
        self.viewers = viewers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        session = try c.decode(String.self, forKey: .session)
        mode = try c.decode(SessionShareMode.self, forKey: .mode)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        active = try c.decode(Bool.self, forKey: .active)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        endReason = try c.decodeIfPresent(String.self, forKey: .endReason)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        viewers = try c.decodeIfPresent([SessionShareViewer].self, forKey: .viewers) ?? []
    }

    /// A link on loopback only opens on the machine itself: the share server
    /// has not been published yet.
    public var isLocalOnly: Bool {
        url.map(Self.isLoopback) ?? false
    }

    public static func isLoopback(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}

/// A chat message beside a shared session. The tool has already removed
/// control, escape and invisible characters from `text`.
public struct SessionChatMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let ts: Date
    public let from: String
    public let role: String
    public let text: String

    public var isOwner: Bool { role == "owner" }

    public init(id: String, ts: Date, from: String, role: String, text: String) {
        self.id = id
        self.ts = ts
        self.from = from
        self.role = role
        self.text = text
    }
}

public struct SessionShareStarted: Equatable, Sendable {
    public let share: SessionShareInfo
    public let password: String?
}

/// Builds the `devmachine run` calls that reach the `session-share` package
/// and reads what they print.
public enum SessionShareCommand {
    public static let package = "session-share"
    public static let jsonVersion = 1

    static func run(workspace: String, _ command: [String]) -> [String] {
        ["run", "--workspace", workspace, "--no-log", "--package", package, "--"] + command
    }

    public static func startArguments(
        workspace: String, session: String, mode: SessionShareMode, duration: SessionShareDuration, name: String
    ) -> [String] {
        var command = ["start", session, "--mode", mode.rawValue, "--for", duration.rawValue]
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { command += ["--name", label] }
        return run(workspace: workspace, command + ["--json"])
    }

    public static func stopArguments(workspace: String, id: String) -> [String] {
        run(workspace: workspace, ["stop", id, "--json"])
    }

    public static func extendArguments(workspace: String, id: String, by duration: String) -> [String] {
        run(workspace: workspace, ["extend", id, "--for", duration, "--json"])
    }

    public static func listArguments(workspace: String) -> [String] {
        run(workspace: workspace, ["shares"])
    }

    /// Each workspace runs its own share server, so each gets its own name.
    public static func publicHost(workspace: String, domain: String) -> String {
        "share-\(workspace.lowercased()).\(domain)"
    }

    /// The port the share server listens on, read from the local link it gave.
    public static func port(of url: String) -> Int? {
        URL(string: url)?.port
    }

    public static func exposeAddArguments(workspace: String, port: Int, host: String) -> [String] {
        ["--format", "json", "expose", "add", workspace, String(port), "--host", host, "--publish"]
    }

    public static func proxyArguments(workspace: String, url: String) -> [String] {
        run(workspace: workspace, ["expose", "proxy", "--url", url, "--json"])
    }

    public static func funnelArguments(workspace: String) -> [String] {
        run(workspace: workspace, ["expose", "funnel", "--json"])
    }

    public static let configArguments = ["--format", "json", "config", "show"]

    /// One long run that prints the chat so far, then each new message, one
    /// JSON line each, until it is stopped.
    public static func chatFollowArguments(workspace: String, id: String) -> [String] {
        run(workspace: workspace, ["chat", id, "--follow", "--json"])
    }

    public static func chatSendArguments(workspace: String, id: String, text: String) -> [String] {
        run(workspace: workspace, ["chat", id, "--message", text, "--json"])
    }

    private struct ChatLine: Decodable {
        let version: Int
        let message: SessionChatMessage
    }

    /// A line of `chat --follow --json`, or nil for anything else the stream
    /// carries (ssh noise, a warning).
    public static func parseChatLine(_ line: String) -> SessionChatMessage? {
        guard line.hasPrefix("{"), let parsed = try? decoder.decode(ChatLine.self, from: Data(line.utf8)),
              parsed.version == jsonVersion else { return nil }
        return parsed.message
    }

    /// A link to the same share under a published base address.
    public static func link(base: String, id: String) -> String {
        base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/s/\(id)/"
    }

    public static func parseDomain(_ output: String) -> String? {
        struct Config: Decodable { let domain: String? }
        let domain = (try? JSONDecoder().decode(Config.self, from: Data(output.utf8)))?.domain?
            .trimmingCharacters(in: .whitespaces)
        return domain?.isEmpty == false ? domain : nil
    }

    private struct ExposeBody: Decodable {
        struct Current: Decodable { let url: String }
        let current: Current?
    }

    public static func parseExposedURL(_ output: String) throws -> String? {
        try decode(ExposeBody.self, output).current?.url
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a date: \(text)"))
        }
        return decoder
    }

    /// Go writes RFC 3339 with up to nine fractional digits, which
    /// `ISO8601DateFormatter` rejects; the fraction is cut to milliseconds.
    static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        guard let dot = text.firstIndex(of: "."),
              let end = text[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) else { return nil }
        let fraction = text[text.index(after: dot)..<end].prefix(3)
        let trimmed = text[..<dot] + "." + fraction.padding(toLength: 3, withPad: "0", startingAt: 0) + text[end...]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: String(trimmed))
    }

    private struct Envelope<Body: Decodable>: Decodable {
        let version: Int
        let body: Body

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            version = try c.decode(Int.self, forKey: AnyKey("version"))
            body = try Body(from: decoder)
        }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private struct StartBody: Decodable {
        let share: SessionShareInfo
        let password: String?
    }

    private struct ShareBody: Decodable {
        let share: SessionShareInfo
    }

    private struct ListBody: Decodable {
        let shares: [SessionShareInfo]
    }

    private static func decode<Body: Decodable>(_ type: Body.Type, _ output: String) throws -> Body {
        let envelope = try decoder.decode(Envelope<Body>.self, from: Data(output.utf8))
        guard envelope.version == jsonVersion else {
            throw SessionShareError.unsupportedVersion(envelope.version)
        }
        return envelope.body
    }

    public static func parseStart(_ output: String) throws -> SessionShareStarted {
        let body = try decode(StartBody.self, output)
        return SessionShareStarted(share: body.share, password: body.password)
    }

    public static func parseShare(_ output: String) throws -> SessionShareInfo {
        try decode(ShareBody.self, output).share
    }

    public static func parseList(_ output: String) throws -> [SessionShareInfo] {
        try decode(ListBody.self, output).shares
    }

    /// The CLI refuses a package the workspace does not have ("… is not
    /// installed on …"), or a command an older package does not list ("…
    /// does not accept …").
    public static func isMissingPackage(_ stderr: String) -> Bool {
        stderr.contains("\(package) is not installed on") || stderr.contains("\(package) does not accept")
    }
}

public enum SessionShareError: Error, Equatable, LocalizedError {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            return "session-share answered with JSON version \(version); this app reads version \(SessionShareCommand.jsonVersion)."
        }
    }
}

/// A share this Mac started, kept after it ends so Settings can list it.
public struct SessionShareRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let workspace: String
    public let alias: String
    public let session: String
    public let name: String
    public let mode: SessionShareMode
    public var url: String?
    public let createdAt: Date
    public var expiresAt: Date
    public var endedAt: Date?
    public var endReason: String?

    public init(
        id: String, workspace: String, alias: String, session: String, name: String, mode: SessionShareMode,
        url: String?, createdAt: Date, expiresAt: Date, endedAt: Date? = nil, endReason: String? = nil
    ) {
        self.id = id
        self.workspace = workspace
        self.alias = alias
        self.session = session
        self.name = name
        self.mode = mode
        self.url = url
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.endedAt = endedAt
        self.endReason = endReason
    }

    public init(_ share: SessionShareInfo, workspace: String, alias: String) {
        self.init(
            id: share.id, workspace: workspace, alias: alias, session: share.session,
            name: share.name ?? share.session, mode: share.mode, url: share.url, createdAt: share.createdAt,
            expiresAt: share.expiresAt, endedAt: share.endedAt, endReason: share.endReason)
    }

    public func isLive(at now: Date) -> Bool {
        endedAt == nil && now < expiresAt
    }

    /// What the tool says now wins: a stop or an extension made in a terminal
    /// shows up here too.
    public mutating func update(from share: SessionShareInfo) {
        url = share.url ?? url
        expiresAt = share.expiresAt
        endedAt = share.endedAt
        endReason = share.endReason
    }

    public mutating func markEnded(_ reason: String, at now: Date) {
        guard endedAt == nil else { return }
        endedAt = now
        endReason = reason
    }
}

/// Every share this Mac started, newest first, in one JSON file. A file that
/// cannot be read is no history: losing it costs nothing a share needs.
public struct SessionShareHistory: Sendable {
    private struct File: Codable {
        let version: Int
        let shares: [SessionShareRecord]
    }

    private static let version = 1
    public static let limit = 200

    public let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return support.appendingPathComponent("Devmachine/shares.json")
    }

    public func load() -> [SessionShareRecord] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data), file.version == Self.version else { return [] }
        return file.shares
    }

    public func save(_ records: [SessionShareRecord]) throws {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(File(version: Self.version, shares: Self.trimmed(records)))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    static func trimmed(_ records: [SessionShareRecord]) -> [SessionShareRecord] {
        Array(records.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    /// Lays a workspace's answer over the records: known shares take the
    /// tool's state; a live record the tool no longer lists has ended (its
    /// history was cleaned up on the machine).
    public static func merge(
        _ records: [SessionShareRecord], with shares: [SessionShareInfo], workspace: String, now: Date
    ) -> [SessionShareRecord] {
        let byID = Dictionary(shares.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return records.map { record in
            guard record.workspace == workspace else { return record }
            var updated = record
            if let share = byID[record.id] {
                updated.update(from: share)
            } else if updated.endedAt == nil {
                updated.markEnded("gone", at: now)
            }
            return updated
        }
    }
}
