import XCTest
@testable import DevmachineCore

final class BugReportTests: XCTestCase {
    private let context = BugReport.Context(
        home: "/Users/alice", user: "alice", hosts: ["box.example.net", "203.0.113.10"], domains: ["example.com"])

    private func report(lines: [String]) -> BugReport {
        BugReport(
            title: "Setup failed: Connect main",
            appVersion: "0.1.14", cliVersion: "0.7.27", macOS: "15.6", arch: "arm64",
            stepID: "machines add --name main", command: "devmachine machines add --name main --address 203.0.113.10",
            exitCode: 1, lines: lines)
    }

    func testSecretsAreRedacted() {
        let text = BugReport.redact("""
            password=hunter2 token: ghp_abcdefghijklmnop secret=s3cr3t api_key=AKIAEXAMPLE
            -----BEGIN OPENSSH PRIVATE KEY-----
            b3BlbnNzaC1rZXktdjEAAAAA
            -----END OPENSSH PRIVATE KEY-----
            done
            """, context: context)
        for leaked in ["hunter2", "ghp_abcdefghijklmnop", "s3cr3t", "AKIAEXAMPLE", "b3BlbnNzaC1rZXktdjEAAAAA"] {
            XCTAssertFalse(text.contains(leaked), leaked)
        }
        XCTAssertTrue(text.contains("<redacted>"))
        XCTAssertTrue(text.contains("done"))
    }

    func testAddressesPathsNamesAndKeysAreReplaced() {
        let text = BugReport.redact(
            "ssh root@203.0.113.10 via 100.64.0.7 and 2001:db8::1 from /Users/alice/.ssh/id_ed25519 as alice; "
                + "mail alice@example.org; host box.example.net site app.example.com; "
                + "key SHA256:Zm9vYmFyYmF6cXV4ZXhhbXBsZWtleWZpbmdlcnByaW50",
            context: context)
        for leaked in ["203.0.113.10", "100.64.0.7", "2001:db8::1", "/Users/alice", "alice", "box.example.net",
                       "example.com", "Zm9vYmFy", "example.org"] {
            XCTAssertFalse(text.contains(leaked), "\(leaked) in \(text)")
        }
        for marker in ["<ip>", "~/.ssh/id_ed25519", "<user>", "<email>", "<host>", "<domain>", "<fingerprint>"] {
            XCTAssertTrue(text.contains(marker), "\(marker) missing in \(text)")
        }
    }

    func testTheURLOpensANewIssueWithTitleAndBodyAndNothingPersonal() throws {
        let url = try XCTUnwrap(report(lines: [
            "connecting to 203.0.113.10 as alice", "Permission denied (publickey,password).",
        ]).url(context: context))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://github.com/mydevmachine/devmachine/issues/new?"))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let title = try XCTUnwrap(items.first { $0.name == "title" }?.value)
        let body = try XCTUnwrap(items.first { $0.name == "body" }?.value)
        XCTAssertEqual(title, "Setup failed: Connect main")
        for expected in ["0.1.14", "0.7.27", "15.6", "arm64", "Exit code: 1", "```", "Permission denied"] {
            XCTAssertTrue(body.contains(expected), expected)
        }
        XCTAssertFalse(url.absoluteString.contains("203.0.113.10"))
        XCTAssertFalse(body.contains("alice"))
    }

    func testMachineAndWorkspaceNamesAreReplacedAsWholeWords() {
        let context = BugReport.Context(
            home: "/Users/alice", user: "alice", machines: ["lab", "main"], workspaces: ["acme"])
        let text = BugReport.redact(
            "devmachine sync --machine lab --yes; workspaces new acme --machine main; label acmes", context: context)
        XCTAssertEqual(
            text, "devmachine sync --machine <machine> --yes; workspaces new <workspace> --machine <machine>; label acmes")
    }

    func testTheCommandInTheBodyIsRedactedToo() throws {
        let context = BugReport.Context(home: "/Users/alice", user: "alice", machines: ["lab"], workspaces: [])
        var report = report(lines: [])
        report.command = "devmachine sync --machine lab --yes"
        let body = report.body(context: context)
        XCTAssertTrue(body.contains("devmachine sync --machine <machine> --yes"))
        XCTAssertFalse(body.contains(" lab "))
    }

    func testAShortUserNameIsReplacedAsAWholeWordOnly() {
        let context = BugReport.Context(home: "/Users/al", user: "al")
        let text = BugReport.redact("login al failed for al; also always alright, /Users/al/.ssh", context: context)
        XCTAssertEqual(text, "login <user> failed for <user>; also always alright, ~/.ssh")
    }

    func testALongLogIsTrimmedFromTheTopToStayUnderTheLimit() throws {
        let lines = (1...400).map { "line \($0) " + String(repeating: "x", count: 60) }
        let url = try XCTUnwrap(report(lines: lines).url(context: context))
        XCTAssertLessThanOrEqual(url.absoluteString.count, BugReport.maxURLLength)
        let body = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.contains("line 400 "))
        XCTAssertFalse(body.contains("line 1 "))
    }

    func testOnlyTheLastFortyLinesAreSent() throws {
        let lines = (1...100).map { "line \($0)" }
        let body = report(lines: lines).body(context: context, maxLines: BugReport.maxLines)
        XCTAssertTrue(body.contains("line 100"))
        XCTAssertTrue(body.contains("line 61\n"))
        XCTAssertFalse(body.contains("line 60\n"))
    }

    func testTheBodySaysWhereTheLogsAre() {
        let body = report(lines: ["boom"]).body(context: context)
        XCTAssertTrue(body.contains("Help > Logs > Save All Logs…"), body)
        XCTAssertTrue(body.contains("~/Library/Logs/Devmachine"), body)
    }
}
