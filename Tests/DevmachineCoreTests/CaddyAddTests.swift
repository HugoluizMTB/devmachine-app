import XCTest
@testable import DevmachineCore

private let baseDomain = "example.com"
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

    func testSubdomainBuildsTheHostFromTheGivenDomain() {
        let req = SubdomainRequest.subdomain(label: "app", port: 3000, baseDomain: "example.net")
        XCTAssertEqual(req.host, "app.example.net")
        XCTAssertEqual(req.port, 3000)
        XCTAssertTrue(req.managedDNS)
    }
}
