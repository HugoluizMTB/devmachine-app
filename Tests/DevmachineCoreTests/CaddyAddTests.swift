import XCTest
@testable import DevmachineCore

private let baseDomain = "example.com"
private let publicIP = "203.0.113.7"

private func subdomain(label: String, port: Int) -> SubdomainRequest {
    SubdomainRequest.subdomain(label: label, port: port, baseDomain: baseDomain)
}

final class CaddyAddTests: XCTestCase {
    func testValidateAcceptsGoodLabelAndPort() throws {
        XCTAssertNoThrow(try CaddyAdd.validate(subdomain(label: "staging-x", port: 8110)))
    }

    func testValidateRejectsBadLabel() {
        XCTAssertThrowsError(try CaddyAdd.validate(subdomain(label: "Bad_Label", port: 80))) { error in
            XCTAssertEqual(error as? CaddyAddError, .invalidLabel)
        }
    }

    func testValidateRejectsPortTooLow() {
        XCTAssertThrowsError(try CaddyAdd.validate(subdomain(label: "ok", port: 0))) { error in
            XCTAssertEqual(error as? CaddyAddError, .invalidPort)
        }
    }

    func testValidateRejectsPortTooHigh() {
        XCTAssertThrowsError(try CaddyAdd.validate(subdomain(label: "ok", port: 70000))) { error in
            XCTAssertEqual(error as? CaddyAddError, .invalidPort)
        }
    }

    func testValidateRejectsHostWithNoDot() {
        let req = SubdomainRequest(host: "nodothost", port: 8080, managedDNS: false)
        XCTAssertThrowsError(try CaddyAdd.validate(req)) { error in
            XCTAssertEqual(error as? CaddyAddError, .invalidLabel)
        }
    }

    func testValidateRejectsUppercaseHost() {
        let req = SubdomainRequest(host: "App.example.net", port: 8080, managedDNS: false)
        XCTAssertThrowsError(try CaddyAdd.validate(req)) { error in
            XCTAssertEqual(error as? CaddyAddError, .invalidLabel)
        }
    }

    func testAppendBlockOnTrailingNewline() throws {
        let caddyfile = """
        example.com {
            reverse_proxy 127.0.0.1:4000
        }
        """ + "\n"
        let req = subdomain(label: "staging-x", port: 8110)
        let result = try CaddyAdd.appendBlock(to: caddyfile, req: req)
        let expected = """
        example.com {
            reverse_proxy 127.0.0.1:4000
        }

        staging-x.example.com {
            reverse_proxy 127.0.0.1:8110
        }
        """ + "\n"
        XCTAssertEqual(result, expected)
    }

    func testAppendBlockThrowsWhenAlreadyExists() throws {
        let caddyfile = """
        staging-x.example.com {
            reverse_proxy 127.0.0.1:8110
        }
        """ + "\n"
        let req = subdomain(label: "staging-x", port: 9000)
        XCTAssertThrowsError(try CaddyAdd.appendBlock(to: caddyfile, req: req)) { error in
            XCTAssertEqual(error as? CaddyAddError, .alreadyExists)
        }
    }

    func testAppendBlockNormalizesDoubleTrailingNewline() throws {
        let caddyfile = """
        example.com {
            reverse_proxy 127.0.0.1:4000
        }
        """ + "\n\n"
        let req = subdomain(label: "staging-x", port: 8110)
        let result = try CaddyAdd.appendBlock(to: caddyfile, req: req)
        let expected = """
        example.com {
            reverse_proxy 127.0.0.1:4000
        }

        staging-x.example.com {
            reverse_proxy 127.0.0.1:8110
        }
        """ + "\n"
        XCTAssertEqual(result, expected)
    }

