import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class FakeGHRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var capturedArgs: [[String]] = []

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        lock.lock()
        capturedArgs.append(args)
        lock.unlock()

        if args.first == "-lic" || args.contains("command -v gh") {
            return "/usr/bin/gh"
        }
        if args.first == "search" {
            return """
            [
              {"number": 1, "title": "root", "isDraft": false, "repository": {"nameWithOwner": "acme/repo"}},
              {"number": 2, "title": "stacked", "isDraft": false, "repository": {"nameWithOwner": "acme/repo"}}
            ]
            """
        }
        if args.first == "pr", args[safe: 1] == "view" {
            let number = Int(args[2]) ?? 0
            if number == 1 {
                return """
                {"number": 1, "title": "root", "url": "https://x/1", "isDraft": false,
                 "reviewDecision": "APPROVED", "headRefName": "feature-1", "baseRefName": "main",
                 "statusCheckRollup": [{"status": "COMPLETED", "conclusion": "SUCCESS", "state": null}]}
                """
            }
            return """
            {"number": 2, "title": "stacked", "url": "https://x/2", "isDraft": false,
             "reviewDecision": "", "headRefName": "feature-2", "baseRefName": "feature-1",
             "statusCheckRollup": []}
            """
        }
        if args.first == "api", args[safe: 1] == "user", args.contains("--jq"), args.last == ".login" {
            return "alice"
        }
        if args.first == "api", args[safe: 1] == "user/orgs" {
            return "acme\nother-org\n"
        }
        return ""
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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

// Answers `gh` for 20 open PRs and records how many `pr view` calls overlap.
private final class ConcurrencyGHRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private(set) var peak = 0
    let total = 20

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        if args.first == "-lic" || args.contains("command -v gh") { return "/usr/bin/gh" }
        if args.first == "search" {
            let items = (1...total).map {
                #"{"number": \#($0), "title": "pr", "isDraft": false, "repository": {"nameWithOwner": "acme/repo"}}"#
            }
            return "[" + items.joined(separator: ",") + "]"
        }
        if args.first == "pr" {
            lock.lock()
            active += 1
            peak = max(peak, active)
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.02)
            lock.lock()
            active -= 1
            lock.unlock()
            let number = Int(args[2]) ?? 0
            return """
            {"number": \(number), "title": "pr", "url": "https://x/\(number)", "isDraft": false,
             "reviewDecision": "", "headRefName": "b\(number)", "baseRefName": "main",
             "statusCheckRollup": []}
            """
        }
        if args.first == "api", args.last == ".login" { return "alice" }
        if args.first == "api" { return "acme\n" }
        return ""
    }

    var peakConcurrency: Int {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }
}

// Holds every search until `release()`, so a test can fire a tick mid-cycle.
private final class GatedGHRunner: CommandRunner, @unchecked Sendable {
    private let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var searches = 0

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        if args.first == "-lic" || args.contains("command -v gh") { return "/usr/bin/gh" }
        if args.first == "search" {
            lock.lock()
            searches += 1
            lock.unlock()
            gate.wait()
            return """
            [{"number": 1, "title": "root", "isDraft": false, "repository": {"nameWithOwner": "acme/repo"}}]
            """
        }
        if args.first == "pr" {
            return """
            {"number": 1, "title": "root", "url": "https://x/1", "isDraft": false,
             "reviewDecision": "", "headRefName": "b1", "baseRefName": "main",
             "statusCheckRollup": []}
            """
        }
        if args.first == "api", args.last == ".login" { return "alice" }
        if args.first == "api" { return "acme\n" }
        return ""
    }

    func release() {
        gate.signal()
    }

    var searchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return searches
    }
}

@MainActor
final class PRStoreTests: XCTestCase {
    func testEnrichKeepsAtMostSixDetailCallsInFlight() async throws {
        let runner = ConcurrencyGHRunner()
        let store = PRStore(client: GHClient(runner: runner))

        try await waitUntil(timeout: 10) { store.openCount == runner.total }

        XCTAssertLessThanOrEqual(runner.peakConcurrency, 6)
        XCTAssertGreaterThan(runner.peakConcurrency, 1)
    }

    func testTimerTickIsSkippedWhileACycleIsRunning() async throws {
        let runner = GatedGHRunner()
        let store = PRStore(client: GHClient(runner: runner))

        try await waitUntil { runner.searchCount == 1 }

        store.refreshIfIdle()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(runner.searchCount, 1)

        runner.release()
        try await waitUntil { store.openCount == 1 }

        store.refreshIfIdle()
        runner.release()
        try await waitUntil { runner.searchCount == 2 }
    }

    func testRefreshBuildsForestFromStackedPRs() async throws {
        let runner = FakeGHRunner()
        let store = PRStore(client: GHClient(runner: runner))

        try await waitUntil { store.openCount == 2 }

        XCTAssertEqual(store.forest.map { $0.pr.number }, [1, 2])
        XCTAssertEqual(store.forest.map { $0.depth }, [0, 1])
        XCTAssertNil(store.errorText)
        XCTAssertTrue(store.owners.contains("acme"))
        XCTAssertTrue(store.owners.contains("alice"))
    }

    func testSelectOwnerTriggersSearchWithOwnerFilter() async throws {
        let runner = FakeGHRunner()
        let store = PRStore(client: GHClient(runner: runner))

        try await waitUntil { store.openCount == 2 }

        store.select("acme")
        try await waitUntil {
            runner.capturedArgs.contains { $0.first == "search" && $0.contains("--owner=acme") }
        }

        XCTAssertEqual(store.selectedOwner, "acme")
    }
}
