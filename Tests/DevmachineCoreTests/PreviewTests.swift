import XCTest
@testable import DevmachineCore

final class PreviewInputTests: XCTestCase {
    func testABareNumberIsAPort() {
        XCTAssertEqual(PreviewInput.parse("3000"), .port(3000, path: ""))
        XCTAssertEqual(PreviewInput.parse(" 8080 "), .port(8080, path: ""))
        XCTAssertEqual(PreviewInput.parse(":5173"), .port(5173, path: ""))
    }

    func testANumberOutsideThePortRangeIsRefused() {
        XCTAssertNil(PreviewInput.parse("0"))
        XCTAssertNil(PreviewInput.parse("70000"))
        XCTAssertNil(PreviewInput.parse(""))
        XCTAssertNil(PreviewInput.parse("   "))
    }

    func testLocalhostIsAPortOnTheSessionsMachine() {
        XCTAssertEqual(PreviewInput.parse("localhost:3000"), .port(3000, path: ""))
        XCTAssertEqual(PreviewInput.parse("http://localhost:5173/admin?x=1"), .port(5173, path: "/admin?x=1"))
        XCTAssertEqual(PreviewInput.parse("127.0.0.1:4000/"), .port(4000, path: "/"))
    }

    func testLocalhostWithoutAPortIsPortEighty() {
        XCTAssertEqual(PreviewInput.parse("http://localhost"), .port(80, path: ""))
    }

    func testAHostWithoutASchemeGetsHTTPS() {
        XCTAssertEqual(PreviewInput.parse("app.example.com"), .url(URL(string: "https://app.example.com")!))
        XCTAssertEqual(PreviewInput.parse("example.com/docs"), .url(URL(string: "https://example.com/docs")!))
    }

    func testAnHTTPURLIsKeptAsTyped() {
        XCTAssertEqual(PreviewInput.parse("http://100.64.0.5:3000"), .url(URL(string: "http://100.64.0.5:3000")!))
        XCTAssertEqual(PreviewInput.parse("https://example.com"), .url(URL(string: "https://example.com")!))
    }

    func testOtherSchemesAreRefused() {
        XCTAssertNil(PreviewInput.parse("file:///etc/passwd"))
        XCTAssertNil(PreviewInput.parse("javascript:alert(1)"))
        XCTAssertNil(PreviewInput.parse("data:text/html,hi"))
        XCTAssertNil(PreviewInput.parse("ftp://example.com"))
        XCTAssertNil(PreviewInput.parse("not a url"))
    }
}

final class PreviewURLPolicyTests: XCTestCase {
    func testWebSchemesAreAllowed() {
        XCTAssertTrue(PreviewURLPolicy.allows(URL(string: "http://localhost:3000")!))
        XCTAssertTrue(PreviewURLPolicy.allows(URL(string: "https://example.com")!))
        XCTAssertTrue(PreviewURLPolicy.allows(URL(string: "HTTPS://example.com")!))
        XCTAssertTrue(PreviewURLPolicy.allows(URL(string: "about:blank")!))
    }

    func testEverythingElseIsBlocked() {
        for raw in ["file:///etc/hosts", "javascript:alert(1)", "data:text/html,x", "mailto:alice@example.com",
                    "ftp://example.com", "vscode://file/x", "about:config"] {
            XCTAssertFalse(PreviewURLPolicy.allows(URL(string: raw)!), raw)
        }
    }
}

final class LinkRoutingTests: XCTestCase {
    func testThePreferenceDecides() {
        XCTAssertEqual(LinkRouting.destination(preference: .inApp, inverted: false), .inApp)
        XCTAssertEqual(LinkRouting.destination(preference: .defaultBrowser, inverted: false), .defaultBrowser)
    }

    func testOptionClickDoesTheOppositeOnce() {
        XCTAssertEqual(LinkRouting.destination(preference: .inApp, inverted: true), .defaultBrowser)
        XCTAssertEqual(LinkRouting.destination(preference: .defaultBrowser, inverted: true), .inApp)
    }

    func testANonWebLinkAlwaysGoesToTheSystem() {
        XCTAssertEqual(
            LinkRouting.destination(for: URL(string: "mailto:alice@example.com")!, preference: .inApp, inverted: false),
            .defaultBrowser)
        XCTAssertEqual(
            LinkRouting.destination(for: URL(string: "https://example.com")!, preference: .inApp, inverted: false),
            .inApp)
    }
}

