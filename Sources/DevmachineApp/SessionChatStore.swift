import Foundation
import DevmachineCore

protocol SessionChatStreaming: Sendable {
    /// Runs until the stream ends or the task is cancelled, handing over each
    /// line of output.
    func stream(_ arguments: [String], line: @escaping @Sendable (String) -> Void) async throws -> Int32
}

struct ProcessSessionChatStreamer: SessionChatStreaming {
    var cli: @Sendable () throws -> DevmachineCLI = { try DevmachineCLI.resolve() }

    func stream(_ arguments: [String], line: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        let instance = try cli()
        return try await StreamingProcess.run(
            executable: instance.executable, arguments: arguments, environment: instance.environment(), output: line)
    }
}

/// The chat beside each share this Mac started. A live share keeps one
/// `chat --follow` run open, so guest messages arrive as they are written;
/// it ends with the share. Sending is one call per message, on a button.
@MainActor
final class SessionChatStore: ObservableObject {
    static let shared = NSClassFromString("XCTestCase") == nil && !DemoMode.isActive
        ? SessionChatStore(streamer: ProcessSessionChatStreamer(), runner: ProcessSessionShareRunner(), follows: true)
        : SessionChatStore(
            streamer: ProcessSessionChatStreamer(cli: { throw DevmachineCLIError.commandFailed("no CLI under tests or in demo mode") }),
            runner: ProcessSessionShareRunner(cli: { throw DevmachineCLIError.commandFailed("no CLI under tests or in demo mode") }))

    @Published private(set) var messages: [String: [SessionChatMessage]] = [:]
    @Published private(set) var unread: [String: Int] = [:]
    @Published private(set) var failure: [String: String] = [:]
    @Published private(set) var sending: Set<String> = []

    /// The share whose chat is on screen: its messages are read as they come.
    var visible: String?

    private let streamer: any SessionChatStreaming
    private let runner: any SessionShareRunning
    private let follows: Bool
    private var streams: [String: Task<Void, Never>] = [:]
    var retryDelay: UInt64 = 5_000_000_000

    init(streamer: any SessionChatStreaming, runner: any SessionShareRunning, follows: Bool = false) {
        self.streamer = streamer
        self.runner = runner
        self.follows = follows
    }

    /// Follows the chat of every live share and lets go of the rest.
    func track(_ records: [SessionShareRecord]) {
        let live = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, task) in streams where live[id] == nil {
            task.cancel()
            streams[id] = nil
        }
        guard follows else { return }
        for record in live.values where streams[record.id] == nil {
            follow(record)
        }
    }

    func follow(_ record: SessionShareRecord) {
        let id = record.id
        let arguments = SessionShareCommand.chatFollowArguments(workspace: record.workspace, id: id)
        streams[id] = Task { [weak self] in
            while !Task.isCancelled {
                let status = try? await self?.streamer.stream(arguments) { line in
                    guard let message = SessionShareCommand.parseChatLine(line) else { return }
                    Task { @MainActor in self?.receive(message, share: id) }
                }
                if Task.isCancelled { return }
                await MainActor.run { self?.failure[id] = status == 0 ? nil : "The chat connection dropped; reconnecting." }
                try? await Task.sleep(nanoseconds: self?.retryDelay ?? 5_000_000_000)
            }
        }
    }

    func receive(_ message: SessionChatMessage, share id: String) {
        var list = messages[id] ?? []
        guard !list.contains(where: { $0.id == message.id }) else { return }
        if message.isOwner, let i = list.firstIndex(where: { Self.isPending($0) && $0.text == message.text }) {
            list.remove(at: i)
        }
        list.append(message)
        messages[id] = list
        failure[id] = nil
        if visible != id && !message.isOwner {
            unread[id, default: 0] += 1
        }
    }

    func markRead(_ id: String) {
        visible = id
        if unread[id] != nil { unread[id] = nil }
    }

    static let pendingPrefix = "pending-"

    static func isPending(_ message: SessionChatMessage) -> Bool {
        message.id.hasPrefix(pendingPrefix)
    }

    /// The message shows at once as sending: a login to some machines takes
    /// seconds, and the real one replaces it when it comes back on the stream.
    func send(_ text: String, to record: SessionShareRecord) async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        let pending = SessionChatMessage(
            id: Self.pendingPrefix + UUID().uuidString, ts: Date(), from: "You", role: "owner", text: body)
        messages[record.id, default: []].append(pending)
        sending.insert(record.id)
        defer { sending.remove(record.id) }
        func drop() { messages[record.id]?.removeAll { $0.id == pending.id } }
        do {
            let output = try await runner.run(
                SessionShareCommand.chatSendArguments(workspace: record.workspace, id: record.id, text: body))
            if output.exitCode == 0 {
                failure[record.id] = nil
                return true
            }
            drop()
            let message = output.stderr.isEmpty ? output.stdout : output.stderr
            failure[record.id] = SessionShareCommand.isMissingPackage(message)
                ? "This workspace's session-share package is too old for the chat. Sync it with packages v49 or newer."
                : message
        } catch {
            drop()
            failure[record.id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        return false
    }
}
