#if DEBUG
import DevmachineCore
import SwiftUI

/// Debug builds only. The Updates pane's CLI block and the corner toast in
/// each state, for the `DEVMACHINE_DEMO_WALK=cli-update` capture. The update runs a real process
/// through `ProcessCLIUpdater`, but on a fake CLI script written to a temporary
/// folder, never the installed devmachine.
@MainActor
enum DemoCLIUpdate {
    enum State {
        case available, running, updated, failed, oldCLI
    }

    enum ToastState {
        case withAppUpdate, running, updated, failed, manual, pinned
    }

    /// The packages card: next to the app's and the CLI's (`available`),
    /// then alone while it runs, once done, and after a failure.
    enum PackagesState {
        case available, running, done, failed
    }

    static func packagesStack(_ state: PackagesState, model: AppModel) async -> some View {
        let updates = await packagesController(state)
        return stack(updates, model: model)
    }

    static func toastStack(_ state: ToastState, model: AppModel) async -> some View {
        let updates: UpdateController
        switch state {
        case .withAppUpdate: updates = await controller(.available, appUpdate: true)
        case .running: updates = await controller(.running)
        case .updated: updates = await controller(.updated)
        case .failed: updates = await controller(.failed)
        case .manual:
            updates = await controller(.oldCLI)
            updates.showCLICommand()
        case .pinned:
            updates = await controller(.updated, installed: "0.7.31")
        }
        return stack(updates, model: model)
    }

    private static func stack(_ updates: UpdateController, model: AppModel) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            if updates.showsBanner { UpdateBanner() }
            if updates.showsCLIBanner { CLIUpdateBanner() }
            if updates.showsPackagesBanner { PackagesUpdateBanner() }
        }
        .environmentObject(updates)
        .environmentObject(model)
        .padding(18)
        .background(Color.dmContentBg)
        .environment(\.colorScheme, .dark)
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

    private static func controller(
        _ state: State, appUpdate: Bool = false, installed: String? = nil
    ) async -> UpdateController {
        let version = installed ?? (state == .oldCLI ? "0.7.22" : "0.7.23")
        let fake = fakeCLIFolder(version: version)
        try? Data(fakeCLI(state, versionFile: fake.versionFile.path, installed: version).utf8).write(to: fake.script)
        let updates = makeController(appUpdate: appUpdate, fake: fake)
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

    private static func packagesController(_ state: PackagesState) async -> UpdateController {
        let fake = fakeCLIFolder(version: "0.7.31")
        try? Data(fakePackagesCLI(state).utf8).write(to: fake.script)
        let updates = makeController(appUpdate: state == .available, fake: fake, cliLatest: state == .available)
        await updates.check(userInitiated: true)
        switch state {
        case .available:
            break
        case .running:
            Task { await updates.updatePackages() }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        case .done, .failed:
            await updates.updatePackages()
        }
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return updates
    }

    private struct FakeCLI {
        let versionFile: URL
        let script: URL
    }

    private static func fakeCLIFolder(version: String) -> FakeCLI {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("devmachine-demo-cli-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let versionFile = folder.appendingPathComponent("version")
        try? Data("\(version)\n".utf8).write(to: versionFile)
        let script = folder.appendingPathComponent("devmachine")
        FileManager.default.createFile(atPath: script.path, contents: nil, attributes: [.posixPermissions: 0o755])
        return FakeCLI(versionFile: versionFile, script: script)
    }

    private static func makeController(appUpdate: Bool, fake: FakeCLI, cliLatest: Bool = true) -> UpdateController {
        let versionFile = fake.versionFile
        let cliFeed = ReleaseFeed(
            url: ReleaseFeed.cliReleases, fetcher: DemoCLIRelease(cliTag: cliLatest ? "v0.8.0" : "v0.7.31"),
            userAgent: "")
        let appFeed = ReleaseFeed(url: ReleaseFeed.appReleases, fetcher: DemoCLIRelease(), userAgent: "")
        let path = fake.script.path
        return UpdateController(dependencies: UpdateDependencies(
            currentVersion: SemanticVersion(appUpdate ? "0.1.6" : "0.1.7"),
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
            packagesOutdated: { Data(packagesOutdatedJSON.utf8) },
            currentAppURL: URL(fileURLWithPath: "/Applications/Devmachine.app"),
            relaunch: { _ in }))
    }

    private nonisolated static let packagesOutdatedJSON =
        #"{"pinned":"v32","latest":"v33","newer":true,"notes_url":"https://example.com/packages/v33"}"#

    private static func fakePackagesCLI(_ state: PackagesState) -> String {
        let log = """
            echo "==> Packages" 1>&2
            echo "  v32 → v33" 1>&2
            """
        switch state {
        case .running:
            return "#!/bin/sh\n\(log)\nsleep 8\n"
        case .failed:
            return "#!/bin/sh\n\(log)\n"
                + "echo 'error: pinning the packages: reading the packages releases: no route to host' 1>&2\n"
                + "exit 1\n"
        case .available, .done:
            return "#!/bin/sh\n\(log)\necho '==> Skills' 1>&2\necho '  updated' 1>&2\n"
                + #"echo '{"cli":{"from":"0.7.31","to":"0.7.31","updated":false},"#
                + #""packages":{"from":"v32","to":"v33","pinned":true},"skills":{"updated":true}}'"#
                + "\n"
        }
    }

    private static func fakeCLI(_ state: State, versionFile: String, installed: String) -> String {
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
            let report = installed == "0.7.31"
                ? #"echo '{"cli":{"from":"0.7.31","to":"0.8.0","updated":true},"#
                    + #""packages":{"from":"v32","to":"v33","pinned":true},"skills":{"updated":true}}'"# + "\n"
                : ""
            return "#!/bin/sh\n\(log)\n"
                + "echo '  starting the new version to confirm it'\n"
                + "echo '  updated: \(installed) → 0.8.0'\n"
                + "echo 0.8.0 > '\(versionFile)'\n"
                + report
        }
    }
}

private struct DemoCLIRelease: HTTPFetching {
    var cliTag = "v0.8.0"

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        let tag = url == ReleaseFeed.cliReleases ? cliTag : "v0.1.7"
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
