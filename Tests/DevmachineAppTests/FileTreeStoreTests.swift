import XCTest
import Combine
import DevmachineCore
@testable import DevmachineApp

private final class TreeRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private let rootOutput: String
    private let rootError: String
    private var listings: [String: String]
    private var commands: [String] = []

    init(root: String, listings: [String: String], rootError: String = "") {
        self.rootOutput = root
        self.rootError = rootError
        self.listings = listings
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        let command = args.last ?? ""
        lock.lock()
        commands.append(command)
        let listings = self.listings
        lock.unlock()

        if command.contains("rev-parse") {
            return (rootOutput, rootError, rootOutput.isEmpty ? 1 : 0)
        }
        guard let path = Self.listedPath(command) else { return ("", "", 1) }
        return (listings[path] ?? "", "", 0)
    }

    func setListing(_ output: String, for path: String) {
        lock.lock()
        listings[path] = output
        lock.unlock()
    }

    func listCount(for path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return commands.filter { Self.listedPath($0) == path }.count
    }

    var rootCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return commands.filter { $0.contains("rev-parse") }.count
    }

    private static func listedPath(_ command: String) -> String? {
        guard command.hasPrefix("find '"), let end = command.range(of: "' -mindepth") else { return nil }
        let start = command.index(command.startIndex, offsetBy: 6)
        return String(command[start..<end.lowerBound])
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
final class FileTreeStoreTests: XCTestCase {
    private let root = "/home/alice/dev/dash"

    private var listings: [String: String] {
        [
            "/home/alice/dev/dash": "d\tSources\nf\tREADME.md\nd\tTests\n",
            "/home/alice/dev/dash/Sources": "f\tApp.swift\nd\tViews\n",
            "/home/alice/dev/dash/Tests": ""
        ]
    }

    private func makeStore(
        root: String? = nil,
        listings: [String: String]? = nil,
        rootError: String = ""
    ) -> (FileTreeStore, TreeRunner) {
        let runner = TreeRunner(
            root: root ?? self.root,
            listings: listings ?? self.listings,
            rootError: rootError
        )
        return (FileTreeStore(remote: RemoteService(runner: runner)), runner)
    }

    func testStartResolvesTheRootAndListsIt() async throws {
        let (store, _) = makeStore()
        defer { store.stop() }

        store.start(alias: "acme-devmachine", session: "dash")
        try await waitUntil { store.children[self.root] != nil }

        XCTAssertEqual(store.root, root)
        XCTAssertEqual(store.children[root]?.map(\.name), ["Sources", "Tests", "README.md"])
        XCTAssertEqual(store.visibleRows.map(\.name), ["Sources", "Tests", "README.md"])
        XCTAssertEqual(store.visibleRows.map(\.depth), [0, 0, 0])
        XCTAssertNil(store.errorText)
        XCTAssertFalse(store.isLoading)
    }

    func testTheRootIsThePanePathWhenTheSessionIsNotInARepository() async throws {
        let (store, _) = makeStore(root: "/home/alice", listings: ["/home/alice": "d\tdev\n"])
        defer { store.stop() }

        store.start(alias: "acme-devmachine", session: "shell")
        try await waitUntil { store.root != nil }

        XCTAssertEqual(store.root, "/home/alice")
        XCTAssertNil(store.errorText)
    }

    func testAnEmptyRootWithAMessageIsAnError() async throws {
        let (store, _) = makeStore(root: "", listings: [:], rootError: "no server running\n")
        defer { store.stop() }

        store.start(alias: "acme-devmachine", session: "gone")
        try await waitUntil { store.errorText != nil }

        XCTAssertNil(store.root)
        XCTAssertEqual(store.errorText, "no server running")
        XCTAssertFalse(store.isLoading)
    }

    func testAnEmptyRootWithoutAMessageLeavesNoPathAndNoError() async throws {
        let (store, _) = makeStore(root: "", listings: [:])
        defer { store.stop() }

        store.start(alias: "acme-devmachine", session: "gone")
        try await waitUntil { !store.isLoading }

        XCTAssertNil(store.root)
        XCTAssertNil(store.errorText)
    }

    func testExpandingADirectoryLoadsItOnceAndCollapsingKeepsTheCache() async throws {
        let (store, runner) = makeStore()
        defer { store.stop() }
        let sources = root + "/Sources"

        store.start(alias: "acme-devmachine", session: "dash")
        try await waitUntil { store.children[self.root] != nil }

        store.toggle(sources)
        try await waitUntil { store.children[sources] != nil }
        XCTAssertEqual(runner.listCount(for: sources), 1)
        XCTAssertEqual(store.visibleRows.map(\.name), ["Sources", "Views", "App.swift", "Tests", "README.md"])
        XCTAssertEqual(store.visibleRows.map(\.depth), [0, 1, 1, 0, 0])

        store.toggle(sources)
        XCTAssertFalse(store.expanded.contains(sources))
        XCTAssertNotNil(store.children[sources])
        XCTAssertEqual(store.visibleRows.map(\.name), ["Sources", "Tests", "README.md"])

        store.toggle(sources)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(runner.listCount(for: sources), 1)
    }

    func testAnExpandedEmptyDirectoryGetsAPlaceholderRow() async throws {
        let (store, _) = makeStore()
        defer { store.stop() }
        let tests = root + "/Tests"

        store.start(alias: "acme-devmachine", session: "dash")
        try await waitUntil { store.children[self.root] != nil }
        store.toggle(tests)
        try await waitUntil { store.children[tests] != nil }

        let placeholder = try XCTUnwrap(store.visibleRows.first { $0.isPlaceholder })
        XCTAssertEqual(placeholder.name, "empty")
        XCTAssertEqual(placeholder.depth, 1)
        XCTAssertEqual(placeholder.path, tests)
        XCTAssertFalse(placeholder.isDirectory)
    }

    func testRefreshReloadsTheRootAndEveryExpandedDirectory() async throws {
        let (store, runner) = makeStore()
        defer { store.stop() }
        let sources = root + "/Sources"

        store.start(alias: "acme-devmachine", session: "dash")
        try await waitUntil { store.children[self.root] != nil }
        store.toggle(sources)
        try await waitUntil { store.children[sources] != nil }

        runner.setListing("f\tApp.swift\nf\tFileTree.swift\n", for: sources)
        store.refresh()
        try await waitUntil { store.children[sources]?.map(\.name) == ["App.swift", "FileTree.swift"] }

        XCTAssertEqual(runner.rootCount, 2)
        XCTAssertEqual(runner.listCount(for: root), 2)
        XCTAssertEqual(runner.listCount(for: sources), 2)
        XCTAssertTrue(store.expanded.contains(sources))
    }

    func testANewRootDropsTheOldExpansion() async throws {
        let (store, _) = makeStore()
        let sources = root + "/Sources"

        store.start(alias: "acme-devmachine", session: "dash")
        try await waitUntil { store.children[self.root] != nil }
        store.toggle(sources)
        try await waitUntil { store.children[sources] != nil }

        store.stop()
        XCTAssertNil(store.root)
        XCTAssertTrue(store.expanded.isEmpty)
        XCTAssertTrue(store.children.isEmpty)

        let other = "/home/alice/dev/site"
        let (second, _) = makeStore(root: other, listings: [other: "f\tindex.html\n"])
        defer { second.stop() }
        second.start(alias: "acme-devmachine", session: "site")
        try await waitUntil { second.children[other] != nil }

        XCTAssertEqual(second.visibleRows.map(\.name), ["index.html"])
    }

    func testStartingTheSameSessionTwiceDoesNotReload() async throws {
        let (store, runner) = makeStore()
        defer { store.stop() }

        store.start(alias: "acme-devmachine", session: "dash")
        try await waitUntil { store.children[self.root] != nil }
        store.start(alias: "acme-devmachine", session: "dash")
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(runner.rootCount, 1)
    }

    func testRelativeAndParentPaths() async throws {
        let (store, _) = makeStore()
        defer { store.stop() }

        store.start(alias: "acme-devmachine", session: "dash")
        try await waitUntil { store.root != nil }

        XCTAssertEqual(store.relativePath(of: root + "/Sources/App.swift"), "Sources/App.swift")
        XCTAssertEqual(store.relativePath(of: root), root)
        XCTAssertEqual(store.parentPath(of: root + "/Sources/App.swift"), root + "/Sources")
        XCTAssertEqual(store.parentPath(of: "/top"), "/")
    }
}
