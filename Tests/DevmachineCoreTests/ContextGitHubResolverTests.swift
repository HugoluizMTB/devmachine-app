import XCTest
@testable import DevmachineCore

private struct StubRunner: CommandRunner {
    let output: String
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { output }
}

final class ContextGitHubResolverTests: XCTestCase {
    private func ref(num: Int = 4, ts: String = "2026-01-01T00:00:00Z") -> ContextGitHubRef {
        ContextGitHubRef(
            host: "github.com", repo: "acme/dash", num: num, firstTimestamp: ts, lastTimestamp: ts, count: 1,
            url: "https://github.com/acme/dash/pull/\(num)"
        )
    }

    private func cachePath() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }

    func testResolvesAnOpenPullRequestFromTheGraphQLResponse() {
        let graphql = """
        {"data":{"a0":{"pullRequest":{"number":4,"state":"OPEN","isDraft":false,"title":"Add feature",
        "url":"https://github.com/acme/dash/pull/4","reviewDecision":"APPROVED",
        "reviewThreads":{"nodes":[{"isResolved":false}]},
        "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}}}}}
        """
        let resolver = ContextGitHubResolver(runner: StubRunner(output: graphql), cachePath: cachePath(), hosts: [])
        let result = resolver.resolve([ref()])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].state, "open")
        XCTAssertEqual(result[0].title, "Add feature")
        XCTAssertEqual(result[0].ci, "pass")
        XCTAssertEqual(result[0].review, "APPROVED")
        XCTAssertEqual(result[0].threads, 1)
    }

    func testAMissingNodeStaysUnknownButIsCached() {
        let resolver = ContextGitHubResolver(
            runner: StubRunner(output: #"{"data":{"a0":null}}"#), cachePath: cachePath(), hosts: []
        )
        let result = resolver.resolve([ref()])
        XCTAssertEqual(result[0].state, "unknown")
    }

    func testFreshCachedOpenPRIsNotReQueried() {
        let cache = cachePath()
        final class CountingRunner: CommandRunner, @unchecked Sendable {
            var calls = 0
            func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
                calls += 1
                return """
                {"data":{"a0":{"pullRequest":{"number":4,"state":"OPEN","isDraft":false,"title":"t",
                "url":"u","reviewDecision":null,"reviewThreads":{"nodes":[]},
                "commits":{"nodes":[]}}}}}
                """
            }
        }
        let runner = CountingRunner()
        let resolver = ContextGitHubResolver(runner: runner, cachePath: cache, hosts: [])
        _ = resolver.resolve([ref()], now: Date())
        XCTAssertEqual(runner.calls, 1)
        _ = resolver.resolve([ref()], now: Date().addingTimeInterval(10))
        XCTAssertEqual(runner.calls, 1)
    }

    func testRateLimitResponsePausesFurtherQueries() {
        let cache = cachePath()
        final class CountingRunner: CommandRunner, @unchecked Sendable {
            var calls = 0
            func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
                calls += 1
                return #"{"errors":[{"type":"RATE_LIMIT"}]}"#
            }
        }
        let runner = CountingRunner()
        let resolver = ContextGitHubResolver(runner: runner, cachePath: cache, hosts: [])
        _ = resolver.resolve([ref()], now: Date())
        XCTAssertEqual(runner.calls, 1)
        _ = resolver.resolve([ref()], now: Date().addingTimeInterval(10))
        XCTAssertEqual(runner.calls, 1)
    }
}
