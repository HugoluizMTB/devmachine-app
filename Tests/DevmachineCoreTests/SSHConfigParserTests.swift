import XCTest
@testable import DevmachineCore

final class SSHConfigParserTests: XCTestCase {
    func testCollectsContextAliases() {
        let cfg = """
        Host devmachine
            HostName 100.64.0.1
            User root

        Host acme-devmachine
            HostName 100.64.0.1
            User acme

        Host delta-staging-devmachine
            User delta-staging

        Host acme-devmachine-pub
            HostName 203.0.113.7
        """
        let ws = SSHConfigParser.parse(cfg)
        XCTAssertEqual(ws, [
            Workspace(name: "acme", alias: "acme-devmachine"),
            Workspace(name: "delta-staging", alias: "delta-staging-devmachine")
        ])
    }

    func testIgnoresBareAndPubHosts() {
        let ws = SSHConfigParser.parse("Host devmachine devmachine-pub\n")
        XCTAssertTrue(ws.isEmpty)
    }

    func testMultipleAliasesOnTheSameLine() {
        let ws = SSHConfigParser.parse("Host dev-devmachine beta-devmachine\n")
        XCTAssertEqual(ws.map(\.name), ["dev", "beta"])
    }

    func testAcceptsTabAfterHost() {
        let ws = SSHConfigParser.parse("Host\tacme-devmachine\n")
        XCTAssertEqual(ws, [Workspace(name: "acme", alias: "acme-devmachine")])
    }

    func testIgnoresWildcard() {
        let ws = SSHConfigParser.parse("Host devmachine *-devmachine\n")
        XCTAssertTrue(ws.isEmpty)
    }

    func testUsesTheGivenSuffix() {
        let cfg = "Host acme-devmachine\nHost web-box\nHost api-box\n"
        let ws = SSHConfigParser.parse(cfg, suffix: "-box")
        XCTAssertEqual(ws, [
            Workspace(name: "web", alias: "web-box"),
            Workspace(name: "api", alias: "api-box")
        ])
    }

    func testHostTokensCollectsEveryAlias() {
        let cfg = "Host devmachine devmachine-pub\nHostName 1.2.3.4\nHost\tacme-devmachine\n"
        XCTAssertEqual(SSHConfigParser.hostTokens(cfg), ["devmachine", "devmachine-pub", "acme-devmachine"])
    }

    func testHostnameFromSSHDump() {
        let dump = "user root\nhostname 203.0.113.7\nport 22\n"
        XCTAssertEqual(SSHConfigParser.hostname(inSSHDump: dump), "203.0.113.7")
    }

    func testHostnameMissingFromSSHDump() {
        XCTAssertNil(SSHConfigParser.hostname(inSSHDump: "user root\nport 22\n"))
    }
}