final class PreviewTargetsTests: XCTestCase {
    private let sites = [
        ExposedSite(host: "app.acme.example.com", port: 3000, workspace: "acme", status: .published),
        ExposedSite(host: "beta.example.com", port: 4000, workspace: "beta", status: .published),
        ExposedSite(host: "api.acme.example.com", port: 8080, workspace: nil, status: .unmanaged),
    ]
    private let ports = [
        PortOwner(port: 5173, owner: "acme"),
        PortOwner(port: 3000, owner: "acme"),
        PortOwner(port: 8080, owner: "acme"),
        PortOwner(port: 5432, owner: "acme"),
        PortOwner(port: 4000, owner: "beta"),
        PortOwner(port: 9000, owner: nil),
    ]

    func testARemoteWorkspaceListsItsOwnSitesThenItsOwnPorts() {
        let targets = PreviewTargets.remote(
            workspace: "acme", user: "acme", sites: sites, ports: ports, containers: [])
        XCTAssertEqual(targets.map(\.kind), [
            .site(host: "api.acme.example.com"),
            .site(host: "app.acme.example.com"),
            .port(3000),
            .port(5173),
            .port(8080),
        ])
    }

    func testAPortIsLabelledByWhatUsuallyListensThere() {
        let targets = PreviewTargets.remote(
            workspace: "acme", user: "acme", sites: [], ports: ports, containers: [])
        XCTAssertEqual(targets.map(\.title), ["3000", "5173", "8080"])
        XCTAssertEqual(targets.map(\.label), ["web", "vite", "http"])
    }

    func testAnUnknownPortTakesTheOnlyContainerOfItsOwner() {
        let targets = PreviewTargets.remote(
            workspace: "acme", user: "acme", sites: [], ports: [PortOwner(port: 7001, owner: "acme")],
            containers: [ContainerStat(name: "shop", memUsedBytes: 1, memLimitBytes: 1, cpuPercent: 0, owner: "acme")])
        XCTAssertEqual(targets.first?.label, "shop")
    }

    func testASiteOpensItsHTTPSAddress() {
        let site = PreviewTargets.remote(
            workspace: "acme", user: "acme", sites: sites, ports: ports, containers: []).first
        XCTAssertEqual(site?.siteURL, URL(string: "https://api.acme.example.com"))
        XCTAssertEqual(site?.label, "8080")
    }

    func testTheLocalListIsWhatThisMacListensOn() {
        let targets = PreviewTargets.local([
            ListeningPort(port: 5173, command: "node"),
            ListeningPort(port: 4567, command: "ruby"),
        ])
        XCTAssertEqual(targets.map(\.kind), [.port(4567), .port(5173)])
        XCTAssertEqual(targets.map(\.label), ["ruby", "vite"])
    }
}

final class ListeningPortsParserTests: XCTestCase {
    func testReadsLsofFieldOutput() {
        let output = """
        p501
        cnode
        f23
        n*:5173
        f24
        n[::1]:5173
        p777
        cruby
        f9
        n127.0.0.1:4567
        p900
        cControlCe
        f4
        n*:7000
        p901
        cpostgres
        f5
        n127.0.0.1:5432
        p902
        cnode
        f6
        n127.0.0.1:61234
        """
        XCTAssertEqual(ListeningPortsParser.parse(output), [
            ListeningPort(port: 4567, command: "ruby"),
            ListeningPort(port: 5173, command: "node"),
        ])
    }

    func testEmptyOutputIsNothing() {
        XCTAssertEqual(ListeningPortsParser.parse(""), [])
    }
}

final class TunnelPortPickerTests: XCTestCase {
    func testTheRemotePortWhenItIsFreeHere() {
        XCTAssertEqual(TunnelPortPicker.pick(preferred: 3000, isFree: { _ in true }, freePort: { 55000 }), 3000)
    }

    func testAFreePortWhenTheRemoteOneIsTakenHere() {
        XCTAssertEqual(TunnelPortPicker.pick(preferred: 3000, isFree: { $0 != 3000 }, freePort: { 55000 }), 55000)
    }

    func testNothingWhenNoPortIsFree() {
        XCTAssertNil(TunnelPortPicker.pick(preferred: 3000, isFree: { _ in false }, freePort: { nil }))
    }

    func testAPrivilegedPortIsNeverAskedFor() {
        XCTAssertEqual(TunnelPortPicker.pick(preferred: 80, isFree: { _ in true }, freePort: { 55001 }), 55001)
    }
}
