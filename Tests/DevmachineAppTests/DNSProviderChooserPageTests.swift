import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

private final class SilentRunner: CommandRunner, @unchecked Sendable {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        ("", "", 0)
    }
}

@MainActor
final class DNSProviderChooserPageTests: XCTestCase {
    func testOneCardPerCatalogPackageInCatalogOrder() {
        let catalog = [
            CLIPackage(name: "cloudflare", scope: "machine", installedOn: [], summary: "DNS zones on Cloudflare."),
            CLIPackage(name: "godaddy", scope: "machine", installedOn: [], summary: "DNS zones on GoDaddy."),
            CLIPackage(name: "hostinger", scope: "machine", installedOn: [], summary: "DNS zones on Hostinger."),
        ]
        let cards = DNSProviderChooserPage.cards(catalog: catalog)
        XCTAssertEqual(cards.map(\.name), ["cloudflare", "godaddy", "hostinger"])
        XCTAssertEqual(cards.map(\.detail), ["DNS zones on Cloudflare.", "DNS zones on GoDaddy.", "DNS zones on Hostinger."])
        XCTAssertEqual(cards.map(\.systemImage), ["cloud.fill", "g.square.fill", "h.square.fill"])
        XCTAssertEqual(DNSProviderChooserPage.symbol(for: "desec"), "globe")
    }

    func testADeclaredProviderThatDoesNotAnswerOpensSelected() {
        XCTAssertEqual(
            DNSProviderChooserPage.preselected(state: .notSynced(provider: "hostinger", problem: .notApplied), initial: nil),
            "hostinger")
        XCTAssertNil(DNSProviderChooserPage.preselected(state: .noneInstalled, initial: nil))
        XCTAssertEqual(DNSProviderChooserPage.preselected(state: .noneInstalled, initial: "godaddy"), "godaddy")
    }

    func testTheBarNamesTheMachine() {
        XCTAssertEqual(
            DNSSetupContent.handMadeBar("box"),
            "No DNS provider answers for box: publishing a port prints the record for you to create by hand.")
    }

    func testAnEmptyCatalogRendersTheCommandBlock() throws {
        let setup = DNSSetupStore(service: CaddyService(cli: DevmachineCLI(executable: "/fake", runner: DemoMode.runner)))
        setup.seedDemo(machine: "box", packages: [], answers: [])
        XCTAssertEqual(DNSProviderChooserPage.cards(catalog: setup.catalog), [])
        let view = DNSProviderChooserPage(setup: setup)
            .environmentObject(AppModel(store: SessionStore(runner: SilentRunner())))
            .frame(width: 900, height: 600)
        XCTAssertEqual(try XCTUnwrap(ImageRenderer(content: view).nsImage).size.height, 600)
    }
}
