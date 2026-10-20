import XCTest
@testable import DevmachineCore

final class LogRedactorTests: XCTestCase {
    private func assertHidden(_ secret: String, in text: String, file: StaticString = #filePath, line: UInt = #line) {
        let redacted = LogRedactor.redact(text)
        XCTAssertFalse(redacted.contains(secret), "\(secret) leaked in \(redacted)", file: file, line: line)
        XCTAssertTrue(redacted.contains(LogRedactor.mask), redacted, file: file, line: line)
    }

    func testGitHubTokensAreHidden() {
        assertHidden("ghp_FAKEfakeFAKEfakeFAKE0123", in: "cloning with ghp_FAKEfakeFAKEfakeFAKE0123 now")
        assertHidden("gho_FAKEfakeFAKEfakeFAKE0123", in: "oauth gho_FAKEfakeFAKEfakeFAKE0123")
        assertHidden("github_pat_FAKE0fake1FAKE2fake3", in: "pat github_pat_FAKE0fake1FAKE2fake3 used")
    }

    func testAPIKeysAndTailscaleKeysAreHidden() {
        assertHidden("sk-ant-FAKEfakeFAKEfake0123", in: "key sk-ant-FAKEfakeFAKEfake0123")
        assertHidden("sk-proj-FAKEfakeFAKEfake0123", in: "key sk-proj-FAKEfakeFAKEfake0123.")
        assertHidden("tskey-auth-FAKEfake0123", in: "tailscale up --authkey tskey-auth-FAKEfake0123")
    }

    func testTokenPrefixesStaySoTheKindCanBeRead() {
        XCTAssertEqual(LogRedactor.redact("ghp_FAKEfakeFAKEfakeFAKE0123"), "ghp_***")
        XCTAssertEqual(LogRedactor.redact("tskey-auth-FAKE0123"), "tskey-***")
    }

    func testPasswordsInsideAddressesAreHidden() {
        XCTAssertEqual(
            LogRedactor.redact("cloning https://alice:fake-url-pw@git.example.com/acme/dash.git"),
            "cloning https://alice:***@git.example.com/acme/dash.git")
    }

    func testBearerAndAuthorizationHeadersAreHidden() {
        assertHidden("FAKEtoken0123", in: "curl -H 'Authorization: Bearer FAKEtoken0123' https://example.com")
        assertHidden("FAKEbasic0123", in: "Authorization: Basic FAKEbasic0123")
        assertHidden("FAKEraw0123", in: "authorization: FAKEraw0123")
        assertHidden("FAKEbearer0123", in: "sent bearer FAKEbearer0123")
    }

    func testPrivateKeyBlocksAreHidden() {
        let text = """
            before
            -----BEGIN OPENSSH PRIVATE KEY-----
            FAKEKEYMATERIALFAKEKEYMATERIAL
            -----END OPENSSH PRIVATE KEY-----
            after
            """
        let redacted = LogRedactor.redact(text)
        XCTAssertFalse(redacted.contains("FAKEKEYMATERIAL"))
        XCTAssertTrue(redacted.contains("before"))
        XCTAssertTrue(redacted.contains("after"))
        assertHidden("FAKECUTKEY", in: "-----BEGIN RSA PRIVATE KEY-----\nFAKECUTKEY")
    }

    func testSensitiveNameValuePairsAreHidden() {
        assertHidden("hunter2", in: "DB_PASSWORD=hunter2 ready")
        assertHidden("fake-secret", in: "client_secret=fake-secret")
        assertHidden("abc123", in: "api-key=abc123")
        assertHidden("quoted value", in: #"GITHUB_TOKEN="quoted value" next"#)
        assertHidden("fake-auth", in: "OAUTH_CLIENT=fake-auth")
        assertHidden("fake-pk", in: "private_key=fake-pk")
        assertHidden("fake-pw", in: "passwd=fake-pw")
    }

    func testSensitiveJSONValuesAreHidden() {
        let text = #"{"name": "acme", "apiKey": "fake-json-key", "password":"fake-json-pw", "auth_token" : "x\"y"}"#
        let redacted = LogRedactor.redact(text)
        for leaked in ["fake-json-key", "fake-json-pw", #"x\"y"#] {
            XCTAssertFalse(redacted.contains(leaked), redacted)
        }
        XCTAssertTrue(redacted.contains(#""name": "acme""#), redacted)
        XCTAssertTrue(redacted.contains(#""apiKey": "***""#), redacted)
    }

    func testEnvFileLinesAreHidden() {
        let text = """
            DATABASE_URL=postgres://alice:fake@db.example.com/app
            export FEATURE_FLAG=on
            plain sentence with SIZE=3 inside
            """
        let redacted = LogRedactor.redact(text)
        XCTAssertFalse(redacted.contains("postgres://"), redacted)
        XCTAssertTrue(redacted.contains("DATABASE_URL=***"), redacted)
        XCTAssertTrue(redacted.contains("export FEATURE_FLAG=***"), redacted)
        XCTAssertTrue(redacted.contains("plain sentence with SIZE=3 inside"), redacted)
    }

    func testAddressesHostsNamesAndPathsSurvive() {
        let text = "ssh alice@203.0.113.10 via 100.64.0.7 host box.example.com machine main "
            + "workspace acme user bob path /Users/alice/.config/devmachine exit 255"
        XCTAssertEqual(LogRedactor.redact(text), text)
    }

    func testSecretsSetValueInArgumentsIsHidden() {
        let args = LogRedactor.redact(arguments: ["secrets", "set", "CLOUDFLARE_API_TOKEN", "fake-value"])
        XCTAssertEqual(args, ["secrets", "set", "CLOUDFLARE_API_TOKEN", "***"])
        XCTAssertEqual(
            LogRedactor.redact(arguments: ["--format", "json", "secrets", "set", "NAME"]),
            ["--format", "json", "secrets", "set", "NAME"])
        XCTAssertEqual(
            LogRedactor.redact(arguments: ["secrets", "set", "NAME", "--stdin"]), ["secrets", "set", "NAME", "--stdin"])
    }

    func testSensitiveFlagsInArgumentsAreHidden() {
        XCTAssertEqual(
            LogRedactor.redact(arguments: ["login", "--token", "fake-tok", "--machine", "main"]),
            ["login", "--token", "***", "--machine", "main"])
        XCTAssertEqual(LogRedactor.redact(arguments: ["--password=fake-pw"]), ["--password=***"])
        XCTAssertEqual(LogRedactor.redact(arguments: ["env", "API_KEY=fake"]), ["env", "API_KEY=***"])
    }

    func testArgumentsKeepNamesAndAddresses() {
        let args = ["machines", "add", "main", "--host", "203.0.113.10", "--user", "alice", "--workspace", "acme"]
        XCTAssertEqual(LogRedactor.redact(arguments: args), args)
    }

    func testLongArgumentsAreCut() {
        let long = String(repeating: "a", count: 1000)
        let cut = LogRedactor.redact(arguments: [long])[0]
        XCTAssertLessThan(cut.count, 400)
        XCTAssertTrue(cut.hasSuffix("…"))
    }
}
