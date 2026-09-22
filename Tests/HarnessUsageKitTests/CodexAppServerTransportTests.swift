import XCTest
@testable import HarnessUsageKit

final class CodexAppServerTransportTests: XCTestCase {
    func testReadsAccountResponsesAmidNotificationsAndSendsOnlyAccountMethods() throws {
        var sent: [String] = []
        let transport = CodexAppServerTransport(timeout: 1) { requests, _ in
            sent = requests
            return [
                #"{"method":"account/rateLimits/updated","params":{}}"#,
                #"{"id":1,"result":{"userAgent":"test"}}"#,
                #"{"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":"Codex","planType":"plus","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1790000000},"secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":1790500000}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":"Codex","planType":"plus","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1790000000}}}}}"#,
                #"{"id":3,"result":{"summary":{"lifetimeTokens":1200,"peakDailyTokens":500,"currentStreakDays":null,"longestStreakDays":7,"longestRunningTurnSec":90},"dailyUsageBuckets":[{"startDate":"2026-09-20","tokens":200}]}}"#
            ]
        }

        let snapshot = try transport.accountSnapshot()

        XCTAssertEqual(snapshot.rateLimits.rateLimitsByLimitId?["codex"]?.primary?.usedPercent, 25)
        XCTAssertEqual(snapshot.usage.dailyUsageBuckets?.first?.tokens, 200)
        let methods = try sent.map { line in
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            return try XCTUnwrap(object["method"] as? String)
        }
        XCTAssertEqual(
            methods,
            ["initialize", "initialized", "account/rateLimits/read", "account/usage/read"])
        XCTAssertFalse(methods.contains("thread/start"))
        XCTAssertFalse(methods.contains("turn/start"))
    }

    func testRPCErrorIsProviderScoped() {
        let transport = CodexAppServerTransport(timeout: 1) { _, _ in
            [#"{"id":2,"error":{"code":-32000,"message":"account unavailable"}}"#]
        }

        XCTAssertThrowsError(try transport.accountSnapshot()) { error in
            XCTAssertEqual(
                error as? CodexTransportError,
                .rpcError(code: -32000, message: "account unavailable"))
        }
    }

    func testMalformedJSONIsRejected() {
        let transport = CodexAppServerTransport(timeout: 1) { _, _ in ["not-json"] }
        XCTAssertThrowsError(try transport.accountSnapshot()) { error in
            XCTAssertEqual(error as? CodexTransportError, .malformedResponse)
        }
    }

    func testTimeoutIsPropagated() {
        let transport = CodexAppServerTransport(timeout: 0.01) { _, _ in
            throw CodexTransportError.timedOut
        }
        XCTAssertThrowsError(try transport.accountSnapshot()) { error in
            XCTAssertEqual(error as? CodexTransportError, .timedOut)
        }
    }
}
