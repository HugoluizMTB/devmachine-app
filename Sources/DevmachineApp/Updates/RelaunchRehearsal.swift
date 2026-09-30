#if DEBUG
import AppKit
import DevmachineCore
import Foundation

/// Debug builds only. With `DEVMACHINE_DEMO=1` and
/// `DEVMACHINE_RELAUNCH_REHEARSAL=<another .app>`, the app "updates" to that
/// bundle through the real dialog, swap and relaunch, so a relaunch can be
/// watched in a real run without Homebrew, the network or a real release.
enum RelaunchRehearsal {
    static var replacement: URL? {
        guard DemoMode.isActive,
              let path = ProcessInfo.processInfo.environment["DEVMACHINE_RELAUNCH_REHEARSAL"], !path.isEmpty
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    @MainActor
    static func controller(replacing app: URL, with replacement: URL) -> UpdateController {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .flatMap { SemanticVersion($0) } ?? SemanticVersion("0.0.1")
        let target = (Bundle(url: replacement)?.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "9.9.9"
        let feed = ReleaseFeed(url: ReleaseFeed.appReleases, fetcher: FixedRelease(tag: "v\(target)"), userAgent: "")
        return UpdateController(dependencies: UpdateDependencies(
            currentVersion: version,
            appFeed: feed,
            cliFeed: feed,
            preferences: UpdatePreferences(defaults: UserDefaults(suiteName: "app.devmachine.mac.rehearsal.updates") ?? .standard),
            detectInstallMethod: { .manual },
            runningTeamID: "REHEARSAL",
            cliVersion: { nil },
            installer: SwapInstaller(current: app, replacement: replacement),
            homebrew: NoHomebrew(),
            currentAppURL: app,
            relaunch: { try AppRelauncher().relaunch($0) }))
    }

    @MainActor
    static func run(_ updates: UpdateController) {
        guard replacement != nil else { return }
        Task { @MainActor in
            await updates.check(userInitiated: true)
            updates.requestUpdate()
            try? await Task.sleep(for: .seconds(2))
            await updates.install()
        }
    }
}

private struct FixedRelease: HTTPFetching {
    let tag: String

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        let body = #"{"tag_name":"\#(tag)","body":"Relaunch rehearsal.","html_url":"https://example.com"}"#
        return HTTPResponse(status: 200, headers: [:], body: Data(body.utf8))
    }
}

private struct SwapInstaller: AppUpdateInstalling {
    let current: URL
    let replacement: URL

    func install(
        release: GitHubRelease, progress: @escaping @Sendable (UpdateProgress) -> Void
    ) async throws -> ManualInstallOutcome {
        progress(.installing)
        let swapper = BundleSwapper()
        try swapper.swap(try swapper.stage(replacement, beside: current), into: current)
        return .replaced(current)
    }
}

private struct NoHomebrew: HomebrewUpgrading {
    func upgrade(brew: String, output: @escaping @Sendable (String) -> Void) async throws {}
}
#endif
