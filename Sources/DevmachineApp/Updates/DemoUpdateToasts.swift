#if DEBUG
import DevmachineCore
import SwiftUI

/// Debug builds only. The update toast in each state it can be in, built from
/// a controller that reads a fixed release and never installs anything, for
/// the `DEVMACHINE_DEMO_WALK=update-toast` capture.
@MainActor
enum DemoUpdateToasts {
    enum State {
        case available, relaunching, installed
    }

    static func toastStack(_ state: State, model: AppModel) async -> some View {
        let updates = await controller(state)
        return VStack(alignment: .trailing, spacing: 8) {
            UpdateBanner()
            DMToastCard(task: BGTask(id: UUID(), label: "Sending mockup.png", completed: 3, total: 8))
        }
        .environmentObject(updates)
        .environmentObject(model)
        .padding(18)
        .background(Color.dmContentBg)
        .environment(\.colorScheme, .dark)
    }

    private static let suite = "app.devmachine.mac.demo.update-toast"

    private static func controller(_ state: State) async -> UpdateController {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let feed = ReleaseFeed(url: ReleaseFeed.appReleases, fetcher: DemoRelease(), userAgent: "")
        let updates = UpdateController(dependencies: UpdateDependencies(
            currentVersion: SemanticVersion("0.1.6"),
            appFeed: feed,
            cliFeed: feed,
            preferences: UpdatePreferences(defaults: UserDefaults(suiteName: suite) ?? .standard),
            detectInstallMethod: { .homebrew(brew: "/opt/homebrew/bin/brew") },
            runningTeamID: "DEMO",
            cliVersion: { nil },
            installer: NoDiskImage(),
            homebrew: NoHomebrew(),
            currentAppURL: URL(fileURLWithPath: "/Applications/Devmachine.app"),
            relaunchTimeout: 3600,
            relaunch: { _ in if state == .installed { throw RelaunchDidNotStart() } }))
        await updates.check(userInitiated: true)
        if state != .available { await updates.install() }
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return updates
    }
}

private struct RelaunchDidNotStart: Error {}

private struct DemoRelease: HTTPFetching {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        let body = #"{"tag_name":"v0.1.7","body":"- Faster start","html_url":"https://example.com"}"#
        return HTTPResponse(status: 200, headers: [:], body: Data(body.utf8))
    }
}

private struct NoDiskImage: AppUpdateInstalling {
    func install(
        release: GitHubRelease, progress: @escaping @Sendable (UpdateProgress) -> Void
    ) async throws -> ManualInstallOutcome { throw CancellationError() }
}

private struct NoHomebrew: HomebrewUpgrading {
    func upgrade(brew: String, output: @escaping @Sendable (String) -> Void) async throws {}
}
#endif
