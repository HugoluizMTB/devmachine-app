import XCTest
import Darwin
@testable import HarnessUsageKit

private final class FakeRPCSession: CodexRPCSession {
    var sent: [String] = []
    var replies: [String]
    var finished = false
    var cancelled = false

    init(replies: [String]) { self.replies = replies }
    func send(_ line: String) throws { sent.append(line) }
    func readLine(until deadline: Date) throws -> String? {
        replies.isEmpty ? nil : replies.removeFirst()
    }
    func finish(until deadline: Date) throws { finished = true }
    func cancel() { cancelled = true }
}

final class CodexAppServerTransportTests: XCTestCase {
    private let rateResponse = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":"Codex","planType":"plus","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1790000000},"secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":1790500000}}}}"#
    private let usageResponse = #"{"id":3,"result":{"summary":{"lifetimeTokens":1200,"peakDailyTokens":500,"currentStreakDays":null,"longestStreakDays":7,"longestRunningTurnSec":90},"dailyUsageBuckets":[{"startDate":"2026-09-20","tokens":200}]}}"#

    func testWaitsForInitializeThenReadsAccountResponsesBeforeFinishing() throws {
        let session = FakeRPCSession(replies: [
            #"{"method":"server/notification","params":{}}"#,
            #"{"id":1,"result":{"userAgent":"test"}}"#,
            #"{"method":"account/rateLimits/updated","params":{}}"#,
            usageResponse,
            rateResponse
        ])
        let transport = CodexAppServerTransport(timeout: 1) { session }

        let snapshot = try transport.accountSnapshot()

        XCTAssertTrue(session.finished)
        XCTAssertFalse(session.cancelled)
        XCTAssertEqual(snapshot.rateLimits.rateLimits.primary?.usedPercent, 25)
        XCTAssertEqual(snapshot.usage.dailyUsageBuckets?.first?.tokens, 200)
        let methods = try session.sent.map { line in
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            return try XCTUnwrap(object["method"] as? String)
        }
        XCTAssertEqual(methods, [
            "initialize", "initialized", "account/rateLimits/read", "account/usage/read"
        ])
        XCTAssertFalse(methods.contains("thread/start"))
        XCTAssertFalse(methods.contains("turn/start"))
    }

    func testRPCErrorCancelsSession() {
        let session = FakeRPCSession(replies: [
            #"{"id":1,"result":{}}"#,
            #"{"id":2,"error":{"code":-32000,"message":"account unavailable"}}"#
        ])
        let transport = CodexAppServerTransport(timeout: 1) { session }

        XCTAssertThrowsError(try transport.accountSnapshot()) { error in
            XCTAssertEqual(error as? CodexTransportError,
                           .rpcError(code: -32000, message: "account unavailable"))
        }
        XCTAssertTrue(session.cancelled)
    }

    func testMalformedJSONIsRejected() {
        let session = FakeRPCSession(replies: ["not-json"])
        let transport = CodexAppServerTransport(timeout: 1) { session }
        XCTAssertThrowsError(try transport.accountSnapshot()) { error in
            XCTAssertEqual(error as? CodexTransportError, .malformedResponse)
        }
    }

    func testMissingInitializeResponseIsRejected() {
        let session = FakeRPCSession(replies: [])
        let transport = CodexAppServerTransport(timeout: 1) { session }
        XCTAssertThrowsError(try transport.accountSnapshot()) { error in
            XCTAssertEqual(error as? CodexTransportError, .missingResponse(id: 1))
        }
    }

    func testProcessTransportDrainsLargeStderrWhileConnectionStaysOpen() throws {
        let script = try makeScript(body: #"""
read initialize
printf '%s\n' '{"id":1,"result":{}}'
read initialized
read rate
read usage
dd if=/dev/zero bs=1024 count=128 1>&2 2>/dev/null
printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":8}}}}'
printf '%s\n' '{"id":3,"result":{"summary":{},"dailyUsageBuckets":[]}}'
read eof || exit 0
"""#)
        defer { try? FileManager.default.removeItem(at: script) }

        let snapshot = try CodexAppServerTransport(
            executableURL: script, timeout: 2).accountSnapshot()

        XCTAssertEqual(snapshot.rateLimits.rateLimits.primary?.usedPercent, 8)
    }

    func testProcessTransportKillsHelperThatIgnoresTermination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = try makeScript(in: directory, body: """
trap '' TERM
read initialize
printf '%s\\n' '{"id":1,"result":{}}'
read initialized
read rate
read usage
printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":8}}}}'
printf '%s\\n' '{"id":3,"result":{"summary":{},"dailyUsageBuckets":[]}}'
while true; do sleep 1; done
""")

        let started = Date()
        XCTAssertThrowsError(try CodexAppServerTransport(
            executableURL: script, timeout: 0.1).accountSnapshot()) { error in
            XCTAssertEqual(error as? CodexTransportError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    private func makeScript(body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try makeScript(in: directory, body: body)
    }

    private func makeScript(in directory: URL, body: String) throws -> URL {
        let url = directory.appendingPathComponent("fake-codex")
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(url.path, 0o755), 0)
        return url
    }
}
