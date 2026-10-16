import Foundation

public enum ChatFailureKind: Equatable, Sendable {
    case unreachable
    case loginRefused
    case hostKeyRejected
    case harnessMissing
    case harnessLoggedOut
    case harnessFailed
    case cancelled
    case sessionNotFound
    case transcriptNotFound
    case harnessUnsupported
    case needsNewerCLI
    /// The CLI turned the request down before any harness ran: an unknown
    /// workspace, flags that conflict.
    case refused
    case other(String)

    public init(wire: String) {
        switch wire {
        case "unreachable": self = .unreachable
        case "login-refused": self = .loginRefused
        case "host-key-rejected": self = .hostKeyRejected
        case "harness-missing": self = .harnessMissing
        case "harness-logged-out": self = .harnessLoggedOut
        case "harness-failed": self = .harnessFailed
        case "cancelled": self = .cancelled
        case "session-not-found": self = .sessionNotFound
        case "transcript-not-found": self = .transcriptNotFound
        case "harness-unsupported": self = .harnessUnsupported
        default: self = .other(wire)
        }
    }
}

public struct ChatFailure: Equatable, Sendable {
    public var kind: ChatFailureKind
    public var message: String

    public init(kind: ChatFailureKind, message: String) {
        self.kind = kind
        self.message = message
    }

    /// The CLI ended without an `error` line: an older CLI that has no
    /// `chat`, or a process that died. `output` is everything it printed.
    public static func fromExit(status: Int32, output: String) -> ChatFailure {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if isOlderCLI(text) {
            return ChatFailure(kind: .needsNewerCLI, message: text)
        }
        if text.lowercased().hasPrefix("error:") {
            return ChatFailure(kind: .refused, message: text)
        }
        let detail = text.isEmpty ? "devmachine chat stopped with exit status \(status) and said nothing." : text
        return ChatFailure(kind: .harnessFailed, message: detail)
    }

    public static func isOlderCLI(_ output: String) -> Bool {
        ["chat", "ask", "continue"].contains { output.contains("unknown command \"\($0)\"") }
    }
}

/// One line of `devmachine chat send|ask` output.
public enum ChatEvent: Equatable, Sendable {
    case started(ChatRecord)
    case text(String)
    case tool(ChatTool)
    /// The harness refused a tool that needed approval a one-shot run
    /// cannot give.
    case denied(ChatTool)
    case done(ChatRecord)
    case error(ChatFailure)
}

public enum ChatEventDecoder {
    private struct Line: Decodable {
        let type: String
        let chat: ChatRecord?
        let delta: String?
        let name: String?
        let summary: String?
        let kind: String?
        let message: String?
    }

    /// Nil for anything that is not an event: stderr shares the stream,
    /// so a log line or a warning is skipped, not an error.
    public static func decode(_ line: String) -> ChatEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{"),
              let parsed = try? JSONDecoder().decode(Line.self, from: Data(trimmed.utf8)) else { return nil }
        switch parsed.type {
        case "started": return parsed.chat.map(ChatEvent.started)
        case "text": return parsed.delta.map(ChatEvent.text)
        case "tool": return .tool(ChatTool(name: parsed.name ?? "", summary: parsed.summary ?? ""))
        case "denied": return .denied(ChatTool(name: parsed.name ?? "", summary: parsed.summary ?? ""))
        case "done": return parsed.chat.map(ChatEvent.done)
        case "error":
            return .error(ChatFailure(
                kind: ChatFailureKind(wire: parsed.kind ?? ""), message: parsed.message ?? ""))
        default: return nil
        }
    }
}
