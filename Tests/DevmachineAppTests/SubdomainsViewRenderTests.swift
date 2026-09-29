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
final class SubdomainsViewRenderTests: XCTestCase {
    func testThePageRendersWithNoData() throws {
        let suiteName = "dev.devmachine.app.subdomains.render.tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let view = SubdomainsView()
            .environmentObject(AppModel(store: SessionStore(runner: SilentRunner())))
            .environmentObject(CaddyStore())
            .environmentObject(SettingsStore(defaults: defaults))
            .frame(width: 800, height: 500)

        let image = try XCTUnwrap(ImageRenderer(content: view).nsImage)

        XCTAssertEqual(image.size.width, 800)
        XCTAssertEqual(image.size.height, 500)
    }

    func testThePageRendersARowAndAProviderTab() throws {
        let suiteName = "dev.devmachine.app.subdomains.render.tests2"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = CaddyStore()
        store.rows = [
            SubdomainRow(
                site: ExposedSite(host: "app.example.com", port: 8080, workspace: "acme", status: .published),
                resolvedWorkspace: "acme", containerName: nil),
            SubdomainRow(
                site: ExposedSite(host: "old.example.com", port: 8810, workspace: nil, status: .unmanaged),
                resolvedWorkspace: nil, containerName: "web"),
        ]
        store.domain = "example.com"
        store.dnsProviders = ["Cloudflare"]
        store.dnsRecordsByProvider["Cloudflare"] = [
            DNSRecordRow(name: "app", type: "A", value: "203.0.113.10", ttl: 300)
        ]

        let view = SubdomainsView()
            .environmentObject(AppModel(store: SessionStore(runner: SilentRunner())))
            .environmentObject(store)
            .environmentObject(SettingsStore(defaults: defaults))
            .frame(width: 800, height: 500)

        let image = try XCTUnwrap(ImageRenderer(content: view).nsImage)

        XCTAssertEqual(image.size.width, 800)
    }
}
