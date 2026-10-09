import XCTest
@testable import DevmachineCore

final class SessionShareTests: XCTestCase {
    private let started = """
        {
          "exposed": false,
          "password": "v3bd-28s5-nave-dvcg",
          "share": {
            "active": true,
            "created_at": "2026-10-08T20:17:19.673331096Z",
            "expires_at": "2026-10-08T21:17:19.673331096Z",
            "id": "wvx3januvgyj",
            "max_viewers": 1,
            "mode": "write",
            "name": "Pairing",
            "session": "main",
            "ssh_guests": [],
            "url": "https://share.example.com/s/wvx3januvgyj/",
            "viewers": []
          },
          "ssh_user": "alice",
          "version": 1
        }
        """

    private let listed = """
        {
          "shares": [
            {"active": true, "created_at": "2026-10-08T20:17:19Z", "expires_at": "2026-10-08T21:17:19Z",
             "id": "wvx3januvgyj", "max_viewers": 1, "mode": "read", "session": "main", "ssh_guests": ["bob"],
             "url": "http://127.0.0.1:7690/s/wvx3januvgyj/",
             "viewers": [{"conn_id": "4ef6c90c125e", "kind": "web", "remote": "203.0.113.7", "started": "2026-10-08T20:18:00Z"}]},
            {"active": false, "created_at": "2026-10-08T19:00:00Z", "expires_at": "2026-10-08T20:00:00Z",
             "ended_at": "2026-10-08T19:30:00.5Z", "end_reason": "revoked", "id": "abcdefghijkl", "max_viewers": 1,
             "mode": "write", "session": "api", "ssh_guests": [], "viewers": []}
          ],
          "version": 1
        }
        """

    func testStartArgumentsReachThePackageAsTheWorkspace() {
        XCTAssertEqual(
            SessionShareCommand.startArguments(
                workspace: "acme", session: "main", mode: .write, duration: .oneHour, name: "  Pairing  "),
            ["run", "--workspace", "acme", "--no-log", "--package", "session-share", "--",
             "start", "main", "--mode", "write", "--for", "1h", "--name", "Pairing", "--json"])
        XCTAssertEqual(
            SessionShareCommand.startArguments(workspace: "acme", session: "-x", mode: .read, duration: .fifteenMinutes, name: " "),
            ["run", "--workspace", "acme", "--no-log", "--package", "session-share", "--",
             "start", "-x", "--mode", "read", "--for", "15m", "--json"])
        XCTAssertEqual(
            SessionShareCommand.listArguments(workspace: "acme"),
            ["run", "--workspace", "acme", "--no-log", "--package", "session-share", "--", "shares"])
        XCTAssertEqual(
            SessionShareCommand.extendArguments(workspace: "acme", id: "wvx3januvgyj", by: "30m").suffix(5),
            ["extend", "wvx3januvgyj", "--for", "30m", "--json"])
        XCTAssertEqual(
            SessionShareCommand.stopArguments(workspace: "acme", id: "wvx3januvgyj").suffix(3),
            ["stop", "wvx3januvgyj", "--json"])
    }

    func testStartReadsTheShareAndThePassword() throws {
        let result = try SessionShareCommand.parseStart(started)
        XCTAssertEqual(result.password, "v3bd-28s5-nave-dvcg")
        XCTAssertEqual(result.share.id, "wvx3januvgyj")
        XCTAssertEqual(result.share.mode, .write)
        XCTAssertEqual(result.share.name, "Pairing")
        XCTAssertEqual(result.share.expiresAt.timeIntervalSince(result.share.createdAt), 3600, accuracy: 0.001)
        XCTAssertFalse(result.share.isLocalOnly)
    }

    func testListReadsLiveAndEndedShares() throws {
        let shares = try SessionShareCommand.parseList(listed)
        XCTAssertEqual(shares.count, 2)
        XCTAssertEqual(shares[0].viewers, [SessionShareViewer(connID: "4ef6c90c125e", kind: "web", remote: "203.0.113.7")])
        XCTAssertTrue(shares[0].isLocalOnly)
        XCTAssertEqual(shares[1].endReason, "revoked")
        XCTAssertNotNil(shares[1].endedAt)
    }

    func testAnotherJSONVersionIsRefused() {
        let newer = started.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2")
        XCTAssertThrowsError(try SessionShareCommand.parseStart(newer)) { error in
            XCTAssertEqual(error as? SessionShareError, .unsupportedVersion(2))
        }
    }

