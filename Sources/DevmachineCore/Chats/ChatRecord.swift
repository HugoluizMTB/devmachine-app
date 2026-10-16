import Foundation

/// One conversation as `devmachine chat` stores it. `workspace` is
/// `"local"` for a chat that runs on this Mac.
public struct ChatRecord: Codable, Equatable, Identifiable, Sendable {
    public static let localWorkspace = "local"
    public static let chatKind = "chat"
    public static let askKind = "ask"

    public var id: String
    public var title: String
    public var harness: HarnessID
    public var workspace: String
    public var folder: String
    public var harnessSessionID: String
    public var createdAt: Date
    public var updatedAt: Date
    public var kind: String
    public var session: String?
    public var sourceSessionID: String?
    public var mode: String?

    public init(
        id: String, title: String, harness: HarnessID, workspace: String, folder: String = "",
        harnessSessionID: String = "", createdAt: Date, updatedAt: Date, kind: String = ChatRecord.chatKind,
        session: String? = nil, sourceSessionID: String? = nil, mode: String? = nil
    ) {
        self.id = id
        self.title = title
        self.harness = harness
        self.workspace = workspace
        self.folder = folder
        self.harnessSessionID = harnessSessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.kind = kind
        self.session = session
        self.sourceSessionID = sourceSessionID
        self.mode = mode
    }

    public var isLocal: Bool { workspace == Self.localWorkspace }
    public var isAsk: Bool { kind == Self.askKind }
    public var place: ChatPlace { isLocal ? .local : .workspace(workspace) }

    enum CodingKeys: String, CodingKey {
        case id, title, harness, workspace, folder, kind, session, mode
        case harnessSessionID = "harness_session_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sourceSessionID = "source_session_id"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        harness = HarnessID(rawValue: try values.decodeIfPresent(String.self, forKey: .harness) ?? "claude")
        workspace = try values.decodeIfPresent(String.self, forKey: .workspace) ?? Self.localWorkspace
        if workspace.isEmpty { workspace = Self.localWorkspace }
        folder = try values.decodeIfPresent(String.self, forKey: .folder) ?? ""
        harnessSessionID = try values.decodeIfPresent(String.self, forKey: .harnessSessionID) ?? ""
        createdAt = ChatDate.parse(try values.decodeIfPresent(String.self, forKey: .createdAt)) ?? .distantPast
        updatedAt = ChatDate.parse(try values.decodeIfPresent(String.self, forKey: .updatedAt)) ?? createdAt
        kind = try values.decodeIfPresent(String.self, forKey: .kind) ?? Self.chatKind
        session = try values.decodeIfPresent(String.self, forKey: .session)
        sourceSessionID = try values.decodeIfPresent(String.self, forKey: .sourceSessionID)
        mode = try values.decodeIfPresent(String.self, forKey: .mode)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(harness.rawValue, forKey: .harness)
        try values.encode(workspace, forKey: .workspace)
        try values.encode(folder, forKey: .folder)
        try values.encode(harnessSessionID, forKey: .harnessSessionID)
        try values.encode(ChatDate.format(createdAt), forKey: .createdAt)
        try values.encode(ChatDate.format(updatedAt), forKey: .updatedAt)
        try values.encode(kind, forKey: .kind)
        try values.encodeIfPresent(session, forKey: .session)
        try values.encodeIfPresent(sourceSessionID, forKey: .sourceSessionID)
        try values.encodeIfPresent(mode, forKey: .mode)
    }
}

public struct ChatTool: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var summary: String

    public init(name: String, summary: String) {
        self.name = name
        self.summary = summary
    }

    public init(from decoder: Decoder) throws {
        if let line = try? decoder.singleValueContainer().decode(String.self) {
            self.init(name: "", summary: line)
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try values.decodeIfPresent(String.self, forKey: .name) ?? "",
            summary: try values.decodeIfPresent(String.self, forKey: .summary) ?? "")
    }

    public var line: String { [name, summary].filter { !$0.isEmpty }.joined(separator: " ") }
}

public struct ChatMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user, assistant
    }

    public var role: Role
    public var text: String
    public var tools: [ChatTool]
    public var at: Date?

    public init(role: Role, text: String, tools: [ChatTool] = [], at: Date? = nil) {
        self.role = role
        self.text = text
        self.tools = tools
        self.at = at
    }

    enum CodingKeys: String, CodingKey { case role, text, tools, at }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        role = Role(rawValue: try values.decodeIfPresent(String.self, forKey: .role) ?? "") ?? .assistant
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
        tools = try values.decodeIfPresent([ChatTool].self, forKey: .tools) ?? []
        at = ChatDate.parse(try values.decodeIfPresent(String.self, forKey: .at))
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(role.rawValue, forKey: .role)
        try values.encode(text, forKey: .text)
        try values.encode(tools, forKey: .tools)
        try values.encodeIfPresent(at.map(ChatDate.format), forKey: .at)
    }
}

/// `chat show ID --json`: the record and its messages, either under
/// `chat` or as one object with `messages` beside the record's fields.
public struct ChatShow: Decodable, Equatable, Sendable {
    public var record: ChatRecord
    public var messages: [ChatMessage]

    public init(record: ChatRecord, messages: [ChatMessage]) {
        self.record = record
        self.messages = messages
    }

    enum CodingKeys: String, CodingKey { case chat, record, messages }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try values.decodeIfPresent(ChatRecord.self, forKey: .chat)
            ?? values.decodeIfPresent(ChatRecord.self, forKey: .record) {
            record = nested
        } else {
            record = try ChatRecord(from: decoder)
        }
        messages = try values.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
    }
}

/// `chat list --json`: a bare array, or the array under `chats`.
public enum ChatListDecoder {
    private struct Wrapped: Decodable { let chats: [ChatRecord]? }

    public static func decode(_ data: Data) throws -> [ChatRecord] {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([ChatRecord].self, from: data) { return list }
        return try decoder.decode(Wrapped.self, from: data).chats ?? []
    }
}

enum ChatDate {
    private static let fractionalSeconds = try? NSRegularExpression(pattern: #"\.\d+"#)

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: raw) { return date }
        guard let regex = fractionalSeconds,
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range, in: raw) else { return nil }
        let digits = raw[range].dropFirst()
        let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: raw.replacingCharacters(in: range, with: "." + millis))
    }

    static func format(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
