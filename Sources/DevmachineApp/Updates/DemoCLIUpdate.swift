#if DEBUG
import DevmachineCore
import SwiftUI

/// Debug builds only. The Updates pane's CLI block in each state, for the
/// `DEVMACHINE_DEMO_WALK=cli-update` capture. The update runs a real process
/// through `ProcessCLIUpdater`, but on a fake CLI script written to a temporary
/// folder, never the installed devmachine.
@MainActor
enum DemoCLIUpdate {
    enum State {
        case available, running, updated, failed, oldCLI
    }

    static func pane(_ state: State) async -> some View {
        let updates = await controller(state)
        return UpdatesSettingsView()
            .environmentObject(updates)
            .frame(width: 640)
            .padding(24)
            .background(Color.dmContentBg)
            .environment(\.colorScheme, .dark)
    }

    private static let suite = "app.devmachine.mac.demo.cli-update"

    private static func controller(_ state: State) async -> UpdateController {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("devmachine-demo-cli-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let versionFile = folder.appendingPathComponent("version")
        try? Data((state == .oldCLI ? "0.7.22\n" : "0.7.23\n").utf8).write(to: versionFile)
        let script = folder.appendingPathComponent("devmachine")
        try? Data(fakeCLI(state, versionFile: versionFile.path).utf8).write(to: script)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let cliFeed = ReleaseFeed(url: ReleaseFeed.cliReleases, fetcher: DemoCLIRelease(), userAgent: "")
        let appFeed = ReleaseFeed(url: ReleaseFeed.appReleases, fetcher: DemoCLIRelease(), userAgent: "")
        let path = script.path
        let updates = UpdateController(dependencies: UpdateDependencies(
            currentVersion: SemanticVersion("0.1.7"),
            appFeed: appFeed,
            cliFeed: cliFeed,
            preferences: UpdatePreferences(defaults: UserDefaults(suiteName: suite) ?? .standard),
            detectInstallMethod: { .homebrew(brew: "/opt/homebrew/bin/brew") },
            runningTeamID: "DEMO",
            cliVersion: {
                guard let output = try? String(contentsOf: versionFile, encoding: .utf8) else { return nil }
                return CLIVersionReading(output: output, method: .homebrew)
            },
            installer: DemoNoDiskImage(),
            homebrew: DemoNoHomebrew(),
            cliUpdater: ProcessCLIUpdater(executable: { path }),
            currentAppURL: URL(fileURLWithPath: "/Applications/Devmachine.app"),
            relaunch: { _ in }))
        await updates.check(userInitiated: true)
        switch state {
        case .available, .oldCLI:
            break
        case .running:
            Task { await updates.updateCLI() }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        case .updated, .failed:
            await updates.updateCLI()
        }
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return updates
    }

    private static func fakeCLI(_ state: State, versionFile: String) -> String {
        let log = """
            echo "==> CLI"
            echo "  0.7.23 → v0.8.0"
            echo "  upgrading through Homebrew"
            echo "==> Updating Homebrew..."
            echo "==> Upgrading mydevmachine/tap/devmachine"
            echo "  0.7.23 -> 0.8.0"
            """
        switch state {
        case .running:
            return "#!/bin/sh\n\(log)\nsleep 8\n"
        case .failed:
            return "#!/bin/sh\n\(log)\n"
                + "echo 'error: updating the CLI: brew upgrade mydevmachine/tap/devmachine: exit status 1' 1>&2\n"
                + "exit 1\n"
        case .available, .updated, .oldCLI:
            return "#!/bin/sh\n\(log)\n"
                + "echo '  starting the new version to confirm it'\n"
                + "echo '  updated: 0.7.23 → 0.8.0'\n"
                + "echo 0.8.0 > '\(versionFile)'\n"
        }
    }
}

private struct DemoCLIRelease: HTTPFetching {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        let tag = url == ReleaseFeed.cliReleases ? "v0.8.0" : "v0.1.7"
        let body = #"{"tag_name":"\#(tag)","body":"","html_url":"https://example.com"}"#
        return HTTPResponse(status: 200, headers: [:], body: Data(body.utf8))
    }
}

private struct DemoNoDiskImage: AppUpdateInstalling {
    func install(
        release: GitHubRelease, progress: @escaping @Sendable (UpdateProgress) -> Void
    ) async throws -> ManualInstallOutcome { throw CancellationError() }
}

private struct DemoNoHomebrew: HomebrewUpgrading {
    func upgrade(brew: String, output: @escaping @Sendable (String) -> Void) async throws {}
}
#endif
