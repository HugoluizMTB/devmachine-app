import Foundation

/// One conversation as the app draws it: what was said, whether an answer
/// is still coming, and how the last turn ended.
public struct ChatConversation: Equatable, Sendable {
    public var record: ChatRecord?
    public var messages: [ChatMessage]
    public var isStreaming: Bool
    public var failure: ChatFailure?
    public var wasStopped: Bool
    /// The CLI's latest status while no part of the answer has come yet.
    public var status: String?

    public init(
        record: ChatRecord? = nil, messages: [ChatMessage] = [], isStreaming: Bool = false,
        failure: ChatFailure? = nil, wasStopped: Bool = false, status: String? = nil
    ) {
        self.record = record
        self.messages = messages
        self.isStreaming = isStreaming
        self.failure = failure
        self.wasStopped = wasStopped
        self.status = status
    }

    public var lastUserText: String? {
        messages.last { $0.role == .user }?.text
    }

    public mutating func begin(userText: String, at date: Date) {
        messages.append(ChatMessage(role: .user, text: userText, at: date))
        isStreaming = true
        failure = nil
        wasStopped = false
        status = nil
    }

    public mutating func apply(_ event: ChatEvent) {
        switch event {
        case .text, .tool, .denied, .done, .error:
            status = nil
        case .status, .started:
            break
        }
        switch event {
        case let .status(update):
            if isStreaming { status = update.message }
        case let .started(chat):
            record = chat
        case let .text(delta):
            updateAnswer { $0.text += delta }
        case let .tool(tool):
            updateAnswer { $0.tools.append(tool) }
        case let .denied(tool):
            updateAnswer { $0.denied.append(tool) }
        case let .done(chat):
            record = chat
            isStreaming = false
        case let .error(error):
            isStreaming = false
            if error.kind == .cancelled {
                wasStopped = true
            } else {
                failure = error
            }
        }
    }

    /// The process ended. Without a `done` or `error` line first, the turn
    /// failed, and what it printed is the reason.
    public mutating func processEnded(status: Int32, output: String) {
        guard isStreaming else { return }
        isStreaming = false
        self.status = nil
        failure = ChatFailure.fromExit(status: status, output: output)
    }

    public mutating func stop() {
        guard isStreaming else { return }
        isStreaming = false
        status = nil
        wasStopped = true
    }

    private mutating func updateAnswer(_ change: (inout ChatMessage) -> Void) {
        if messages.last?.role != .assistant {
            messages.append(ChatMessage(role: .assistant, text: "", at: Date()))
        }
        change(&messages[messages.count - 1])
    }
}

public enum ChatHarness {
    public static let supported: [HarnessID] = [.claude, .codex]

    public static func title(_ id: HarnessID) -> String {
        switch id {
        case .claude: return "Claude"
        case .codex: return "Codex"
        default: return id.rawValue.prefix(1).uppercased() + id.rawValue.dropFirst()
        }
    }

    /// The workspace package that installs the harness's CLI.
    public static func package(_ id: HarnessID) -> String? {
        switch id {
        case .claude: return "claude-code"
        case .codex: return "codex"
        default: return nil
        }
    }
}
