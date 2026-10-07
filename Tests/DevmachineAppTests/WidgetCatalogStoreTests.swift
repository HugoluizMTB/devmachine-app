import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class WidgetsRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var lastArgs: [String] = []
    let result: (stdout: String, stderr: String, exitCode: Int32)

    init(_ result: (String, String, Int32)) {
        self.result = result
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.withLock { lastArgs = args }
        return result
    }
}

private enum ReadError: LocalizedError {
    case offline
    var errorDescription: String? { "could not fetch packages: offline" }
}

private final class ReadBox: @unchecked Sendable {
    private let lock = NSLock()
    private var next: Result<WidgetCatalog, Error>

    init(_ next: Result<WidgetCatalog, Error>) {
        self.next = next
    }

    func set(_ value: Result<WidgetCatalog, Error>) { lock.withLock { next = value } }
    func read() throws -> WidgetCatalog { try lock.withLock { next }.get() }
}

@MainActor
final class WidgetCatalogStoreTests: XCTestCase {
    private let json = #"{"engine":"1.0","packages_release":"v39","widgets":[],"problems":[]}"#

    func testTheCatalogComesFromWidgetsListInJSON() throws {
        let runner = WidgetsRunner((json, "", 0))
        let cli = DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: runner)
        let catalog = try WidgetCatalog.decode(cli.widgetsList())
        XCTAssertEqual(runner.lastArgs, ["widgets", "list", "--format", "json"])
        XCTAssertEqual(catalog.packagesRelease, "v39")
    }

    func testAnOlderCLISaysItNeedsAnUpdate() {
        let runner = WidgetsRunner(("", "Error: unknown command \"widgets\" for \"devmachine\"", 1))
        let cli = DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: runner)
        XCTAssertThrowsError(try cli.widgetsList()) { error in
            XCTAssertEqual(error as? DevmachineCLIError, .needsNewerCLI("widgets"))
        }
    }

    func testTheCLIPathCanBeOverridden() {
        XCTAssertEqual(DevmachineCLI.overridePath(environment: ["DEVMACHINE_CLI": "/tmp/dm/devmachine"]), "/tmp/dm/devmachine")
        XCTAssertNil(DevmachineCLI.overridePath(environment: ["DEVMACHINE_CLI": ""]))
        XCTAssertNil(DevmachineCLI.overridePath(environment: [:]))
    }

    func testAFailureKeepsTheLastGoodCatalog() async {
        let good = WidgetCatalog(engine: "1.0", packagesRelease: "v39", widgets: [])
        let box = ReadBox(.success(good))
        let store = WidgetCatalogStore(read: { try box.read() })
        await store.reload()
        XCTAssertEqual(store.catalog, good)
        XCTAssertEqual(store.state, .loaded)
        box.set(.failure(ReadError.offline))
        await store.reload()
        XCTAssertEqual(store.catalog?.widgets, good.widgets)
        XCTAssertEqual(store.catalog?.isStale, true)
        XCTAssertEqual(store.state, .failed("could not fetch packages: offline"))
        box.set(.success(good))
        await store.reload()
        XCTAssertEqual(store.catalog, good)
        XCTAssertEqual(store.catalog?.isStale, false)
    }

    func testAFirstFailureLeavesNoCatalog() async {
        let store = WidgetCatalogStore(read: { throw ReadError.offline })
        await store.reload()
        XCTAssertNil(store.catalog)
        XCTAssertEqual(store.state, .failed("could not fetch packages: offline"))
    }

    func testAPinnedCatalogNeverReadsTheCLI() async {
        let pinned = WidgetCatalog(engine: "1.0", packagesRelease: "v39", widgets: [])
        let box = ReadBox(.success(WidgetCatalog(engine: "1.0", packagesRelease: "v40", widgets: [])))
        let store = WidgetCatalogStore(read: { try box.read() })
        store.pin(pinned)
        await store.reload()
        XCTAssertEqual(store.catalog, pinned)
        XCTAssertEqual(store.state, .loaded)
    }

    func testHomeAndBothSidebarsStartingTogetherReadTheCatalogOnce() async {
        let reads = ReadCounter()
        let store = WidgetCatalogStore(read: {
            reads.increment()
            return WidgetCatalog(engine: "1.2", packagesRelease: "v39", widgets: [])
        })
        store.reloadIfIdle()
        XCTAssertEqual(store.state, .loading)
        store.reloadIfIdle()
        store.reloadIfIdle()
        await waitUntil { store.state == .loaded }
        store.reloadIfIdle()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(reads.value, 1)
    }

    func testAPinnedCatalogIsNeverReloadedWhenIdle() async {
        let reads = ReadCounter()
        let store = WidgetCatalogStore(read: {
            reads.increment()
            return WidgetCatalog(engine: "1.2", packagesRelease: "v39", widgets: [])
        })
        store.pin(WidgetCatalog(engine: "1.2", packagesRelease: "v38", widgets: []))
        store.reloadIfIdle()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(reads.value, 0)
    }
}