    func testAppendBlockNormalizesNoTrailingNewline() throws {
        let caddyfile = """
        example.com {
            reverse_proxy 127.0.0.1:4000
        }
        """
        let req = subdomain(label: "staging-x", port: 8110)
        let result = try CaddyAdd.appendBlock(to: caddyfile, req: req)
        let expected = """
        example.com {
            reverse_proxy 127.0.0.1:4000
        }

        staging-x.example.com {
            reverse_proxy 127.0.0.1:8110
        }
        """ + "\n"
        XCTAssertEqual(result, expected)
    }

    func testAppendBlockExternalDomain() throws {
        let req = SubdomainRequest(host: "app.example.net", port: 8201, managedDNS: false)
        let result = try CaddyAdd.appendBlock(to: "", req: req)
        let expected = "app.example.net {\n    reverse_proxy 127.0.0.1:8201\n}\n"
        XCTAssertEqual(result, expected)
    }

    func testDnsBodyExactString() {
        let req = subdomain(label: "staging-x", port: 8110)
        let expected = "{\"overwrite\":false,\"zone\":[{\"name\":\"staging-x\",\"type\":\"A\",\"ttl\":14400,\"records\":[{\"content\":\"203.0.113.7\"}]}]}"
        XCTAssertEqual(CaddyAdd.dnsBody(req, baseDomain: baseDomain, ip: publicIP), expected)
    }

    func testHostingerCurlContainsExpectedPieces() {
        let req = subdomain(label: "staging-x", port: 8110)
        let result = CaddyAdd.hostingerCurl(req, baseDomain: baseDomain, ip: publicIP)
        XCTAssertTrue(result.contains("https://developers.hostinger.com/api/dns/v1/zones/example.com"))
        XCTAssertTrue(result.contains("$HOSTINGER_API_TOKEN"))
        XCTAssertTrue(result.contains(CaddyAdd.dnsBody(req, baseDomain: baseDomain, ip: publicIP)))
    }

    func testAnsibleApplyExactString() {
        XCTAssertEqual(CaddyAdd.ansibleApply(), "cd ansible && ansible-playbook -i inventory.ini site.yml --tags caddy")
    }

    func testIsCleanAndSyncedTrue() {
        XCTAssertTrue(CaddyAdd.isCleanAndSynced(porcelain: "", localHead: "abc123", remoteHead: "abc123"))
    }

    func testIsCleanAndSyncedFalseWhenDirty() {
        XCTAssertFalse(CaddyAdd.isCleanAndSynced(porcelain: " M file.txt", localHead: "abc123", remoteHead: "abc123"))
    }

    func testIsCleanAndSyncedFalseWhenHeadsDiffer() {
        XCTAssertFalse(CaddyAdd.isCleanAndSynced(porcelain: "", localHead: "abc123", remoteHead: "def456"))
    }

    func testHostingRowExactString() {
        let req = subdomain(label: "staging-x", port: 8110)
        let expected = "| `staging-x.example.com` | `127.0.0.1:8110` | ⏳ pending |"
        XCTAssertEqual(CaddyAdd.hostingRow(req), expected)
    }

    func testDnsBodyAndCurlFollowTheGivenDomainAndIP() {
        let req = SubdomainRequest.subdomain(label: "app", port: 3000, baseDomain: "example.net")
        XCTAssertEqual(req.host, "app.example.net")

        let body = CaddyAdd.dnsBody(req, baseDomain: "example.net", ip: "10.0.0.9")
        XCTAssertTrue(body.contains("\"name\":\"app\""))
        XCTAssertTrue(body.contains("\"content\":\"10.0.0.9\""))

        let curl = CaddyAdd.hostingerCurl(req, baseDomain: "example.net", ip: "10.0.0.9")
        XCTAssertTrue(curl.contains("https://developers.hostinger.com/api/dns/v1/zones/example.net"))
    }

    func testHostingRowExternalContainsExternalDNS() {
        let req = SubdomainRequest(host: "app.example.net", port: 8201, managedDNS: false)
        XCTAssertTrue(CaddyAdd.hostingRow(req).contains("external DNS"))
    }
}
