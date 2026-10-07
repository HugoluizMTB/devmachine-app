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

private final class HeldSleeps: @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [TimeInterval] = []
    private var held: [CheckedContinuation<Void, Never>] = []

    var delays: [TimeInterval] { lock.withLock { asked } }
    var waiting: Int { lock.withLock { held.count } }

    func sleep(_ delay: TimeInterval) async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                asked.append(delay)
                held.append(continuation)
            }
        }
    }

    func releaseNext() {
        let next: CheckedContinuation<Void, Never>? = lock.withLock { held.isEmpty ? nil : held.removeFirst() }
        next?.resume()
    }

    func releaseAll() {
        let all: [CheckedContinuation<Void, Never>] = lock.withLock {
            defer { held.removeAll() }
            return held
        }
        all.forEach { $0.resume() }
    }
}

@MainActor
final class WidgetCatalogStoreTests: XCTestCase {
    private var sleeps = HeldSleeps()

    override func tearDown() async throws {
        sleeps.releaseAll()
    }

    private func retryingStore(_ box: ReadBox, reads: ReadCounter = ReadCounter()) -> WidgetCatalogStore {
        let sleeps = self.sleeps
        return WidgetCatalogStore(
            read: {
                reads.increment()
                return try box.read()
            },
            sleep: { await sleeps.sleep($0) })
    }

    func testAStaleCatalogIsReadAgainOnTheBackoffUntilAReadWorks() async {
        let good = WidgetCatalog(engine: "1.3", packagesRelease: "v41", widgets: [])
        let box = ReadBox(.success(good))
        let store = retryingStore(box)
        await store.reload()
        XCTAssertEqual(sleeps.delays, [])
        box.set(.failure(ReadError.offline))
        await store.reload()
        for expected in [[30], [30, 60], [30, 60, 120], [30, 60, 120, 300], [30, 60, 120, 300, 300]] as [[TimeInterval]] {
            await waitUntil { self.sleeps.delays == expected && self.sleeps.waiting == 1 }
            if expected.count < 5 { sleeps.releaseNext() }
        }
        box.set(.success(good))
        sleeps.releaseNext()
        await waitUntil { store.catalog?.isStale == false }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(sleeps.delays.count, 5)
        XCTAssertEqual(sleeps.waiting, 0)
    }

    func testHomeAndBothStacksFailingTogetherShareOneRetry() async {
        let box = ReadBox(.success(WidgetCatalog(engine: "1.3", packagesRelease: "v41", widgets: [])))
        let store = retryingStore(box)
        await store.reload()
        box.set(.failure(ReadError.offline))
        await store.reload()
        await store.reload()
        await store.reload()
        await waitUntil { self.sleeps.waiting == 1 }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(sleeps.delays, [30])
    }

    func testNoCatalogYetAndNothingWaitingForItMeansNoRetry() async {
        let store = retryingStore(ReadBox(.failure(ReadError.offline)))
        await store.reload()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(sleeps.delays, [])
    }

    func testAFailedFirstReadIsRetriedOnlyWhileABoardWaitsForTheCatalog() async {
        let reads = ReadCounter()
        let box = ReadBox(.failure(ReadError.offline))
        let store = retryingStore(box, reads: reads)
        await store.reload()
        store.setWaitsForCatalog(true, board: "home")
        await waitUntil { self.sleeps.waiting == 1 }
        store.setWaitsForCatalog(true, board: "sidebar")
        sleeps.releaseNext()
        await waitUntil { self.sleeps.delays == [30, 60] && self.sleeps.waiting == 1 }
        XCTAssertEqual(reads.value, 2)

        store.setWaitsForCatalog(false, board: "home")
        store.setWaitsForCatalog(false, board: "sidebar")
        sleeps.releaseNext()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(reads.value, 2)

        store.setWaitsForCatalog(true, board: "context-sidebar")
        await waitUntil { self.sleeps.delays == [30, 60, 30] }
        box.set(.success(WidgetCatalog(engine: "1.3", packagesRelease: "v41", widgets: [])))
        sleeps.releaseNext()
        await waitUntil { store.catalog != nil }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(sleeps.delays.count, 3)
    }

    func testABoardWaitingBeforeTheFirstReadFailsGetsTheRetryWhenItFails() async {
        let store = retryingStore(ReadBox(.failure(ReadError.offline)))
        store.setWaitsForCatalog(true, board: "home")
        XCTAssertEqual(sleeps.delays, [])
        await store.reload()
        await waitUntil { self.sleeps.delays == [30] }
    }

    func testStoppingCancelsThePendingRetry() async {
        let reads = ReadCounter()
        let box = ReadBox(.success(WidgetCatalog(engine: "1.3", packagesRelease: "v41", widgets: [])))
        let store = retryingStore(box, reads: reads)
        await store.reload()
        box.set(.failure(ReadError.offline))
        await store.reload()
        await waitUntil { self.sleeps.waiting == 1 }
        store.stopRetrying()
        sleeps.releaseNext()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(reads.value, 2)
    }
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
