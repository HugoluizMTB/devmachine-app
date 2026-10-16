import XCTest
import DevmachineCore
@testable import DevmachineApp

/// `DEVMACHINE_CHAT_E2E=<devmachine binary>` runs a real chat on this Mac
/// with the local claude, in a configuration folder of its own. Skipped
/// otherwise: it uses the person's own claude login.
@MainActor
final class ChatCLILiveTests: XCTestCase {
    func testARealChatOnThisMac() async throws {
        guard let binary = ProcessInfo.processInfo.environment["DEVMACHINE_CHAT_E2E"], !binary.isEmpty else {
            throw XCTSkip("set DEVMACHINE_CHAT_E2E to a devmachine binary")
        }
        let config = FileManager.default.temporaryDirectory.appendingPathComponent("chat-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: config) }
        var environment = ProcessInfo.processInfo.environment
        environment["DEVMACHINE_CONFIG"] = config.path
        let processEnvironment = environment
        let store = ChatStore(runner: ProcessChatCommandRunner(cli: {
            DevmachineCLI(executable: binary, processEnvironment: processEnvironment)
        }))
        await store.refresh()
        XCTAssertNil(store.listFailure)
        XCTAssertEqual(store.defaultPlace, .local)

        let key = try XCTUnwrap(store.send("Reply with exactly: pong", harness: .claude, place: .local))
        await waitForChat(180) { !store.isAnswering(store.current(key)) && store.current(key) != key }
        let id = store.current(key)
        XCTAssertTrue(id.hasPrefix("c_"), id)
        XCTAssertNil(store.conversation(id).failure)
        XCTAssertTrue(store.conversation(id).messages.last?.text.lowercased().contains("pong") == true)

        store.send("Now reply with exactly: ping", toChat: id)
        await waitForChat(180) { !store.isAnswering(id) }
        XCTAssertNil(store.conversation(id).failure)
        XCTAssertTrue(store.conversation(id).messages.last?.text.lowercased().contains("ping") == true)

        let fresh = ChatStore(runner: ProcessChatCommandRunner(cli: {
            DevmachineCLI(executable: binary, processEnvironment: processEnvironment)
        }))
        await fresh.refresh()
        XCTAssertEqual(fresh.visibleChats.map(\.id), [id])
        await fresh.load(id)
        XCTAssertEqual(fresh.conversation(id).messages.map(\.role), [.user, .assistant, .user, .assistant])

        await fresh.rename(id, to: "Ping pong")
        await fresh.refresh()
        XCTAssertEqual(fresh.visibleChats.first?.title, "Ping pong")
        await fresh.delete(id)
        await fresh.refresh()
        XCTAssertTrue(fresh.visibleChats.isEmpty)
    }

    /// Warm session, two messages, then `chat ask --serve` on a throwaway
    /// folder whose claude transcript the test writes first. Prints what the
    /// stores saw.
    func testWarmSessionsAndAskServeOnThisMac() async throws {
        guard let binary = ProcessInfo.processInfo.environment["DEVMACHINE_CHAT_E2E"], !binary.isEmpty else {
            throw XCTSkip("set DEVMACHINE_CHAT_E2E to a devmachine binary")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chat-e2e-\(UUID().uuidString)")
        let config = root.appendingPathComponent("config")
        let folder = root.appendingPathComponent("chats")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var environment = ProcessInfo.processInfo.environment
        environment["DEVMACHINE_CONFIG"] = config.path
        let processEnvironment = environment
        let runner = ProcessChatCommandRunner(cli: {
            DevmachineCLI(executable: binary, processEnvironment: processEnvironment)
        })
        try "machines:\n  - name: laptop\n    self: true\n".write(
            to: config.appendingPathComponent("config.yml"), atomically: true, encoding: .utf8)
        let set = try await runner.run(["config", "set", "chat.folder", folder.path])
        XCTAssertEqual(set.exitCode, 0, set.stderr)
        let store = ChatStore(runner: runner)
        await store.refresh()
        XCTAssertEqual(store.config.folder, folder.path)
        var seen: [String] = []
        func note(_ text: String) {
            seen.append(text)
            print("E2E", text)
        }

        let started = Date()
        store.prewarm(ChatSessionSpec(harness: .claude, place: .local, mcp: false))
        await waitForChat(60) { store.sessions.warm?.isReady == true }
        note(String(format: "ready after %.1fs", Date().timeIntervalSince(started)))
        XCTAssertEqual(store.sessions.warm?.isReady, true)

        for (index, word) in ["pong", "ping"].enumerated() {
            let sent = Date()
            let key: String
            if index == 0 {
                key = try XCTUnwrap(store.send("Reply with exactly: \(word)", harness: .claude, place: .local))
            } else {
                key = try XCTUnwrap(store.send("Now reply with exactly: \(word)", toChat: store.selectedID ?? ""))
            }
            var statuses: [String] = []
            var firstWord: TimeInterval?
            let deadline = Date().addingTimeInterval(180)
            while Date() < deadline {
                let conversation = store.conversation(store.current(key))
                if let status = conversation.status, statuses.last != status { statuses.append(status) }
                if firstWord == nil, conversation.messages.last?.role == .assistant,
                   !(conversation.messages.last?.text.isEmpty ?? true) {
                    firstWord = Date().timeIntervalSince(sent)
                }
                if !conversation.isStreaming, store.current(key) != key || index > 0 { break }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            let id = store.current(key)
            let conversation = store.conversation(id)
            note("message \(index + 1): statuses \(statuses), first word \(firstWord.map { String(format: "%.1fs", $0) } ?? "none"), "
                + "answer \(conversation.messages.last?.text ?? ""), failure \(conversation.failure?.message ?? "none")")
            XCTAssertNil(conversation.failure)
            XCTAssertTrue(conversation.messages.last?.text.lowercased().contains(word) == true)
            store.selectedID = id
        }
        XCTAssertFalse(store.sessions.isUnsupported)
        note("sessions open for chats: \(store.sessions.chats.count)")

        let ask = Process()
        ask.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        ask.arguments = ["claude", "-p", "Remember the code word kiwi. Reply with: ok"]
        ask.currentDirectoryURL = folder
        ask.standardOutput = FileHandle.nullDevice
        try ask.run()
        ask.waitUntilExit()

        let askKey = AskSessionKey(place: .local, session: "e2e-throwaway")
        let asked = Date()
        store.warmAsk(askKey, harness: .claude, folder: folder.path, chatID: nil)
        await waitForChat(60) { store.sessions.asks[askKey]?.isReady == true }
        note(String(format: "ask ready after %.1fs", Date().timeIntervalSince(asked)))
        for (index, question) in ["What was the code word? One word.", "Spell it backwards. One word."].enumerated() {
            let sent = Date()
            let chatID = store.records.first { $0.isAsk }?.id
            let key = try XCTUnwrap(store.ask(question, key: askKey, harness: .claude, folder: folder.path, chatID: chatID))
            var statuses: [String] = []
            await waitForChat(180) {
                if let status = store.conversation(store.current(key)).status, statuses.last != status {
                    statuses.append(status)
                }
                return !store.isAnswering(store.current(key)) && (index > 0 || store.current(key) != key)
            }
            let conversation = store.conversation(store.current(key))
            note(String(format: "ask %d after %.1fs: statuses %@, answer %@, failure %@", index + 1,
                        Date().timeIntervalSince(sent), statuses.description,
                        conversation.messages.last?.text ?? "", conversation.failure?.message ?? "none"))
            XCTAssertNil(conversation.failure)
        }
        XCTAssertTrue(store.conversation(store.records.first { $0.isAsk }?.id ?? "").messages.last?.text
            .lowercased().contains("iwik") == true)
        store.closeAllSessions()
        print("E2E summary", seen)
    }
}
