import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class DNSProviderSetupCardTests: XCTestCase {
    private let packages = [
        CLIPackage(name: "cloudflare", scope: "machine", installedOn: [], summary: "DNS zones on Cloudflare."),
        CLIPackage(name: "hostinger", scope: "machine", installedOn: ["machine box"], summary: "DNS zones on Hostinger."),
    ]

    func testEveryStateHasATitleThatNamesTheMachine() {
        let states: [DNSSetupState] = [
            .noneInstalled,
            .notSynced(provider: "hostinger", problem: .notApplied),
            .notSynced(provider: "hostinger", problem: .providerError("no token")),
            .notSynced(provider: "hostinger", problem: .noZones),
            .working(.sync),
            .failed(.sync, cause: "x", details: "y"),
        ]
        for state in states {
            let title = DNSSetupContent.title(state, machine: "box", provider: "hostinger")
            XCTAssertFalse(title.isEmpty, "\(state)")
        }
        XCTAssertEqual(DNSSetupContent.title(.noneInstalled, machine: "box", provider: nil), "box can't create DNS records")
        XCTAssertEqual(DNSSetupContent.title(.ready, machine: "box", provider: nil), "")
    }

    func testAProviderErrorIsQuotedAndTheHandMadeRecordIsExplained() {
        let body = DNSSetupContent.body(.providerError("HOSTINGER_API_TOKEN is not set"), provider: "hostinger")
        XCTAssertTrue(body.contains("HOSTINGER_API_TOKEN is not set"))
        XCTAssertTrue(body.contains("by hand"))
    }

    func testOnlyHostingerIsToldAboutTheZonesSetting() {
        XCTAssertTrue(DNSSetupContent.body(.noZones, provider: "hostinger").contains("Domains portfolio"))
        XCTAssertFalse(DNSSetupContent.body(.noZones, provider: "cloudflare").contains("Domains portfolio"))
    }

    func testTheConfirmationsNameTheZonesTheCLIWillSet() {
        XCTAssertTrue(DNSSetupContent.installConfirmation("hostinger", machine: "box", zones: ["example.com"])
            .contains("sets the zones it may manage to example.com"))
        XCTAssertFalse(DNSSetupContent.installConfirmation("hostinger", machine: "box").contains("zones"))
        XCTAssertTrue(DNSSetupContent.zonesConfirmation("hostinger", machine: "box", zones: ["example.com", "example.net"])
            .contains("example.com, example.net"))
    }

    func testAnOlderCLIIsToldWhichVersionSetsTheZones() {
        XCTAssertTrue(DNSSetupContent.zonesGap.contains("0.7.27"))
        XCTAssertTrue(DNSSetupContent.zonesGap.contains("config.yml"))
    }

    func testARunningSyncPointsToTheCornerInsteadOfALog() {
        XCTAssertTrue(DNSSetupContent.syncingBody.contains("corner"))
    }

    func testTheCardRendersInEveryStateAndNotWhenReady() throws {
        let cases: [(answers: [DNSProviderAnswer]?, job: DNSSetupJob?, declared: Bool, shows: Bool)] = [
            ([], nil, false, true),
            ([], nil, true, true),
            ([DNSProviderAnswer(name: "hostinger", zones: [], error: "no token")], nil, true, true),
            ([DNSProviderAnswer(name: "hostinger", zones: [], error: nil)], nil, true, true),
            ([], .running(.sync), true, true),
            ([], .failed(.sync, cause: "exit status 2", details: "fatal"), true, true),
            ([DNSProviderAnswer(name: "hostinger", zones: ["example.com"], error: nil)], nil, true, false),
        ]
        for item in cases {
            let setup = DNSSetupStore(
                service: CaddyService(cli: DevmachineCLI(executable: "/fake", runner: DemoMode.runner)))
            let listed = item.declared ? packages : packages.map {
                CLIPackage(name: $0.name, scope: $0.scope, installedOn: [], summary: $0.summary)
            }
            setup.seedDemo(machine: "box", packages: listed, answers: item.answers, job: item.job)
            XCTAssertEqual(setup.state.showsCard, item.shows)

            guard item.shows else { continue }
            let view = DNSProviderSetupCard(setup: setup, domain: "example.com").frame(width: 760)
            let image = try XCTUnwrap(ImageRenderer(content: view).nsImage)
            XCTAssertGreaterThan(image.size.height, 60, "\(setup.state)")
        }
    }
}
