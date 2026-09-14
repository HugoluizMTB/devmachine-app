import XCTest
import Combine
import DevmachineCore
@testable import DevmachineApp

private final class ScriptedRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var outputs: [String]
    private(set) var calls = 0

    init(outputs: [String]) {
        self.outputs = outputs
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        return outputs.count > 1 ? outputs.removeFirst() : (outputs.first ?? "")
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

private final class CountingRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var callsByAlias: [String: Int] = [:]

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        guard let alias = args.first else { return "" }
        lock.lock()
        callsByAlias[alias, default: 0] += 1
        lock.unlock()
        return "dash|1\n@@PANES@@\ndash|claude"
    }

    func calls(for alias: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return callsByAlias[alias] ?? 0
    }
}

@MainActor
private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail("condition never became true")
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    func testRefreshAllChamaCadaAliasUmaVez() async throws {
        let runner = CountingRunner()
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [
            Workspace(name: "acme", alias: "acme-devmachine"),
            Workspace(name: "beta", alias: "beta-devmachine")
        ]

        model.refreshAll()

        try await waitUntil { runner.calls(for: "acme-devmachine") == 1 && runner.calls(for: "beta-devmachine") == 1 }

        XCTAssertEqual(runner.calls(for: "acme-devmachine"), 1)
        XCTAssertEqual(runner.calls(for: "beta-devmachine"), 1)
    }

    func testSelecionarSessaoAgendaPollSoDoAliasSelecionado() {
        let runner = CountingRunner()
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [
            Workspace(name: "acme", alias: "acme-devmachine"),
            Workspace(name: "beta", alias: "beta-devmachine")
        ]
        model.sessionsByAlias = [
            "acme-devmachine": [TmuxSession(name: "dash", windows: 1, hasClaude: true)]
        ]

        model.clickSession(SessionRef(alias: "acme-devmachine", name: "dash"))

        XCTAssertTrue(model.hasSelectionPollTimer)
        XCTAssertEqual(model.selectionPollTarget, "acme-devmachine")
    }

    func testTrocarSelecaoRetargeteiaOPoll() {
        let runner = CountingRunner()
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [
            Workspace(name: "acme", alias: "acme-devmachine"),
            Workspace(name: "beta", alias: "beta-devmachine")
        ]
        model.sessionsByAlias = [
            "acme-devmachine": [TmuxSession(name: "dash", windows: 1, hasClaude: true)],
            "beta-devmachine": [TmuxSession(name: "web", windows: 1, hasClaude: true)]
        ]

        model.clickSession(SessionRef(alias: "acme-devmachine", name: "dash"))
        XCTAssertEqual(model.selectionPollTarget, "acme-devmachine")

        model.clickSession(SessionRef(alias: "beta-devmachine", name: "web"))
        XCTAssertEqual(model.selectionPollTarget, "beta-devmachine")
    }

    func testSelecaoIniciaEHomeParaOPoll() {
        let runner = CountingRunner()
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]
        model.sessionsByAlias = [
            "acme-devmachine": [TmuxSession(name: "dash", windows: 1, hasClaude: true)]
        ]

        model.clickSession(SessionRef(alias: "acme-devmachine", name: "dash"))
        XCTAssertTrue(model.hasSelectionPollTimer)
        XCTAssertEqual(model.selectionPollTarget, "acme-devmachine")

        model.goHome()

        XCTAssertFalse(model.hasSelectionPollTimer)
        XCTAssertNil(model.selectionPollTarget)
    }

    func testOpsShellPaletteItemShowsTheConfiguredHostAlias() {
        let model = AppModel(store: SessionStore(runner: CountingRunner()))
        model.settings = AppSettings(
            opsRepoPath: "/Users/alice/dev/ops",
            hostAlias: "myhost",
            publicIP: "203.0.113.10",
            baseDomain: "example.com"
        )

        XCTAssertEqual(model.paletteItems().last?.subtitle, "myhost")
    }

    func testPollWithSameResultDoesNotRepublish() async throws {
        let runner = ScriptedRunner(outputs: ["dash|1\n@@PANES@@\ndash|claude"])
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]

        model.refresh(alias: "acme-devmachine")
        try await waitUntil { model.sessionsByAlias["acme-devmachine"] != nil }

        let changes = ChangeCounter()
        let token = model.objectWillChange.sink { _ in changes.bump() }
        defer { token.cancel() }

        model.refresh(alias: "acme-devmachine")
        try await waitUntil { runner.callCount == 2 }
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(model.sessionsByAlias["acme-devmachine"]?.count, 1)
        XCTAssertEqual(changes.count, 0)
    }

    func testPollWithNewResultRepublishes() async throws {
        let runner = ScriptedRunner(outputs: [
            "dash|1\n@@PANES@@\ndash|claude",
            "dash|1\nweb|2\n@@PANES@@\ndash|claude"
        ])
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]

        model.refresh(alias: "acme-devmachine")
        try await waitUntil { model.sessionsByAlias["acme-devmachine"]?.count == 1 }

        let changes = ChangeCounter()
        let token = model.objectWillChange.sink { _ in changes.bump() }
        defer { token.cancel() }

        model.refresh(alias: "acme-devmachine")
        try await waitUntil { model.sessionsByAlias["acme-devmachine"]?.count == 2 }

        XCTAssertEqual(changes.count, 1)
    }

    func testRefreshSkipsTickWhileTheSameAliasIsInFlight() async throws {
        let runner = BlockingRunner(output: "dash|1\n@@PANES@@\ndash|claude")
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]

        model.refresh(alias: "acme-devmachine")
        try await waitUntil { runner.callCount == 1 }

        model.refresh(alias: "acme-devmachine")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(runner.callCount, 1)

        runner.release()
        try await waitUntil { model.sessionsByAlias["acme-devmachine"] != nil }

        model.refresh(alias: "acme-devmachine")
        runner.release()
        try await waitUntil { runner.callCount == 2 }
    }

    func testRefreshOfAnotherAliasIsNotBlocked() async throws {
        let runner = BlockingRunner(output: "dash|1\n@@PANES@@\ndash|claude")
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [
            Workspace(name: "acme", alias: "acme-devmachine"),
            Workspace(name: "beta", alias: "beta-devmachine")
        ]

        model.refresh(alias: "acme-devmachine")
        model.refresh(alias: "beta-devmachine")

        try await waitUntil { runner.callCount == 2 }
        runner.release()
        runner.release()
    }

    func testOfflineAliasStaysOfflineWithoutRepublishing() async throws {
        let runner = ThrowingRunner()
        let model = AppModel(store: SessionStore(runner: runner))
        model.workspaces = [Workspace(name: "acme", alias: "acme-devmachine")]

        model.refresh(alias: "acme-devmachine")
        try await waitUntil { model.offlineAliases.contains("acme-devmachine") }

        let changes = ChangeCounter()
        let token = model.objectWillChange.sink { _ in changes.bump() }
        defer { token.cancel() }

        model.refresh(alias: "acme-devmachine")
        try await waitUntil { runner.callCount == 2 }
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(changes.count, 0)
    }
}

private final class ThrowingRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        lock.lock()
        calls += 1
        lock.unlock()
        throw NSError(domain: "test", code: 1)
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}
