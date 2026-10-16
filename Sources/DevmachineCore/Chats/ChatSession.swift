import Foundation

/// A long-lived `chat session` (or `chat ask --serve`): the harness starts
/// once and answers each message written to its stdin, so a message does
/// not wait for the harness to start.
public enum ChatSessionLine: Equatable, Sendable {
    /// The harness is up; `chat` is nil until the session's first message.
    case ready(ChatRecord?)
    case event(ChatEvent)
    /// Printed before the process exits: "idle", "eof" or "error".
    case closed(String)

    private struct Line: Decodable {
        let type: String
        let chat: ChatRecord?
        let reason: String?
    }

    /// A CLI from before sessions refuses the command or one of its flags
    /// (it reads `chat session --local` as an unknown flag); the app then
    /// sends each message with `chat send` as before.
    public static func isUnsupported(_ output: String) -> Bool {
        ["unknown command", "unknown flag", "flag provided but not defined"].contains { output.contains($0) }
    }

    public static func decode(_ line: String) -> ChatSessionLine? {
        if let event = ChatEventDecoder.decode(line) { return .event(event) }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{"),
              let parsed = try? JSONDecoder().decode(Line.self, from: Data(trimmed.utf8)) else { return nil }
        switch parsed.type {
        case "ready": return .ready(parsed.chat)
        case "closed": return .closed(parsed.reason ?? "")
        default: return nil
        }
    }
}

/// What the app writes to a session's stdin, one JSON line each.
public enum ChatSessionInput {
    public static func send(_ text: String) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: ["type": "send", "text": text], options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    public static let cancel = #"{"type":"cancel"}"#
}

/// What a warm session was started for. A new chat sent with anything else
/// needs another session.
public struct ChatSessionSpec: Equatable, Hashable, Sendable {
    public var harness: HarnessID
    public var place: ChatPlace
    public var mcp: Bool

    public init(harness: HarnessID, place: ChatPlace, mcp: Bool) {
        self.harness = harness
        self.place = place
        self.mcp = mcp
    }
}
