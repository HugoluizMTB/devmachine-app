import Foundation

/// Whether Ask can answer about a session: the CLI reads the session's
/// transcript on each question, for Claude and Codex sessions.
public enum AskMode: Equatable, Sendable {
    case supported(HarnessID)
    case unsupported(HarnessID?)

    public init(harness: HarnessID?) {
        if let harness, ChatHarness.supported.contains(harness) {
            self = .supported(harness)
        } else {
            self = .unsupported(harness)
        }
    }

    public var harness: HarnessID? {
        switch self {
        case let .supported(id): return id
        case let .unsupported(id): return id
        }
    }

    public var isSupported: Bool {
        if case .supported = self { return true }
        return false
    }

    public var subtitle: String {
        switch self {
        case let .supported(id): return "about this session · \(ChatHarness.title(id))"
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
