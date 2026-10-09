import XCTest
import DevmachineCore
@testable import DevmachineApp

final class SessionChatStoreTests: XCTestCase {
    private let record = SessionShareRecord(
        id: "wvx3januvgyj", workspace: "acme", alias: "acme-devmachine", session: "main", name: "main",
        mode: .read, url: "https://share-acme.example.com/s/wvx3januvgyj/",
        createdAt: Date(timeIntervalSince1970: 1_800_000_000), expiresAt: Date(timeIntervalSince1970: 1_900_000_000))

    private static func line(_ id: String, from: String, role: String, text: String) -> String {
        #"{"message":{"from":"\#(from)","id":"\#(id)","role":"\#(role)","text":"\#(text)","ts":"2026-10-08T23:31:05Z"},"version":1}"#
    }

    @MainActor
    func testFollowedMessagesArriveAndCountAsUnreadUntilSeen() async {
        let streamer = FakeChatStreamer(lines: [
            "Warning: noise from ssh",
            Self.line("a1", from: "bob", role: "guest", text: "hi"),
            Self.line("a2", from: "alice", role: "owner", text: "hello"),
            Self.line("a1", from: "bob", role: "guest", text: "hi"),
        ])
        let store = SessionChatStore(streamer: streamer, runner: FakeSessionShareRunner([]))
        store.follow(record)
        await waitUntil { store.messages[self.record.id]?.count == 2 }

        XCTAssertEqual(store.messages[record.id]?.map(\.text), ["hi", "hello"])
        XCTAssertEqual(store.unread[record.id], 1)
        XCTAssertEqual(streamer.calls.first, SessionShareCommand.chatFollowArguments(workspace: "acme", id: record.id))
        store.markRead(record.id)
        XCTAssertNil(store.unread[record.id])
        store.receive(SessionChatMessage(id: "a3", ts: Date(), from: "bob", role: "guest", text: "seen"), share: record.id)
        XCTAssertNil(store.unread[record.id])
        store.track([])
    }

    @MainActor
    func testSendUsesMessageSoAnyTextGetsThrough() async {
        let runner = FakeSessionShareRunner([CLIOutput(stdout: "{}", stderr: "", exitCode: 0)])
        let store = SessionChatStore(streamer: FakeChatStreamer(lines: []), runner: runner)

        let sent = await store.send("  -rf / is just text  ", to: record)

        XCTAssertTrue(sent)
        XCTAssertEqual(runner.calls, [SessionShareCommand.chatSendArguments(workspace: "acme", id: record.id, text: "-rf / is just text")])
        let empty = await store.send("   ", to: record)
        XCTAssertFalse(empty)
        XCTAssertEqual(runner.calls.count, 1)
    }

    @MainActor
    func testASentMessageShowsAtOnceAndTheEchoReplacesIt() async {
        let runner = FakeSessionShareRunner([CLIOutput(stdout: "{}", stderr: "", exitCode: 0)])
        let store = SessionChatStore(streamer: FakeChatStreamer(lines: []), runner: runner)

        _ = await store.send("on my way", to: record)
        XCTAssertEqual(store.messages[record.id]?.map(\.text), ["on my way"])
        XCTAssertTrue(SessionChatStore.isPending(store.messages[record.id]![0]))

        store.receive(SessionChatMessage(id: "a9", ts: Date(), from: "alice", role: "owner", text: "on my way"), share: record.id)
        XCTAssertEqual(store.messages[record.id]?.map(\.id), ["a9"])
    }

    @MainActor
    func testAnOldPackageIsNamedWhenSendingFails() async {
        let refused = "error: session-share does not accept \"chat\". It accepts start, stop"
        let store = SessionChatStore(
            streamer: FakeChatStreamer(lines: []),
            runner: FakeSessionShareRunner([CLIOutput(stdout: "", stderr: refused, exitCode: 1)]))

        let sent = await store.send("hi", to: record)

        XCTAssertFalse(sent)
        XCTAssertTrue(store.failure[record.id]?.contains("packages v49") ?? false)
        XCTAssertEqual(store.messages[record.id] ?? [], [], "a failed message must not stay as sending")
    }

    @MainActor
    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

final class FakeChatStreamer: SessionChatStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private let lines: [String]
    private var recorded: [[String]] = []

    init(lines: [String]) {
        self.lines = lines
    }

    var calls: [[String]] { lock.withLock { recorded } }

    func stream(_ arguments: [String], line: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        lock.withLock { recorded.append(arguments) }
        for l in lines { line(l) }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return 0
    }
}
