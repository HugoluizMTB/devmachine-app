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
final class DNSProvidersSettingsViewTests: XCTestCase {
    private func makeSetup() -> DNSSetupStore {
        DNSSetupStore(service: CaddyService(cli: DevmachineCLI(executable: "/fake", runner: DemoMode.runner)))
    }

    func testEveryCatalogPackageGetsARowWithItsState() {
        let setup = makeSetup()
        setup.seedDemo(
            machine: "box",
            packages: [
                CLIPackage(name: "cloudflare", scope: "machine", installedOn: ["machine box"], summary: "DNS zones on Cloudflare."),
                CLIPackage(name: "godaddy", scope: "machine", installedOn: [], summary: "DNS zones on GoDaddy."),
                CLIPackage(name: "hostinger", scope: "machine", installedOn: ["machine box"], summary: "DNS zones on Hostinger."),
            ],
            answers: [
                DNSProviderAnswer(name: "cloudflare", zones: ["example.com"], error: nil),
                DNSProviderAnswer(name: "hostinger", zones: [], error: "HOSTINGER_API_TOKEN is not set"),
            ])
        XCTAssertEqual(
            DNSProvidersSettingsView.rows(catalog: setup.catalog, stateOf: setup.stateOf),
            [
                DNSProviderRow(name: "cloudflare", label: "Ready"),
                DNSProviderRow(name: "godaddy", label: "Not installed"),
                DNSProviderRow(name: "hostinger", label: "Token missing"),
            ])
    }

    func testAnEmptyCatalogShowsTheCommandInsteadOfRows() throws {
        let setup = makeSetup()
        setup.seedDemo(machine: "box", packages: [], answers: [])
        XCTAssertEqual(DNSProvidersSettingsView.rows(catalog: setup.catalog, stateOf: setup.stateOf), [])
        let store = CaddyStore(dnsSetup: setup)
        store.show(
            machines: [CLIMachine(name: "box", isSelf: false), CLIMachine(name: "laptop", isSelf: true)],
            states: [:], selected: "box")
        let view = DNSProvidersSettingsView()
            .environmentObject(store)
            .environmentObject(AppModel(store: SessionStore(runner: SilentRunner())))
            .frame(width: 900, height: 600)
        XCTAssertEqual(try XCTUnwrap(ImageRenderer(content: view).nsImage).size.width, 900)
    }

    func testOnlyServersAreOffered() {
        XCTAssertEqual(
            DNSProvidersSettingsView.machines([
                CLIMachine(name: "laptop", isSelf: true), CLIMachine(name: "box", isSelf: false),
            ]),
            ["box"])
    }
}
