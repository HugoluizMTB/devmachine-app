import AppKit
import Foundation
import DevmachineCore

struct ChatCommandOutput: Equatable, Sendable {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

/// How the store reaches `devmachine chat`. Tests hand it a fake; the demo
/// never runs anything.
protocol ChatCommandRunning: Sendable {
    /// Runs until the process ends or the task is cancelled, handing over
    /// each line of stdout and stderr in the order they were written.
    func stream(_ arguments: [String], line: @escaping @Sendable (String) -> Void) async throws -> Int32
    func run(_ arguments: [String]) async throws -> ChatCommandOutput
    /// Starts a long-lived session; throws where sessions cannot run.
    func openSession(
        _ arguments: [String], line: @escaping @Sendable (String) -> Void,
        exited: @escaping @Sendable (Int32) -> Void
    ) throws -> any ChatSessionChannel
}

extension ChatCommandRunning {
    func openSession(
        _ arguments: [String], line: @escaping @Sendable (String) -> Void,
        exited: @escaping @Sendable (Int32) -> Void
    ) throws -> any ChatSessionChannel {
        throw ChatSessionsUnavailable()
    }
}

struct ProcessChatCommandRunner: ChatCommandRunning {
    var cli: @Sendable () throws -> DevmachineCLI = { try DevmachineCLI.resolve() }

    func stream(_ arguments: [String], line: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        let instance = try cli()
        return try await ChatProcess.run(
            executable: instance.executable, arguments: arguments, environment: instance.environment(), line: line)
    }

    func openSession(
        _ arguments: [String], line: @escaping @Sendable (String) -> Void,
        exited: @escaping @Sendable (Int32) -> Void
    ) throws -> any ChatSessionChannel {
        let instance = try cli()
        return try ChatSessionProcess(
            executable: instance.executable, arguments: arguments, environment: instance.environment(), line: line,
            exited: exited)
    }

