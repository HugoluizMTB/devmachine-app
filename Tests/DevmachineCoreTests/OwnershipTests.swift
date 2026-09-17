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

    func testTheSupabaseCLIFolderCountsAsAnOwnerToo() {
        let owners = Ownership.containerOwners(
            "supabase_studio_site|/home/acme/dev/site|0.0.0.0:54363->3000/tcp")
        XCTAssertEqual(owners["supabase_studio_site"], "acme")
    }

    func testContainerOwnersComeFromTheComposeFolder() {
        let owners = Ownership.containerOwners("""
        site-web|/home/acme/dev/site|0.0.0.0:8110->80/tcp
        loose-box||
        system-box|/opt/thing|
        """)
        XCTAssertEqual(owners, ["site-web": "acme"])
    }

    func testPublishedPortsReadBothFamilies() {
        XCTAssertEqual(
            Ownership.publishedPorts("0.0.0.0:8810->80/tcp, [::]:8810->80/tcp"), [8810])
        XCTAssertEqual(Ownership.publishedPorts("127.0.0.1:8110->80/tcp"), [8110])
        XCTAssertEqual(
            Ownership.publishedPorts("0.0.0.0:9000->9000/tcp, 0.0.0.0:9001->9001/tcp"),
            [9000, 9001])
        XCTAssertTrue(Ownership.publishedPorts("8080/tcp").isEmpty)
        // Docker folds a run of ports into one mapping.
        XCTAssertEqual(
            Ownership.publishedPorts("0.0.0.0:9000-9001->9000-9001/tcp"), [9000, 9001])
    }

    func testAContainerOwnsItsPublishedPort() {
        let owners = Ownership.portOwners("""
        site-web|/home/acme/dev/site|127.0.0.1:8110->80/tcp
        @@LISTENERS@@
        LISTEN 0 4096 127.0.0.1:8110 0.0.0.0:* users:(("docker-proxy",pid=99,fd=4))
        @@PROCESSES@@
        99 root
        """)
        // Docker's proxy holds the port and belongs to root; the container is
        // what the workspace owns.
        XCTAssertEqual(owners[8110], "acme")
    }

    func testAPlainProcessOwnsItsPort() {
        let owners = Ownership.portOwners("""
        @@LISTENERS@@
        LISTEN 0 511 *:7000 *:* users:(("node",pid=4242,fd=24))
        LISTEN 0 1024 127.0.0.1:3000 0.0.0.0:* users:(("ruby",pid=77,fd=5))
        @@PROCESSES@@
        4242 globex
        77 initech
        """)
        XCTAssertEqual(owners[7000], "globex")
        XCTAssertEqual(owners[3000], "initech")
    }

    func testAPortNobodyClaimsHasNoOwner() {
        let owners = Ownership.portOwners("""
        @@LISTENERS@@
        LISTEN 0 511 *:4000 *:* users:(("nginx",pid=5,fd=6))
        @@PROCESSES@@
        """)
        XCTAssertNil(owners[4000])
        XCTAssertNil(owners[9999])
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