    func testAMissingPackageIsToldApartFromOtherFailures() {
        XCTAssertTrue(SessionShareCommand.isMissingPackage(
            "error: session-share is not installed on main or workspace acme. Add it with `devmachine packages add session-share`"))
        XCTAssertTrue(SessionShareCommand.isMissingPackage("error: session-share does not accept \"shares\". It accepts start, stop"))
        XCTAssertFalse(SessionShareCommand.isMissingPackage("session-share: no such tmux session \"main\""))
    }

    func testMergeTakesTheToolsStateAndEndsWhatItNoLongerLists() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let shares = try SessionShareCommand.parseList(listed)
        let live = SessionShareRecord(shares[0], workspace: "acme", alias: "acme-devmachine")
        let stale = SessionShareRecord(
            id: "zzzzzzzzzzzz", workspace: "acme", alias: "acme-devmachine", session: "old", name: "old",
            mode: .read, url: nil, createdAt: now.addingTimeInterval(-60), expiresAt: now.addingTimeInterval(600))
        let other = SessionShareRecord(
            id: "yyyyyyyyyyyy", workspace: "beta", alias: "beta-devmachine", session: "x", name: "x",
            mode: .read, url: nil, createdAt: now, expiresAt: now.addingTimeInterval(600))
        var revoked = SessionShareRecord(shares[1], workspace: "acme", alias: "acme-devmachine")
        revoked.endedAt = nil
        revoked.endReason = nil

        let merged = SessionShareHistory.merge([live, stale, other, revoked], with: shares, workspace: "acme", now: now)

        XCTAssertNil(merged[0].endedAt)
        XCTAssertEqual(merged[1].endReason, "gone")
        XCTAssertEqual(merged[1].endedAt, now)
        XCTAssertEqual(merged[2], other)
        XCTAssertEqual(merged[3].endReason, "revoked")
    }

    func testHistoryRoundTripsNewestFirstAndCapped() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-share-history-\(UUID().uuidString)/shares.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let history = SessionShareHistory(fileURL: url)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let records = (0..<(SessionShareHistory.limit + 5)).map { i in
            SessionShareRecord(
                id: String(format: "%012d", i), workspace: "acme", alias: "acme-devmachine", session: "main",
                name: "main", mode: .read, url: nil, createdAt: base.addingTimeInterval(Double(i)),
                expiresAt: base.addingTimeInterval(Double(i) + 3600))
        }
        try history.save(records)
        let loaded = history.load()
        XCTAssertEqual(loaded.count, SessionShareHistory.limit)
        XCTAssertEqual(loaded.first?.id, String(format: "%012d", SessionShareHistory.limit + 4))
        XCTAssertTrue(SessionShareHistory(fileURL: nil).load().isEmpty)
    }

    func testRecordIsLiveUntilItEndsOrExpires() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var record = SessionShareRecord(
            id: "wvx3januvgyj", workspace: "acme", alias: "acme-devmachine", session: "main", name: "main",
            mode: .read, url: nil, createdAt: now, expiresAt: now.addingTimeInterval(60))
        XCTAssertTrue(record.isLive(at: now))
        XCTAssertFalse(record.isLive(at: now.addingTimeInterval(60)))
        record.markEnded("revoked", at: now)
        XCTAssertFalse(record.isLive(at: now))
        record.markEnded("expired", at: now.addingTimeInterval(5))
        XCTAssertEqual(record.endReason, "revoked")
    }

    func testChatLinesAreReadOneByOne() {
        let line = #"{"message":{"from":"bob","id":"a1","role":"guest","text":"hi <b>there</b>","ts":"2026-10-08T23:31:05.123456789Z"},"version":1}"#
        let message = SessionShareCommand.parseChatLine(line)
        XCTAssertEqual(message?.from, "bob")
        XCTAssertEqual(message?.text, "hi <b>there</b>")
        XCTAssertEqual(message?.isOwner, false)
        XCTAssertNil(SessionShareCommand.parseChatLine("Warning: Permanently added the host key"))
        XCTAssertNil(SessionShareCommand.parseChatLine(line.replacingOccurrences(of: #""version":1"#, with: #""version":2"#)))
        XCTAssertEqual(
            SessionShareCommand.chatFollowArguments(workspace: "acme", id: "wvx3januvgyj").suffix(4),
            ["chat", "wvx3januvgyj", "--follow", "--json"])
        XCTAssertEqual(
            SessionShareCommand.chatSendArguments(workspace: "acme", id: "wvx3januvgyj", text: "-rf /").suffix(5),
            ["chat", "wvx3januvgyj", "--message", "-rf /", "--json"])
    }
}
