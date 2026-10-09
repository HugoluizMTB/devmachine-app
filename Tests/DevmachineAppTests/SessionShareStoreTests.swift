import XCTest
import DevmachineCore
@testable import DevmachineApp

final class SessionShareStoreTests: XCTestCase {
    private static func shareJSON(id: String = "wvx3januvgyj", mode: String = "read", active: Bool = true, ended: String? = nil) -> String {
        let end = ended.map { #", "ended_at": "2026-10-08T20:30:00Z", "end_reason": "\#($0)""# } ?? ""
        return #"{"id": "\#(id)", "session": "main", "mode": "\#(mode)", "created_at": "2026-10-08T20:00:00Z", "expires_at": "2030-01-01T00:00:00Z", "active": \#(active), "url": "https://share.example.com/s/\#(id)/", "max_viewers": 1, "ssh_guests": [], "viewers": []\#(end)}"#
    }

    private let request = SessionShareRequest(alias: "acme-devmachine", workspace: "acme", session: "main")
    private var historyURL: URL!

    override func setUp() {
        historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-store-\(UUID().uuidString)/shares.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: historyURL.deletingLastPathComponent())
    }

    @MainActor
    private func store(_ outputs: [CLIOutput]) -> (SessionShareStore, FakeSessionShareRunner) {
        let runner = FakeSessionShareRunner(outputs)
        let store = SessionShareStore(runner: runner, history: SessionShareHistory(fileURL: historyURL))
        store.isPaused = { _ in false }
        return (store, runner)
    }

    @MainActor
    func testStartRecordsTheShareAndShowsThePassword() async {
        let started = #"{"version": 1, "password": "v3bd-28s5-nave-dvcg", "share": \#(Self.shareJSON(mode: "write"))}"#
        let (store, runner) = store([CLIOutput(stdout: started, stderr: "", exitCode: 0)])

        await store.start(request, name: "Pairing", mode: .write, duration: .twoHours)

        XCTAssertEqual(runner.calls, [SessionShareCommand.startArguments(
            workspace: "acme", session: "main", mode: .write, duration: .twoHours, name: "Pairing")])
        guard case let .started(record, password) = store.outcome?.result else {
            return XCTFail("outcome = \(String(describing: store.outcome))")
        }
        XCTAssertEqual(password, "v3bd-28s5-nave-dvcg")
        XCTAssertEqual(record.alias, "acme-devmachine")
        XCTAssertEqual(store.liveShare(alias: "acme-devmachine", session: "main")?.id, "wvx3januvgyj")
        XCTAssertNil(store.liveShare(alias: "acme-devmachine", session: "other"))
        XCTAssertEqual(SessionShareHistory(fileURL: historyURL).load().map(\.id), ["wvx3januvgyj"])
    }

    @MainActor
    func testAWorkspaceWithoutThePackageIsToldWhatToAdd() async {
        let refused = "error: session-share is not installed on main or workspace acme. Add it with `devmachine packages add session-share`"
        let (store, _) = store([CLIOutput(stdout: "", stderr: refused, exitCode: 1)])

        await store.start(request, name: "", mode: .read, duration: .oneHour)

        guard case let .failed(state) = store.outcome?.result else {
            return XCTFail("outcome = \(String(describing: store.outcome))")
        }
        XCTAssertEqual(state.title, "Couldn't share main")
        XCTAssertTrue(state.cause?.contains("Settings → Packages") ?? false)
        XCTAssertEqual(state.details, refused)
        XCTAssertTrue(store.records.isEmpty)
    }

    @MainActor
    func testTheSameFailureTwiceIsANewOutcome() async {
        let refused = CLIOutput(stdout: "", stderr: "session-share: no such tmux session \"main\"", exitCode: 1)
        let (store, _) = store([refused, refused])
        await store.start(request, name: "", mode: .read, duration: .oneHour)
        let first = store.outcome
        await store.start(request, name: "", mode: .read, duration: .oneHour)
        XCTAssertEqual(first?.result, store.outcome?.result)
        XCTAssertNotEqual(first?.id, store.outcome?.id)
    }

    @MainActor
    func testStopTakesTheToolsAnswer() async {
        let started = #"{"version": 1, "password": "p", "share": \#(Self.shareJSON())}"#
        let stopped = #"{"version": 1, "share": \#(Self.shareJSON(active: false, ended: "revoked"))}"#
        let (store, runner) = store([
            CLIOutput(stdout: started, stderr: "", exitCode: 0),
            CLIOutput(stdout: stopped, stderr: "", exitCode: 0),
        ])
        await store.start(request, name: "", mode: .read, duration: .oneHour)
        guard let record = store.liveShare(alias: "acme-devmachine", session: "main") else { return XCTFail("no share") }

        await store.stop(record)

        XCTAssertEqual(runner.calls.last, SessionShareCommand.stopArguments(workspace: "acme", id: "wvx3januvgyj"))
        XCTAssertNil(store.liveShare(alias: "acme-devmachine", session: "main"))
        XCTAssertEqual(store.records.first?.endReason, "revoked")
    }

    @MainActor
    func testRefreshReadsOnlyWorkspacesWithALiveShareAndSkipsPausedOnes() async {
        let started = #"{"version": 1, "password": "p", "share": \#(Self.shareJSON())}"#
        let listed = #"{"version": 1, "shares": [\#(Self.shareJSON(active: false, ended: "expired"))]}"#
        let (store, runner) = store([
            CLIOutput(stdout: started, stderr: "", exitCode: 0),
            CLIOutput(stdout: listed, stderr: "", exitCode: 0),
        ])
        await store.start(request, name: "", mode: .read, duration: .oneHour)

        store.isPaused = { _ in true }
        await store.refresh()
        XCTAssertEqual(runner.calls.count, 1)

        store.isPaused = { _ in false }
        await store.refresh()
        XCTAssertEqual(runner.calls.last, SessionShareCommand.listArguments(workspace: "acme"))
        XCTAssertEqual(store.records.first?.endReason, "expired")

        await store.refresh()
        XCTAssertEqual(runner.calls.count, 2)
    }

    @MainActor
    func testClearEndedKeepsLiveShares() async {
        let started = #"{"version": 1, "password": "p", "share": \#(Self.shareJSON())}"#
        let (store, _) = store([CLIOutput(stdout: started, stderr: "", exitCode: 0)])
        await store.start(request, name: "", mode: .read, duration: .oneHour)
        try? SessionShareHistory(fileURL: historyURL).save(store.records + [SessionShareRecord(
            id: "abcdefghijkl", workspace: "acme", alias: "acme-devmachine", session: "old", name: "old", mode: .read,
            url: nil, createdAt: Date(timeIntervalSince1970: 0), expiresAt: Date(timeIntervalSince1970: 60))])
        let reloaded = SessionShareStore(runner: FakeSessionShareRunner([]), history: SessionShareHistory(fileURL: historyURL))

        reloaded.clearEnded()

        XCTAssertEqual(reloaded.records.map(\.id), ["wvx3januvgyj"])
    }
}

final class FakeSessionShareRunner: SessionShareRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var outputs: [CLIOutput]
    private var recorded: [[String]] = []

    init(_ outputs: [CLIOutput]) {
        self.outputs = outputs
    }

    var calls: [[String]] {
        lock.withLock { recorded }
    }

    func run(_ arguments: [String]) async throws -> CLIOutput {
        lock.withLock {
            recorded.append(arguments)
            guard !outputs.isEmpty else { return CLIOutput(stdout: "", stderr: "no more answers", exitCode: 1) }
            return outputs.removeFirst()
        }
    }
}
