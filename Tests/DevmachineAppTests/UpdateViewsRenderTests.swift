import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

private struct FixedHTTP: HTTPFetching {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        let tag = url == ReleaseFeed.cliReleases ? "v0.8.0" : "v0.1.3"
        let body = #"{"tag_name":"\#(tag)","body":"- Faster start\n- Updates from inside the app","html_url":"https://example.com"}"#
        return HTTPResponse(status: 200, headers: [:], body: Data(body.utf8))
    }
}

private struct SilentRunner: CommandRunner {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
}

private struct NoInstall: AppUpdateInstalling, HomebrewUpgrading {
    func install(
        release: GitHubRelease, progress: @escaping @Sendable (UpdateProgress) -> Void
    ) async throws -> ManualInstallOutcome { throw CancellationError() }
    func upgrade(brew: String, output: @escaping @Sendable (String) -> Void) async throws {}
}

@MainActor
final class UpdateViewsRenderTests: XCTestCase {
    private var suite: String!

    override func tearDown() async throws {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private struct HelperDidNotStart: Error {}

    private func controller(method: AppInstallMethod, relaunches: Bool = true) async -> UpdateController {
        suite = "app.devmachine.mac.tests.\(UUID().uuidString)"
        let updates = UpdateController(dependencies: UpdateDependencies(
            currentVersion: SemanticVersion("0.1.2"),
            appFeed: ReleaseFeed(url: ReleaseFeed.appReleases, fetcher: FixedHTTP(), userAgent: "Devmachine"),
            cliFeed: ReleaseFeed(url: ReleaseFeed.cliReleases, fetcher: FixedHTTP(), userAgent: "Devmachine"),
            preferences: UpdatePreferences(defaults: UserDefaults(suiteName: suite)!),
            detectInstallMethod: { method },
            runningTeamID: "TEAM123456",
            cliVersion: { CLIVersionReading(output: "0.7.1", method: .homebrew) },
            installer: NoInstall(), homebrew: NoInstall(),
            currentAppURL: URL(fileURLWithPath: "/Applications/Devmachine.app"),
            relaunch: { _ in if !relaunches { throw HelperDidNotStart() } }))
        await updates.check(userInitiated: true)
        return updates
    }

    private func render(_ view: some View, name: String) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.height, 0)
        if ProcessInfo.processInfo.environment["DEVMACHINE_RENDER"] != nil,
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "/tmp/devmachine-updates-\(name).png"))
        }
    }

    func testTheBannerTheDialogAndTheAboutPaneRender() async throws {
        let manual = await controller(method: .manual)
        let homebrew = await controller(method: .homebrew(brew: "/opt/homebrew/bin/brew"))
        let model = AppModel(store: SessionStore(runner: SilentRunner()))

        try render(
            UpdateBanner().environmentObject(manual).environmentObject(model)
                .padding(20).background(Color.dmContentBg),
            name: "banner")
        try render(UpdateDialog().environmentObject(manual).background(Color.dmContentBg), name: "dialog")
        try render(UpdateDialog().environmentObject(homebrew).background(Color.dmContentBg), name: "dialog-brew")
        try render(
            UpdatesSettingsView().environmentObject(homebrew)
                .frame(width: 640).padding(24).background(Color.black.opacity(0.8)),
            name: "about")
    }

    func testAnUpdateWaitingForARestartRendersEverywhere() async throws {
        let updates = await controller(method: .homebrew(brew: "/opt/homebrew/bin/brew"), relaunches: false)
        await updates.install()
        XCTAssertEqual(updates.phase, .restartNeeded("0.1.3"))
        let model = AppModel(store: SessionStore(runner: SilentRunner()))

        try render(
            UpdateBanner().environmentObject(updates).environmentObject(model)
                .padding(20).background(Color.dmContentBg),
            name: "banner-restart")
        try render(UpdateDialog().environmentObject(updates).background(Color.dmContentBg), name: "dialog-restart")
        try render(
            UpdatesSettingsView().environmentObject(updates)
                .frame(width: 640).padding(24).background(Color.black.opacity(0.8)),
            name: "about-restart")
    }
}
