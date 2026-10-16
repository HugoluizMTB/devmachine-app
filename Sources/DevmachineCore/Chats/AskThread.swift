import Foundation

/// How Ask answers about a session: a fork of a Claude session, or a new
/// Codex thread fed from the session's transcript.
public enum AskMode: Equatable, Sendable {
    case fork
    case transcript
    case unsupported(HarnessID?)

    public init(harness: HarnessID?) {
        switch harness {
        case .claude?: self = .fork
        case .codex?: self = .transcript
        default: self = .unsupported(harness)
        }
    }

    public var harness: HarnessID? {
        switch self {
        case .fork: return .claude
        case .transcript: return .codex
        case let .unsupported(id): return id
        }
    }

    public var isSupported: Bool {
        if case .unsupported = self { return false }
        return true
    }

    public var subtitle: String {
        switch self {
        case .fork: return "about this session · Claude (fork)"
        case .transcript: return "about this session · Codex (transcript search)"
        case let .unsupported(id?): return "Ask is not available for \(ChatHarness.title(id)) yet"
        case .unsupported(nil): return "Ask needs a Claude or Codex session"
        }
    }
}

/// Which session an Ask thread belongs to.
public struct AskSessionKey: Hashable, Sendable {
    public let place: ChatPlace
    public let session: String

    public init(place: ChatPlace, session: String) {
        self.place = place
        self.session = session
    }
}

public enum AskThreadPicker {
    /// The session's newest ask chat, ignoring any started before `reset`.
    public static func latest(in records: [ChatRecord], key: AskSessionKey, after reset: Date?) -> ChatRecord? {
        records
            .filter { $0.isAsk && $0.place == key.place && $0.session == key.session }
            .filter { record in reset.map { record.createdAt > $0 } ?? true }
            .max { $0.updatedAt < $1.updatedAt }
    }
}