    func run(_ arguments: [String]) async throws -> ChatCommandOutput {
        let instance = try cli()
        return try await Task.detached {
            let result = try instance.runner.runCapturing(
                executable: instance.executable, args: arguments, environment: instance.environment())
            return ChatCommandOutput(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode)
        }.value
    }
}

/// Reads the process's output on one thread to the end before it returns,
/// so the last line (`done` or `error`) always arrives before the exit.
/// A cancelled task sends SIGTERM; the CLI then ends with `cancelled`.
enum ChatProcess {
    static func run(
        executable: String, arguments: [String], environment: [String: String],
        line: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let handle = pipe.fileHandleForReading
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var buffer = Data()
                    while true {
                        let data = handle.availableData
                        if data.isEmpty { break }
                        buffer.append(data)
                        while let newline = buffer.firstIndex(of: 0x0A) {
                            let text = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                            buffer.removeSubrange(buffer.startIndex...newline)
                            if !text.isEmpty { line(text) }
                        }
                    }
                    if !buffer.isEmpty { line(String(decoding: buffer, as: UTF8.self)) }
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

struct UnavailableChatRunner: ChatCommandRunning {
    func stream(_ arguments: [String], line: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        throw DevmachineCLIError.commandFailed("devmachine chat does not run under tests or in demo mode")
    }

    func run(_ arguments: [String]) async throws -> ChatCommandOutput {
        throw DevmachineCLIError.commandFailed("devmachine chat does not run under tests or in demo mode")
    }
}

/// What the new chat page holds before its first message.
struct ChatDraft: Equatable {
    var text = ""
    var harness: HarnessID?
    var place: ChatPlace?
}

enum ChatPicker: Hashable {
    case harness
    case workspace
}

/// Every chat the app shows. The CLI keeps the conversations; this store
/// lists them, runs one `chat send` per message and keeps what each
/// conversation looks like while it streams.
@MainActor
final class ChatStore: ObservableObject {
    static let shared: ChatStore = {
        let live = NSClassFromString("XCTestCase") == nil && !DemoMode.isActive
        let store = ChatStore(runner: live ? ProcessChatCommandRunner() : UnavailableChatRunner())
        if DemoMode.isActive { DemoChats.seed(store) }
        if live {
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { store.closeAllSessions() }
            }
        }
        return store
    }()

    static let pendingPrefix = "pending-"
    static let titleLength = 60

    @Published private(set) var records: [ChatRecord] = []
    @Published private(set) var conversations: [String: ChatConversation] = [:]
    @Published private(set) var listFailure: ChatFailure?
    @Published private(set) var hasLoaded = false
    /// Where new chats run, as the CLI's configuration says.
    @Published private(set) var config = ChatCLIConfig()
    @Published var selectedID: String?
    @Published var draft = ChatDraft()
    @Published var openPicker: ChatPicker?
    @Published var workspaces: [String] = []
    @Published var settings = ChatSettings.default
    /// The chat whose question goes out again once the person comes back
    /// from logging in.
    @Published private(set) var awaitingLogin: String?
    /// The MCP chip where the person changed it: per chat, and for the next
    /// new chat. Until then a chat follows its record and a new chat the
    /// CLI's `chat.mcp`.
    @Published private(set) var mcpChoices: [String: Bool] = [:]
    @Published private(set) var newChatMCP: Bool?

    private let runner: any ChatCommandRunning
    private let now: () -> Date
    private var tasks: [String: Task<Void, Never>] = [:]
    /// The turn each conversation is on. A turn's process can report its
    /// end after the next turn started; only the current turn may end it.
    private var turns: [String: UUID] = [:]
    private var movedKeys: [String: String] = [:]
    let sessions = ChatSessionPool()
    private var isDemo = false

    init(runner: any ChatCommandRunning, now: @escaping () -> Date = Date.init) {
        self.runner = runner
        self.now = now
    }

    // MARK: - Reading

    /// The chats Chats mode lists: asks about a session stay in their
    /// session's Ask section.
    var visibleChats: [ChatRecord] {
        ChatGrouping.sorted(records.filter { !$0.isAsk })
    }

    func record(_ id: String) -> ChatRecord? {
        records.first { $0.id == id } ?? conversations[id]?.record
    }

    func conversation(_ id: String) -> ChatConversation {
        conversations[id] ?? ChatConversation(record: record(id))
    }

    func isAnswering(_ id: String) -> Bool {
        conversations[id]?.isStreaming == true
    }

    var defaultPlace: ChatPlace { config.defaultPlace(workspaces: workspaces) }

    var defaultHarness: HarnessID {
        settings.harnesses.contains(config.harness) ? config.harness : settings.harnesses[0]
    }

    var draftHarness: HarnessID {
        draft.harness.flatMap { settings.harnesses.contains($0) ? $0 : nil } ?? defaultHarness
    }

    var draftPlace: ChatPlace { draft.place ?? defaultPlace }

    /// What the new chat page would send with right now.
    var draftSpec: ChatSessionSpec {
        ChatSessionSpec(harness: draftHarness, place: draftPlace, mcp: usesMCP(nil))
    }

    func refresh() async {
        guard !isDemo else { return }
        await loadConfig()
        do {
            let output = try await runner.run(ChatCommand.list())
            guard output.exitCode == 0 else {
                listFailure = ChatFailure.fromExit(status: output.exitCode, output: output.stderr + output.stdout)
                hasLoaded = true
                return
            }
            let listed = try ChatListDecoder.decode(Data(output.stdout.utf8))
            let listedIDs = Set(listed.map(\.id))
            let pending = records.filter { $0.id.hasPrefix(Self.pendingPrefix) && !listedIDs.contains($0.id) }
            let updated = listed.map { listedRecord in
                conversations[listedRecord.id]?.isStreaming == true
                    ? (records.first { $0.id == listedRecord.id } ?? listedRecord) : listedRecord
            }
            if updated + pending != records { records = updated + pending }
            listFailure = nil
        } catch {
            listFailure = Self.failure(from: error)
        }
        hasLoaded = true
    }

    func loadConfig() async {
        guard !isDemo, let output = try? await runner.run(ChatCommand.configShow()), output.exitCode == 0,
              let loaded = ChatCLIConfig.fromConfigShow(Data(output.stdout.utf8)) else { return }
        if loaded != config { config = loaded }
    }

    /// Writes Settings → Chats' "Where chats run" through `config set`.
    /// Returns what the CLI said when it refused a change.
    func saveConfig(_ wanted: ChatCLIConfig) async -> String? {
        for arguments in wanted.changes(from: config) {
            guard let output = try? await runner.run(arguments) else {
                await loadConfig()
                return "The devmachine CLI could not run."
            }
            if output.exitCode != 0 {
                await loadConfig()
                let message = (output.stderr.isEmpty ? output.stdout : output.stderr)
                return message.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        await loadConfig()
        return nil
    }

    /// Reads a chat's messages from the CLI's local copy, unless an answer
    /// is streaming into it right now.
    func load(_ id: String) async {
        guard !isDemo, !id.hasPrefix(Self.pendingPrefix), conversations[id]?.isStreaming != true else { return }
        do {
            let output = try await runner.run(ChatCommand.show(id: id))
            guard output.exitCode == 0 else { return }
            let shown = try JSONDecoder().decode(ChatShow.self, from: Data(output.stdout.utf8))
            guard conversations[id]?.isStreaming != true else { return }
            var conversation = conversations[id] ?? ChatConversation()
            conversation.record = shown.record
            conversation.messages = shown.messages
            conversation.failure = shown.messages.last?.error.flatMap { $0.kind == .cancelled ? nil : $0 }
            conversation.wasStopped = shown.messages.last?.error?.kind == .cancelled
            conversations[id] = conversation
        } catch {
            return
        }
    }

    // MARK: - Choosing

    func select(_ id: String?) {
        openPicker = nil
        selectedID = id
        if let id { loadIfNeeded(id) }
    }

    func loadIfNeeded(_ id: String) {
        guard conversations[id] == nil else { return }
        Task { await load(id) }
    }

    func startNewChat(place: ChatPlace? = nil, harness: HarnessID? = nil, text: String = "") {
        selectedID = nil
        openPicker = nil
        draft = ChatDraft(text: text, harness: harness, place: place)
    }

    /// "Choose another workspace": the same question, ready to go anywhere else.
    func askElsewhere(_ id: String) {
        let conversation = conversation(id)
        startNewChat(harness: conversation.record?.harness, text: conversation.lastUserText ?? "")
        openPicker = .workspace
    }

    // MARK: - MCP

    /// Whether the chat (nil: the next new chat) loads MCP servers.
    func usesMCP(_ id: String?) -> Bool {
        guard let id else { return newChatMCP ?? config.mcp }
        let key = current(id)
        return mcpChoices[key] ?? record(key)?.mcp ?? config.mcp
    }

    func setMCP(_ on: Bool, chat id: String?) {
        if let id { mcpChoices[current(id)] = on } else { newChatMCP = on }
    }

    private func mcpFlag(_ key: String) -> Bool? {
        ChatMCP.flag(
            chosen: usesMCP(key), record: key.hasPrefix(Self.pendingPrefix) ? nil : record(key),
            configDefault: config.mcp)
    }

    // MARK: - Sending

    /// Sends from the chat pane: into the selected chat, or a new chat with
    /// the draft's harness and workspace. Returns the key the conversation
    /// is under (a pending one until the CLI names the chat).
    @discardableResult
    func sendFromPane(_ text: String) -> String? {
        if let selectedID, let record = record(selectedID), !selectedID.hasPrefix(Self.pendingPrefix) {
            return send(text, toChat: record.id)
        }
        let key = send(text, harness: draftHarness, place: draftPlace)
        draft.text = ""
        return key
    }

    @discardableResult
    func send(_ text: String, harness: HarnessID, place: ChatPlace, selects: Bool = true) -> String? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let key = Self.pendingPrefix + UUID().uuidString
        let mcp = usesMCP(nil)
        let placeholder = ChatRecord(
            id: key, title: Self.title(of: body), harness: harness,
            workspace: place.workspaceName ?? ChatRecord.localWorkspace, folder: config.folder,
            createdAt: now(), updatedAt: now(), mcp: mcp)
        records.append(placeholder)
        conversations[key] = ChatConversation(record: placeholder)
        mcpChoices[key] = mcp
        newChatMCP = nil
        if selects { selectedID = key }
        openPicker = nil
        let flag = ChatMCP.flag(chosen: mcp, record: nil, configDefault: config.mcp)
        let arguments = ChatCommand.send(chatID: nil, place: place, harness: harness, message: body, mcp: flag)
        let spec = ChatSessionSpec(harness: harness, place: place, mcp: mcp)
        if let warm = sessions.warm, warm.spec == spec, !warm.hasEnded {
            sessions.warm = nil
            turn(through: warm, key: key, text: body, fallback: arguments)
        } else if let live = openSession(ChatCommand.session(chatID: nil, spec: spec, mcp: flag), spec: spec, mcp: mcp) {
            turn(through: live, key: key, text: body, fallback: arguments)
        } else {
            launch(key: key, text: body, arguments: arguments)
        }
        return key
    }

    @discardableResult
    func send(_ text: String, toChat id: String) -> String? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isAnswering(id), let record = record(id) else { return nil }
        if conversations[id] == nil { conversations[id] = ChatConversation(record: record) }
        let isPending = id.hasPrefix(Self.pendingPrefix)
        let arguments = ChatCommand.send(
            chatID: isPending ? nil : id, place: record.place, harness: record.harness, message: body,
            mcp: mcpFlag(id))
        if !isPending, let live = chatSession(id) {
            turn(through: live, key: id, text: body, fallback: arguments)
        } else {
            launch(key: id, text: body, arguments: arguments)
        }
        return id
    }

    /// One Ask turn: the first creates the session's ask chat, later ones
    /// pass it with `--chat`.
    @discardableResult
    func ask(
        _ question: String, key askKey: AskSessionKey, harness: HarnessID, folder: String? = nil, chatID: String?
    ) -> String? {
        let body = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let key = chatID ?? Self.pendingPrefix + UUID().uuidString
        if isAnswering(key) { return nil }
        if conversations[key] == nil {
            let placeholder = ChatRecord(
                id: key, title: Self.title(of: body), harness: harness,
                workspace: askKey.place.workspaceName ?? ChatRecord.localWorkspace, folder: folder ?? "",
                createdAt: now(), updatedAt: now(), kind: ChatRecord.askKind, session: askKey.session)
            conversations[key] = ChatConversation(record: record(key) ?? placeholder)
        }
        let arguments = ChatCommand.ask(
            place: askKey.place, session: askKey.session, folder: folder, harness: harness, chatID: chatID,
            question: body)
        if let live = sessions.asks[askKey], !live.hasEnded, live.turn == nil || live.key == key {
            turn(through: live, key: key, text: body, fallback: arguments)
        } else {
            launch(key: key, text: body, arguments: arguments)
        }
        return key
    }

    /// Try again: the last question goes out once more.
    func retry(_ id: String) {
        var conversation = conversation(id)
        guard let text = conversation.lastUserText, !conversation.isStreaming,
              let index = conversation.messages.lastIndex(where: { $0.role == .user }) else { return }
        conversation.messages.removeSubrange(index...)
        conversation.failure = nil
        conversations[id] = conversation
        guard let record = record(id) else { return }
        let chatID = id.hasPrefix(Self.pendingPrefix) ? nil : id
        let arguments: [String]
        if record.isAsk, let session = record.session {
            arguments = ChatCommand.ask(
                place: record.place, session: session, folder: record.folder, harness: record.harness, chatID: chatID,
                question: text)
        } else {
            arguments = ChatCommand.send(
                chatID: chatID, place: record.place, harness: record.harness, message: text, mcp: mcpFlag(id))
        }
        launch(key: id, text: text, arguments: arguments)
    }

    func awaitLogin(_ id: String) {
        awaitingLogin = current(id)
    }

    func retryAwaitedLogin() {
        guard let id = awaitingLogin else { return }
        awaitingLogin = nil
        retry(id)
    }

    /// Esc: the CLI is told to stop (it kills the harness) and what was
    /// answered so far stays.
    func stop(_ id: String) {
        let key = current(id)
        if turns[key] != nil, let live = session(answering: key) {
            live.channel.write(ChatSessionInput.cancel)
            live.draining += 1
            live.turn = nil
        }
        tasks[key]?.cancel()
        tasks[key] = nil
        turns[key] = nil
        conversations[key]?.stop()
    }

    // MARK: - Changing

    func rename(_ id: String, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = records.firstIndex(where: { $0.id == id }) else { return }
        let output = try? await runner.run(ChatCommand.rename(id: id, title: trimmed))
        guard output?.exitCode == 0 else { return }
        records[index].title = trimmed
        conversations[id]?.record?.title = trimmed
    }

    func delete(_ id: String) async {
        let id = current(id)
        stop(id)
        if !id.hasPrefix(Self.pendingPrefix) {
            let output = try? await runner.run(ChatCommand.delete(id: id))
            guard output?.exitCode == 0 else { return }
        }
        records.removeAll { $0.id == id }
        conversations[id] = nil
        if selectedID == id { selectedID = nil }
    }

    // MARK: - Streaming

    private func launch(key: String, text: String, arguments: [String], begins: Bool = true) {
        if begins { conversations[key, default: ChatConversation(record: record(key))].begin(userText: text, at: now()) }
        let turn = UUID()
        turns[key] = turn
        let runner = self.runner
        let collected = CollectedOutput()
        tasks[key] = Task { [weak self] in
            var status: Int32 = 0
            var thrown: Error?
            do {
                status = try await runner.stream(arguments) { line in
                    if ChatEventDecoder.decode(line) == nil { collected.append(line) }
                    // The main queue runs blocks in the order they were sent,
                    // so the events keep their order; separate tasks would not.
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.receive(line, key: key, turn: turn) }
                    }
                }
            } catch {
                thrown = error
            }
            let output = collected.text
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.finish(key: key, turn: turn, status: status, output: output, error: thrown)
                }
            }
        }
    }

    func receive(_ line: String, key: String, turn: UUID? = nil) {
        guard let event = ChatEventDecoder.decode(line) else { return }
        var key = current(key)
        if let turn, turns[key] != turn { return }
        if case let .started(chat) = event, key != chat.id {
            move(key, to: chat)
            key = chat.id
        }
        conversations[key, default: ChatConversation(record: record(key))].apply(event)
        if case let .done(chat) = event { upsert(chat) }
        if case let .started(chat) = event { upsert(chat) }
    }

    private func finish(key: String, turn: UUID, status: Int32, output: String, error: Error?) {
        let key = current(key)
        guard turns[key] == turn else { return }
        turns[key] = nil
        tasks[key] = nil
        guard conversations[key]?.isStreaming == true else { return }
        if let error, !(error is CancellationError) {
            conversations[key]?.isStreaming = false
            conversations[key]?.failure = Self.failure(from: error)
        } else {
            conversations[key]?.processEnded(status: status, output: output)
        }
    }

    private func move(_ pending: String, to chat: ChatRecord) {
        movedKeys[pending] = chat.id
        if let conversation = conversations.removeValue(forKey: pending) {
            conversations[chat.id] = conversation
        }
        if let task = tasks.removeValue(forKey: pending) { tasks[chat.id] = task }
        if let turn = turns.removeValue(forKey: pending) { turns[chat.id] = turn }
        if let mcp = mcpChoices.removeValue(forKey: pending) { mcpChoices[chat.id] = mcp }
        if let live = sessions.chats.removeValue(forKey: pending) {
            live.key = chat.id
            sessions.chats[chat.id] = live
        }
        for live in sessions.asks.values where live.key == pending { live.key = chat.id }
        records.removeAll { $0.id == pending }
        if selectedID == pending { selectedID = chat.id }
    }

    // MARK: - Sessions

    /// Starts the harness for the next new chat while the person types, so
    /// the first message does not wait for it. Another spec replaces it.
    func prewarm(_ spec: ChatSessionSpec) {
        if let warm = sessions.warm, warm.spec == spec, !warm.hasEnded { return }
        sessions.warm?.channel.close()
        sessions.warm = nil
        let flag = ChatMCP.flag(chosen: spec.mcp, record: nil, configDefault: config.mcp)
        sessions.warm = openSession(ChatCommand.session(chatID: nil, spec: spec, mcp: flag), spec: spec, mcp: spec.mcp)
    }

    /// An open chat keeps a session; the CLI ends it after it idles.
    func warmChat(_ id: String) {
        _ = chatSession(current(id))
    }

    /// The Ask section on screen keeps one `chat ask --serve` for its session.
    func warmAsk(_ askKey: AskSessionKey, harness: HarnessID, folder: String?, chatID: String?) {
        if let live = sessions.asks[askKey], !live.hasEnded { return }
        let arguments = ChatCommand.askServe(
            place: askKey.place, session: askKey.session, folder: folder, harness: harness, chatID: chatID)
        guard let live = openSession(arguments, spec: nil, mcp: false) else { return }
        live.key = chatID
        sessions.asks[askKey] = live
    }

    func closeAsk(_ askKey: AskSessionKey) {
        sessions.asks.removeValue(forKey: askKey)?.channel.close()
    }

    func closeAllSessions() {
        sessions.closeAll()
    }

    private func chatSession(_ id: String) -> ChatSessionPool.Live? {
        guard !id.hasPrefix(Self.pendingPrefix), let record = record(id), !record.isAsk else { return nil }
        let mcp = usesMCP(id)
        if let live = sessions.chats[id], !live.hasEnded {
            if live.mcp == mcp { return live }
            if live.turn == nil || turns[id] == nil {
                live.channel.close()
                sessions.remove(live)
            } else {
                return nil
            }
        }
        let arguments = ChatCommand.session(
            chatID: id, spec: ChatSessionSpec(harness: record.harness, place: record.place, mcp: mcp), mcp: mcpFlag(id))
        guard let live = openSession(arguments, spec: nil, mcp: mcp) else { return nil }
        live.key = id
        sessions.chats[id] = live
        return live
    }

    private func session(answering key: String) -> ChatSessionPool.Live? {
        if let live = sessions.chats[key], live.turn != nil { return live }
        return sessions.asks.values.first { $0.key == key && $0.turn != nil }
    }

    private func openSession(_ arguments: [String], spec: ChatSessionSpec?, mcp: Bool) -> ChatSessionPool.Live? {
        guard !sessions.isUnsupported, !isDemo else { return nil }
        let ref = ChatSessionRef()
        let channel: any ChatSessionChannel
        do {
            channel = try runner.openSession(
                arguments,
                line: { [weak self] line in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { if let live = ref.live { self?.sessionLine(line, live) } }
                    }
                },
                exited: { [weak self] status in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { if let live = ref.live { self?.sessionEnded(live, status: status) } }
                    }
                })
        } catch {
            return nil
        }
        let live = ChatSessionPool.Live(channel: channel, spec: spec, mcp: mcp)
        ref.live = live
        return live
    }

    private func turn(through live: ChatSessionPool.Live, key: String, text: String, fallback: [String]) {
        conversations[key, default: ChatConversation(record: record(key))].begin(userText: text, at: now())
        let turn = UUID()
        turns[key] = turn
        live.key = key
        live.turn = turn
        live.fallback = fallback
        live.output = []
        let isAsk = sessions.asks.values.contains { $0 === live }
        if !isAsk { sessions.chats[key] = live }
        // An ask reads the session's transcript first, and says so itself.
        let ready = isAsk ? nil : Self.thinking(record(key)?.harness ?? live.spec?.harness)
        conversations[key]?.status = live.isReady ? ready : live.status
        live.channel.write(ChatSessionInput.send(text))
    }

    private func sessionLine(_ line: String, _ live: ChatSessionPool.Live) {
        switch ChatSessionLine.decode(line) {
        case nil:
            live.output.append(line)
        case .ready?:
            live.isReady = true
            live.status = nil
        case .closed?:
            live.hasEnded = true
        case let .event(event)?:
            if live.draining > 0 {
                switch event {
                case .done, .error: live.draining -= 1
                default: break
                }
                return
            }
            if case let .status(update) = event, !live.isReady { live.status = update.message }
            guard let key = live.key, let turn = live.turn else { return }
            receive(line, key: key, turn: turn)
            let now = current(key)
            if now != key { live.key = now }
            switch event {
            case .done, .error:
                if turns[now] == turn { turns[now] = nil }
                live.turn = nil
            default:
                break
            }
        }
    }

    /// What a ready session shows until the CLI's own `waiting` arrives.
    static func thinking(_ harness: HarnessID?) -> String? {
        harness.map { "\(ChatHarness.title($0)) is thinking…" }
    }

    /// The process ended. A turn still open fails with what it printed; on a
    /// CLI from before sessions it goes out again with `chat send`.
    private func sessionEnded(_ live: ChatSessionPool.Live, status: Int32) {
        sessions.remove(live)
        let output = live.output.joined(separator: "\n")
        let unsupported = !live.isReady && ChatSessionLine.isUnsupported(output)
        if unsupported { sessions.isUnsupported = true }
        guard let key = live.key.map(current), let turn = live.turn, turns[key] == turn else { return }
        live.turn = nil
        if unsupported, let fallback = live.fallback {
            turns[key] = nil
            launch(key: key, text: "", arguments: fallback, begins: false)
            return
        }
        finish(key: key, turn: turn, status: status, output: output, error: nil)
    }

    /// A key the CLI renamed from pending to the chat's id.
    func current(_ key: String) -> String {
        movedKeys[key] ?? key
    }

    private func upsert(_ chat: ChatRecord) {
        if let index = records.firstIndex(where: { $0.id == chat.id }) {
            if records[index] != chat { records[index] = chat }
        } else {
            records.append(chat)
        }
    }

    static func title(of message: String) -> String {
        let firstLine = message.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? message
        return firstLine.count > titleLength ? String(firstLine.prefix(titleLength)) : firstLine
    }

    static func failure(from error: Error) -> ChatFailure {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if ChatFailure.isOlderCLI(message) { return ChatFailure(kind: .needsNewerCLI, message: message) }
        if case .executableNotFound = error as? DevmachineCLIError {
            return ChatFailure(kind: .other("cli-not-found"), message: message)
        }
        return ChatFailure(kind: .harnessFailed, message: message)
    }

    // MARK: - Demo

    func seedDemo(records: [ChatRecord], conversations: [String: ChatConversation], config: ChatCLIConfig) {
        isDemo = true
        self.config = config
        self.records = records
        self.conversations = conversations
        hasLoaded = true
        listFailure = nil
    }

    func seedDemoConversation(_ id: String, _ conversation: ChatConversation) {
        conversations[id] = conversation
    }
}

private final class CollectedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) { lock.withLock { lines.append(line) } }
    var text: String { lock.withLock { lines.joined(separator: "\n") } }
}
