import XCTest
@testable import DevmachineCore

private struct Item: Codable, Equatable, Sendable, Identifiable {
    let id: String
    var value: Int
}

private final class FetchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func bump() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

@MainActor
private final class Clock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
final class DataCacheTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("datacache-tests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var fileURL: URL { directory.appendingPathComponent("machine-cache.json") }

    private func makeCache(clock: Clock, file: CacheFile? = nil) -> DataCache {
        DataCache(file: file, policy: .standard, now: { clock.now })
    }

    private let sites = CacheKey<[Item]>(.sites, "box")

    func testAPutValueReadsBackWithItsTime() {
        let clock = Clock()
        let cache = makeCache(clock: clock)
        cache.put(sites, [Item(id: "a", value: 1)])

        let cached = cache.cached(sites)
        XCTAssertEqual(cached?.value, [Item(id: "a", value: 1)])
        XCTAssertEqual(cached?.fetchedAt, clock.now)
    }

    func testAValueWrittenToDiskIsReadByTheNextLaunch() {
        let clock = Clock()
        let first = makeCache(clock: clock, file: CacheFile(fileURL: fileURL))
        first.put(sites, [Item(id: "a", value: 1)])
        first.waitForPendingWrites()

        let second = makeCache(clock: clock, file: CacheFile(fileURL: fileURL))
        XCTAssertEqual(second.cached(sites)?.value, [Item(id: "a", value: 1)])
        XCTAssertEqual(second.cached(sites)?.fetchedAt, clock.now)
    }

    func testAnUnchangedAnswerRewritesTheFileOnlyNowAndThen() {
        let clock = Clock()
        let file = CacheFile(fileURL: fileURL)
        let cache = makeCache(clock: clock, file: file)
        cache.put(sites, [Item(id: "a", value: 1)])
        let written = clock.now

        clock.advance(5)
        cache.put(sites, [Item(id: "a", value: 1)])
        cache.waitForPendingWrites()
        XCTAssertEqual(file.load().first?.fetchedAt, written)

        clock.advance(30)
        cache.put(sites, [Item(id: "a", value: 1)])
        cache.waitForPendingWrites()
        XCTAssertEqual(file.load().first?.fetchedAt, clock.now)
    }

    func testACorruptFileIsIgnored() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: fileURL)

        let cache = makeCache(clock: Clock(), file: CacheFile(fileURL: fileURL))
        XCTAssertNil(cache.cached(sites))
        cache.put(sites, [Item(id: "a", value: 1)])
        cache.waitForPendingWrites()
        XCTAssertEqual(CacheFile(fileURL: fileURL).load().count, 1)
    }

    func testAnEntryOfAnotherShapeIsDroppedNotThrown() {
        let clock = Clock()
        let file = CacheFile(fileURL: fileURL)
        let first = makeCache(clock: clock, file: file)
        first.put(CacheKey<String>(.sites, "box"), "not a list")
        first.waitForPendingWrites()

        let second = makeCache(clock: clock, file: file)
        XCTAssertNil(second.cached(sites))
    }

    func testAFileFromAnotherVersionIsIgnored() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"version": 999, "entries": {}}"#.utf8).write(to: fileURL)
        XCTAssertTrue(CacheFile(fileURL: fileURL).load().isEmpty)
    }

    func testFreshnessFollowsTheKindsTTL() {
        let clock = Clock()
        let cache = makeCache(clock: clock)
        cache.put(sites, [])
        XCTAssertTrue(cache.isFresh(sites))
        clock.advance(CachePolicy.standard.ttl(for: .sites) + 1)
        XCTAssertFalse(cache.isFresh(sites))
        XCTAssertTrue(cache.cached(sites)?.isStale ?? false)
    }

    func testTTLsDifferPerKind() {
        let policy = CachePolicy.standard
        XCTAssertLessThanOrEqual(policy.ttl(for: .ports), 60)
        XCTAssertGreaterThanOrEqual(policy.ttl(for: .ports), 30)
        XCTAssertEqual(policy.ttl(for: .sites), 60)
        XCTAssertEqual(policy.ttl(for: .dnsRecords), 300)
        XCTAssertEqual(policy.ttl(for: .dnsProviders), 300)
    }

    func testRevalidateHandsBackTheCachedValueAtOnceThenTheFreshOne() async throws {
        let clock = Clock()
        let cache = makeCache(clock: clock)
        cache.put(sites, [Item(id: "a", value: 1)])
        clock.advance(120)

        let updated = expectation(description: "fresh value")
        var received: [Item]?
        let immediate = cache.revalidate(sites, fetch: { [Item(id: "a", value: 2)] }) { update in
            received = update.cached.value
            updated.fulfill()
        }

        XCTAssertEqual(immediate?.value, [Item(id: "a", value: 1)])
        XCTAssertNil(received)
        await fulfillment(of: [updated], timeout: 2)
        XCTAssertEqual(received, [Item(id: "a", value: 2)])
        XCTAssertEqual(cache.cached(sites)?.fetchedAt, clock.now)
    }

    func testRevalidateOfAFreshValueAsksNothing() async {
        let clock = Clock()
        let cache = makeCache(clock: clock)
        cache.put(sites, [Item(id: "a", value: 1)])
        let counter = FetchCounter()

        _ = cache.revalidate(sites, fetch: { _ = counter.bump(); return [] }) { _ in }
        await cache.settle()

        XCTAssertEqual(counter.value, 0)
    }

    func testAManualRefreshBypassesTheTTL() async throws {
        let clock = Clock()
        let cache = makeCache(clock: clock)
        cache.put(sites, [Item(id: "a", value: 1)])
        let counter = FetchCounter()

        _ = cache.revalidate(sites, force: true, fetch: { _ = counter.bump(); return [Item(id: "a", value: 9)] }) { _ in }
        await cache.settle()

        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(cache.cached(sites)?.value, [Item(id: "a", value: 9)])
    }

    func testAnEqualAnswerRefreshesTheAgeButReportsNoChange() async {
        let clock = Clock()
        let cache = makeCache(clock: clock)
        cache.put(sites, [Item(id: "a", value: 1)])
        clock.advance(120)
        var updates = 0

        _ = cache.revalidate(sites, fetch: { [Item(id: "a", value: 1)] }) { if $0.changed { updates += 1 } }
        await cache.settle()

        XCTAssertEqual(updates, 0)
        XCTAssertEqual(cache.cached(sites)?.fetchedAt, clock.now)
    }

    func testConcurrentRefreshesOfOneKeyShareOneFetch() async throws {
        let cache = makeCache(clock: Clock())
        let counter = FetchCounter()
        let fetch: @Sendable () async throws -> [Item] = {
            let n = counter.bump()
            try await Task.sleep(nanoseconds: 50_000_000)
            return [Item(id: "a", value: n)]
        }

        let one = Task { try await cache.value(sites, fetch: fetch) }
        let two = Task { try await cache.value(sites, fetch: fetch) }
        let three = Task { try await cache.value(sites, force: true, fetch: fetch) }
        let results = try await [one.value, two.value, three.value]

        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(results, Array(repeating: [Item(id: "a", value: 1)], count: 3))
        XCTAssertFalse(cache.isRefreshing(sites))
    }

    func testWaitingForAKeyEndsWhenItsRunningFetchAnswers() async {
        let cache = makeCache(clock: Clock())
        _ = cache.revalidate(sites, fetch: {
            try await Task.sleep(nanoseconds: 50_000_000)
            return [Item(id: "a", value: 1)]
        }) { _ in }
        XCTAssertTrue(cache.isRefreshing(sites))

        await cache.waitForRunningFetch(sites)

        XCTAssertFalse(cache.isRefreshing(sites))
        XCTAssertEqual(cache.cached(sites)?.value, [Item(id: "a", value: 1)])
    }

    func testDifferentKeysFetchSeparately() async throws {
        let cache = makeCache(clock: Clock())
        let counter = FetchCounter()
        let fetch: @Sendable () async throws -> [Item] = { _ = counter.bump(); return [] }

        let one = Task { try await cache.value(sites, fetch: fetch) }
        let two = Task { try await cache.value(CacheKey<[Item]>(.sites, "other"), fetch: fetch) }
        _ = try await (one.value, two.value)

        XCTAssertEqual(counter.value, 2)
    }

    func testAFailedRefreshKeepsTheCachedValueAndRemembersTheError() async {
        let clock = Clock()
        let cache = makeCache(clock: clock)
        cache.put(sites, [Item(id: "a", value: 1)])
        clock.advance(120)
        var failure: Error?

        _ = cache.revalidate(sites, fetch: { throw CacheTestError.offline }, onUpdate: { _ in }, onError: { failure = $0 })
        await cache.settle()

        XCTAssertNotNil(failure)
        XCTAssertEqual(cache.cached(sites)?.value, [Item(id: "a", value: 1)])
        XCTAssertNotNil(cache.lastError(sites))
    }

    func testAFailedKeyIsNotAskedAgainUntilItsRetryDelayPasses() async {
        let clock = Clock()
        let cache = makeCache(clock: clock)
        cache.put(sites, [Item(id: "a", value: 1)])
        clock.advance(120)
        let counter = FetchCounter()
        let failing: @Sendable () async throws -> [Item] = { _ = counter.bump(); throw CacheTestError.offline }

        _ = cache.revalidate(sites, fetch: failing) { _ in }
        await cache.settle()
        _ = cache.revalidate(sites, fetch: failing) { _ in }
        await cache.settle()
        XCTAssertEqual(counter.value, 1)

        clock.advance(CachePolicy.standard.retryAfterFailure + 1)
        _ = cache.revalidate(sites, fetch: failing) { _ in }
        await cache.settle()
        XCTAssertEqual(counter.value, 2)
    }

    func testAManualRefreshIgnoresTheRetryDelay() async {
        let cache = makeCache(clock: Clock())
        let counter = FetchCounter()
        let failing: @Sendable () async throws -> [Item] = { _ = counter.bump(); throw CacheTestError.offline }

        _ = try? await cache.value(sites, fetch: failing)
        _ = try? await cache.value(sites, fetch: failing)
        XCTAssertEqual(counter.value, 1)

        _ = try? await cache.value(sites, force: true, fetch: failing)
        XCTAssertEqual(counter.value, 2)
    }

    func testInvalidatingAKindMakesItsEntriesStaleButKeepsThem() {
        let clock = Clock()
        let cache = makeCache(clock: clock)
        let other = CacheKey<[Item]>(.dnsRecords, "box|cf|example.com")
        cache.put(sites, [Item(id: "a", value: 1)])
        cache.put(other, [])

        cache.invalidate(.sites, scope: "box")

        XCTAssertFalse(cache.isFresh(sites))
        XCTAssertEqual(cache.cached(sites)?.value, [Item(id: "a", value: 1)])
        XCTAssertTrue(cache.isFresh(other))
    }

    func testInvalidatingByScopePrefixReachesEveryProvider() {
        let cache = makeCache(clock: Clock())
        let cloudflare = CacheKey<[Item]>(.dnsRecords, "box|cf|example.com")
        let route53 = CacheKey<[Item]>(.dnsRecords, "box|r53|example.com")
        let elsewhere = CacheKey<[Item]>(.dnsRecords, "edge|cf|example.com")
        for key in [cloudflare, route53, elsewhere] { cache.put(key, []) }

        cache.invalidate(.dnsRecords, scopePrefix: "box|")

        XCTAssertFalse(cache.isFresh(cloudflare))
        XCTAssertFalse(cache.isFresh(route53))
        XCTAssertTrue(cache.isFresh(elsewhere))
    }

    func testAnInvalidatedEntryRefetchesOnTheNextRevalidate() async {
        let cache = makeCache(clock: Clock())
        cache.put(sites, [Item(id: "a", value: 1)])
        cache.invalidate(.sites, scope: "box")
        let counter = FetchCounter()

        _ = cache.revalidate(sites, fetch: { _ = counter.bump(); return [Item(id: "b", value: 2)] }) { _ in }
        await cache.settle()

        XCTAssertEqual(counter.value, 1)
        XCTAssertTrue(cache.isFresh(sites))
    }

    func testObserversHearOnlyRealChanges() async {
        let cache = makeCache(clock: Clock())
        var heard: [String] = []
        cache.observe { heard.append($0.id) }

        cache.put(sites, [Item(id: "a", value: 1)])
        cache.put(sites, [Item(id: "a", value: 1)])
        cache.put(sites, [Item(id: "a", value: 2)])

        XCTAssertEqual(heard, ["sites:box", "sites:box"])
    }

    func testOldContextEntriesArePrunedToTheKindsLimit() {
        let clock = Clock()
        let cache = makeCache(clock: clock)
        let limit = CachePolicy.standard.maxEntries(for: .context)
        for index in 0..<(limit + 5) {
            clock.advance(1)
            cache.put(CacheKey<Int>(.context, "s\(index)"), index)
        }
        XCTAssertNil(cache.cached(CacheKey<Int>(.context, "s0")))
        XCTAssertEqual(cache.cached(CacheKey<Int>(.context, "s\(limit + 4)"))?.value, limit + 4)
        XCTAssertEqual(cache.count(of: .context), limit)
    }
}

private enum CacheTestError: Error { case offline }
