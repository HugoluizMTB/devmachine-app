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
}
