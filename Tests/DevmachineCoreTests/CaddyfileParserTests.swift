import XCTest
@testable import DevmachineCore

final class CaddyfileParserTests: XCTestCase {
    private let sample = """
    # apex site
    example.com {
        reverse_proxy 127.0.0.1:4000
    }
    www.example.com {
        redir https://example.com{uri}
    }
    a.x b.x {
        reverse_proxy 127.0.0.1:9000
    }
    handle.example.com {
        handle {
            respond "ok"
        }
    }
    """

    func testParsesApexProxyBlock() {
        let sites = CaddyfileParser.parse(sample)

        XCTAssertEqual(
            sites.first { $0.address == "example.com" },
            CaddySite(address: "example.com", target: "127.0.0.1:4000", kind: "proxy")
        )
    }

    func testParsesRedirBlock() {
        let sites = CaddyfileParser.parse(sample)

        XCTAssertEqual(
            sites.first { $0.address == "www.example.com" },
            CaddySite(address: "www.example.com", target: "https://example.com{uri}", kind: "redir")
        )
    }

    func testExpandsMultiAddressBlock() {
        let sites = CaddyfileParser.parse(sample)

        XCTAssertEqual(
            sites.filter { $0.address == "a.x" || $0.address == "b.x" },
            [
                CaddySite(address: "a.x", target: "127.0.0.1:9000", kind: "proxy"),
                CaddySite(address: "b.x", target: "127.0.0.1:9000", kind: "proxy")
            ]
        )
    }

    func testExpandsCommaSeparatedAddressBlock() {
        let text = "delta.example.net, app.example.net {\n    reverse_proxy 127.0.0.1:8110\n}"

        let sites = CaddyfileParser.parse(text)

        XCTAssertEqual(sites, [
            CaddySite(address: "delta.example.net", target: "127.0.0.1:8110", kind: "proxy"),
            CaddySite(address: "app.example.net", target: "127.0.0.1:8110", kind: "proxy")
        ])
    }

    func testFallsBackToOtherKindWhenNoKnownDirectiveFound() {
        let sites = CaddyfileParser.parse(sample)

        XCTAssertEqual(
            sites.first { $0.address == "handle.example.com" },
            CaddySite(address: "handle.example.com", target: "", kind: "other")
        )
    }

    func testSkipsCommentsAndPreservesFileOrder() {
        let sites = CaddyfileParser.parse(sample)

        XCTAssertEqual(sites.map(\.address), [
            "example.com",
            "www.example.com",
            "a.x",
            "b.x",
            "handle.example.com"
        ])
    }

    func testEmptyInputProducesEmptyList() {
        XCTAssertEqual(CaddyfileParser.parse(""), [])
    }
}
