import XCTest
@testable import DevmachineApp
@testable import DevmachineCore

@MainActor
final class WidgetEditApprovalTests: XCTestCase {
    private var root: URL!
    private var command: ScriptedSourceRunner!
    private var launcher: AppFakeLauncher!
    private var controller: HomeBoardController!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetEditApprovalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("config/boards"), withIntermediateDirectories: true)
        try Data("""
            format: 1
            surface: home
            widgets:
              - id: disk
                title: Disk
                source: {kind: command, run: df, every: 60s}
                view: {kind: text}
                frame: {x: 24, y: 24, w: 320, h: 160}
                size: medium
                minimized: false
                z: 1
              - id: ask
                title: Go news
                source: {kind: prompt, harness: claude, permission_mode: plan, prompt: Search the web.}
                view: {kind: markdown}
                frame: {x: 368, y: 24, w: 320, h: 320}
                size: large
                minimized: false
                z: 2

            """.utf8).write(to: root.appendingPathComponent("config/boards/home.yml"))
        command = ScriptedSourceRunner()
        launcher = AppFakeLauncher()
        let environment = SourceRunEnvironment(
            cli: { CLIInvocationContext(executable: "/opt/homebrew/bin/devmachine", environment: [:]) },
            localEnvironment: [:], home: "/Users/alice", isExecutable: { _ in true })
        let sources = WidgetSourceController(
            runners: SourceRunners(command: command, url: command, prompt: command, session: command, launcher: launcher, environment: environment),
            approvalsFile: WidgetApprovalsFile(fileURL: root.appendingPathComponent("approvals.json")),
            historyStore: SparklineHistoryStore(directory: root.appendingPathComponent("history")), surface: "home",
            isDemo: false, startsTimer: false)
        let catalog = WidgetCatalog(engine: "1.5", packagesRelease: "r", widgets: [])
        let store = WidgetCatalogStore(read: { catalog })
        store.seed(catalog)
        controller = HomeBoardController(
            placementsFile: WidgetPlacementsFile(fileURL: root.appendingPathComponent("widget-placements.json")),
            catalog: store, configPath: { nil }, sources: sources)
        controller.open(configDirectory: root.appendingPathComponent("config").path)
    }

    override func tearDown() async throws {
        controller.sources.stop()
        command.release()
        launcher.releaseAll()
        try? FileManager.default.removeItem(at: root)
    }

    private func sync() {
        controller.sources.update(controller.sourceEntries(isOnScreen: { _ in true }))
    }

    private func allow(_ id: String) async throws {
        sync()
        guard case let .waiting(hash) = controller.sources.approvalState(id) else { return XCTFail("expected waiting") }
        controller.sources.approve(id, hash: hash)
        await waitUntil { self.controller.sources.approvalState(id) == .allowed }
    }

    private func allowDisk() async throws { try await allow("disk") }

    private func edit(_ id: String, _ change: (inout InlineWidgetForm) -> Void) throws {
        let old = try XCTUnwrap(controller.editableEntry(id)?.inline)
        var form = try XCTUnwrap(InlineWidgetForm(inline: old, surface: "home"))
        change(&form)
        XCTAssertTrue(controller.apply(.inline(try form.read(surface: "home", id: id, keeping: old).get()), to: id))
        sync()
    }

    private func edit(_ change: (inout InlineWidgetForm) -> Void) throws { try edit("disk", change) }

    func testChangingTheCommandAsksAgain() async throws {
        try await allowDisk()
        try edit { $0.run = "du" }
        guard case .waiting = controller.sources.approvalState("disk") else { return XCTFail("expected waiting again") }
    }

    func testChangingTheTitleKeepsTheDecision() async throws {
        try await allowDisk()
        try edit { $0.title = "Disk use" }
        XCTAssertEqual(controller.sources.approvalState("disk"), .allowed)
    }

    func testChangingEveryKeepsTheDecision() async throws {
        try await allowDisk()
        try edit { $0.every = "10m" }
        XCTAssertEqual(controller.sources.approvalState("disk"), .allowed)
    }

    func testChangingTheTargetAsksAgain() async throws {
        try await allowDisk()
        try edit { $0.target = .machine("main") }
        guard case .waiting = controller.sources.approvalState("disk") else { return XCTFail("expected waiting again") }
    }

    func testChangingThePermissionModeAsksAgain() async throws {
        try await allow("ask")
        try edit("ask") { $0.choosePermissionMode("auto") }
        guard case .waiting = controller.sources.approvalState("ask") else { return XCTFail("expected waiting again") }
        try await allow("ask")
        try edit("ask") { $0.choosePermissionMode("bypassPermissions") }
        guard case .waiting = controller.sources.approvalState("ask") else { return XCTFail("expected waiting again") }
        try await allow("ask")
        try edit("ask") { $0.choosePermissionMode("") }
        guard case .waiting = controller.sources.approvalState("ask") else { return XCTFail("expected waiting again") }
    }

    func testChangingOnlyThePromptsTitleKeepsTheDecision() async throws {
        try await allow("ask")
        try edit("ask") { $0.title = "Go releases" }
        XCTAssertEqual(controller.sources.approvalState("ask"), .allowed)
    }
}
