import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class DNSProviderFormTests: XCTestCase {
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

    func testTheConfirmationsForAddAndSaveAndRemoveSayWhatHappens() {
        let add = DNSSetupContent.addAndSaveConfirmation("hostinger", machine: "box", zones: [])
        XCTAssertTrue(add.hasPrefix(DNSSetupContent.installConfirmation("hostinger", machine: "box")))
        XCTAssertTrue(add.hasSuffix(" Then it syncs hostinger alone on box and delivers the token."))
        let remove = DNSSetupContent.removeConfirmation("hostinger", machine: "box")
        XCTAssertTrue(remove.contains("runs a full sync on box"))
        XCTAssertTrue(remove.contains("/opt/devmachine/roles/hostinger"))
    }

    func testButtonsPerState() {
        XCTAssertEqual(DNSProviderForm.actions(for: .notInstalled, canRunSync: true), [.addAndSave])
        XCTAssertEqual(DNSProviderForm.actions(for: .notSynced, canRunSync: true), [.saveToken, .pushAgain, .remove])
        XCTAssertEqual(
            DNSProviderForm.actions(for: .tokenMissing(error: "e"), canRunSync: true), [.saveToken, .pushAgain, .remove])
        XCTAssertEqual(DNSProviderForm.actions(for: .noZones, canRunSync: true), [.saveToken, .pushAgain, .remove])
        XCTAssertEqual(DNSProviderForm.actions(for: .ready, canRunSync: true), [.saveToken, .pushAgain, .remove])
        XCTAssertEqual(DNSProviderForm.actions(for: .working(.sync), canRunSync: true), [])
        XCTAssertEqual(DNSProviderForm.actions(for: .failed(.sync, cause: "x", details: "y"), canRunSync: true), [])
        XCTAssertEqual(DNSProviderForm.actions(for: .ready, canRunSync: false), [.saveToken])
        XCTAssertEqual(DNSProviderForm.actions(for: .notInstalled, canRunSync: false), [.addAndSave])
    }

    func testAddAndSaveNeedsAUsableTokenAndValidZones() {
        XCTAssertTrue(DNSProviderForm.canSubmit(token: "  tok-1 ", zones: ""))
        XCTAssertFalse(DNSProviderForm.canSubmit(token: "   ", zones: ""))
        XCTAssertFalse(DNSProviderForm.canSubmit(token: "one\ntwo", zones: ""))
        XCTAssertFalse(DNSProviderForm.canSubmit(token: "tok-1", zones: "example.com]: x"))
    }

    func testTheFormRendersInEveryState() throws {
        let cases: [(answers: [DNSProviderAnswer]?, job: DNSSetupJob?, declared: Bool)] = [
            ([], nil, false),
            ([], nil, true),
            ([DNSProviderAnswer(name: "hostinger", zones: [], error: "no token")], nil, true),
            ([DNSProviderAnswer(name: "hostinger", zones: [], error: nil)], nil, true),
            ([], .running(.sync), true),
            ([], .failed(.sync, cause: "exit status 2", details: "fatal"), true),
            ([DNSProviderAnswer(name: "hostinger", zones: ["example.com"], error: nil)], nil, true),
        ]
        for item in cases {
            let setup = DNSSetupStore(
                service: CaddyService(cli: DevmachineCLI(executable: "/fake", runner: DemoMode.runner)))
            let listed = item.declared ? packages : packages.map {
                CLIPackage(name: $0.name, scope: $0.scope, installedOn: [], summary: $0.summary)
            }
            setup.seedDemo(machine: "box", packages: listed, answers: item.answers, job: item.job, package: "hostinger")

            let view = DNSProviderForm(setup: setup, package: "hostinger", domain: "example.com").frame(width: 760)
            let image = try XCTUnwrap(ImageRenderer(content: view).nsImage)
            XCTAssertGreaterThan(image.size.height, 15, "\(setup.stateOf("hostinger"))")
        }
    }
}
