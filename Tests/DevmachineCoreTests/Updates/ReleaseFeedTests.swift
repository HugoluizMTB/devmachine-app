import XCTest
@testable import DevmachineCore

private final class FakeHTTP: HTTPFetching, @unchecked Sendable {
    var responses: [HTTPResponse]
    private(set) var requests: [(URL, [String: String])] = []

    init(_ responses: [HTTPResponse]) {
        self.responses = responses
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append((url, headers))
        return responses.removeFirst()
    }
}

final class ReleaseFeedTests: XCTestCase {
    private let url = URL(string: "https://api.example.com/repos/example/app-releases/releases/latest")!
    private let body = Data(GitHubReleaseTests.json.utf8)

    func testAFreshAnswerIsDecodedAndItsETagKept() async throws {
        let http = FakeHTTP([HTTPResponse(status: 200, headers: ["ETag": "\"abc\""], body: body)])
        let feed = ReleaseFeed(url: url, fetcher: http, userAgent: "Devmachine/0.1.2")

        let result = try await feed.latest(cached: nil)

        XCTAssertEqual(result.release.tagName, "v0.1.3")
        XCTAssertEqual(result.cache, CachedRelease(etag: "\"abc\"", body: body))
        XCTAssertNil(http.requests[0].1["If-None-Match"])
        XCTAssertEqual(http.requests[0].1["User-Agent"], "Devmachine/0.1.2")
        XCTAssertEqual(http.requests[0].1["Accept"], "application/vnd.github+json")
    }

    func testSendsTheCachedETagAndReusesTheCachedBodyOn304() async throws {
        let http = FakeHTTP([HTTPResponse(status: 304, headers: [:], body: Data())])
        let feed = ReleaseFeed(url: url, fetcher: http, userAgent: "Devmachine/0.1.2")
        let cached = CachedRelease(etag: "\"abc\"", body: body)

        let result = try await feed.latest(cached: cached)

        XCTAssertEqual(http.requests[0].1["If-None-Match"], "\"abc\"")
        XCTAssertEqual(result.release.tagName, "v0.1.3")
        XCTAssertEqual(result.cache, cached)
    }

    func testHeaderNamesAreMatchedWithoutCase() async throws {
        let http = FakeHTTP([HTTPResponse(status: 200, headers: ["etag": "W/\"x\""], body: body)])
        let feed = ReleaseFeed(url: url, fetcher: http, userAgent: "Devmachine")
        let result = try await feed.latest(cached: nil)
        XCTAssertEqual(result.cache?.etag, "W/\"x\"")
    }

    func testAnAnswerWithoutETagIsNotCached() async throws {
        let http = FakeHTTP([HTTPResponse(status: 200, headers: [:], body: body)])
        let feed = ReleaseFeed(url: url, fetcher: http, userAgent: "Devmachine")
        let result = try await feed.latest(cached: CachedRelease(etag: "\"old\"", body: Data()))
        XCTAssertNil(result.cache)
    }

    func testRateLimitAndMissingReleaseAreTheirOwnErrors() async {
        let limited = ReleaseFeed(
            url: url, fetcher: FakeHTTP([HTTPResponse(status: 403, headers: [:], body: Data())]),
            userAgent: "Devmachine")
        await assertThrows(ReleaseFeedError.rateLimited) { _ = try await limited.latest(cached: nil) }

        let missing = ReleaseFeed(
            url: url, fetcher: FakeHTTP([HTTPResponse(status: 404, headers: [:], body: Data())]),
            userAgent: "Devmachine")
        await assertThrows(ReleaseFeedError.noRelease) { _ = try await missing.latest(cached: nil) }

        let broken = ReleaseFeed(
            url: url, fetcher: FakeHTTP([HTTPResponse(status: 502, headers: [:], body: Data())]),
            userAgent: "Devmachine")
        await assertThrows(ReleaseFeedError.httpStatus(502)) { _ = try await broken.latest(cached: nil) }
    }

    func testA304WithNothingCachedIsAnError() async {
        let feed = ReleaseFeed(
            url: url, fetcher: FakeHTTP([HTTPResponse(status: 304, headers: [:], body: Data())]),
            userAgent: "Devmachine")
        await assertThrows(ReleaseFeedError.httpStatus(304)) { _ = try await feed.latest(cached: nil) }
    }

    private func assertThrows(
        _ expected: ReleaseFeedError, _ body: () async throws -> Void, line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected)", line: line)
        } catch {
            XCTAssertEqual(error as? ReleaseFeedError, expected, line: line)
        }
    }
}
