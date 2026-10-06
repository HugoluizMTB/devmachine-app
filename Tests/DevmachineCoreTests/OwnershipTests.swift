import XCTest
@testable import DevmachineCore

final class OwnershipTests: XCTestCase {
    func testTheHomeFolderNamesTheOwner() {
        XCTAssertEqual(Ownership.user(fromHome: "/home/acme/dev/site"), "acme")
        XCTAssertEqual(Ownership.user(fromHome: "/home/acme"), "acme")
        XCTAssertNil(Ownership.user(fromHome: "/opt/stack"))
        XCTAssertNil(Ownership.user(fromHome: "/home/"))
        XCTAssertNil(Ownership.user(fromHome: ""))
    }

    func testOnAMacTheHomeIsUnderUsers() {
        XCTAssertEqual(Ownership.user(fromHome: "/Users/acme/dev/site", system: "Darwin"), "acme")
        XCTAssertNil(Ownership.user(fromHome: "/home/acme/dev/site", system: "Darwin"))
        XCTAssertNil(Ownership.user(fromHome: "/Users/acme/dev/site", system: "Linux"))
    }

    func testAContainerNamedAfterAUserCountsAsTheirs() {
        let users: Set<String> = ["acme", "globex"]
        XCTAssertEqual(
            Ownership.owner(ofContainer: "acme-pg", labelled: nil, knownUsers: users), "acme")
        XCTAssertEqual(
            Ownership.owner(ofContainer: "globex", labelled: nil, knownUsers: users), "globex")
        XCTAssertNil(
            Ownership.owner(ofContainer: "buildkit-0", labelled: nil, knownUsers: users))
        // A name that only looks like a user is not one.
        XCTAssertNil(
            Ownership.owner(ofContainer: "acmecorp-web", labelled: nil, knownUsers: users))
    }

    func testTheLabelWinsOverTheName() {
        XCTAssertEqual(
            Ownership.owner(ofContainer: "acme-pg", labelled: "globex", knownUsers: ["acme"]),
            "globex")
    }

    func testTheSitePortIsReadFromItsTarget() {
        XCTAssertEqual(CaddySiteOwnership.port(of: "127.0.0.1:8810"), 8810)
        XCTAssertEqual(CaddySiteOwnership.port(of: "localhost:7000"), 7000)
        XCTAssertNil(CaddySiteOwnership.port(of: "https://example.com/{uri}"))
    }
}
