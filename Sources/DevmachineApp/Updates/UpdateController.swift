import AppKit
import DevmachineCore
import Foundation

enum UpdateProgress: Equatable, Sendable {
    case downloading(Double)
    case verifying
    case installing
}

enum ManualInstallOutcome: Equatable, Sendable {
    case replaced(URL)
    case needsManualMove(URL)
}

protocol AppUpdateInstalling: Sendable {
    func install(
        release: GitHubRelease, progress: @escaping @Sendable (UpdateProgress) -> Void
    ) async throws -> ManualInstallOutcome
}

protocol HomebrewUpgrading: Sendable {
    func upgrade(brew: String, output: @escaping @Sendable (String) -> Void) async throws
}

protocol CLIUpdating: Sendable {
    func updateCLI(output: @escaping @Sendable (String) -> Void) async throws
}

enum CLIUpdateError: LocalizedError, Equatable {
    case exited(Int32)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .exited(let status): return "devmachine update --cli-only exited with status \(status)."
        case .unavailable: return "The devmachine CLI cannot be run from here."
        }
    }
}

struct UnavailableCLIUpdater: CLIUpdating {
    func updateCLI(output: @escaping @Sendable (String) -> Void) async throws {
        throw CLIUpdateError.unavailable
    }
}

enum CLIUpdatePhase: Equatable {
    case idle
    case running
    case updated(SemanticVersion)
    case failed(DMErrorState)
    case needsManualUpdate
}

struct CLIVersionReading: Equatable, Sendable {
    let output: String
    let method: CLIInstallMethod
}

enum UpdatePhase: Equatable {
    case idle
    case downloading(Double)
    case verifying
    case installing
    case upgradingWithHomebrew
    case relaunching
    case restartNeeded(String)
    case manualMove(URL)
    case failed(DMErrorState)

    var isBusy: Bool {
        switch self {
        case .downloading, .verifying, .installing, .upgradingWithHomebrew, .relaunching: return true
        case .idle, .restartNeeded, .manualMove, .failed: return false
        }
    }
}

struct UpdateDependencies {
    var currentVersion: SemanticVersion?
    var appFeed: ReleaseFeed
    var cliFeed: ReleaseFeed
    var preferences: UpdatePreferences
    var schedule = UpdateSchedule()
    var now: @Sendable () -> Date = { Date() }
    var sleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    var detectInstallMethod: @Sendable () -> AppInstallMethod
    var runningTeamID: String?
    var cliVersion: @Sendable () async -> CLIVersionReading?
    var installer: any AppUpdateInstalling
    var homebrew: any HomebrewUpgrading
    var cliUpdater: any CLIUpdating = UnavailableCLIUpdater()
    var currentAppURL: URL
    var relaunchTimeout: TimeInterval = 10
    var relaunch: @MainActor (URL) throws -> Void
}

/// Looks for a newer Devmachine.app and a newer devmachine CLI, and replaces
/// either when the person asks. For the CLI it runs only `update --cli-only`,
/// which replaces the binary and never its configuration, packages or machines.
@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var availability: UpdateAvailability?
    @Published private(set) var checkError: DMErrorState?
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var phase: UpdatePhase = .idle
    @Published private(set) var homebrewOutput: [String] = []
    @Published private(set) var installMethod: AppInstallMethod?
    @Published private(set) var cliNotice: CLIUpdateNotice?
    @Published private(set) var cliPhase: CLIUpdatePhase = .idle
    @Published private(set) var cliOutput: [String] = []
    @Published private var dismissedVersion: SemanticVersion?
    @Published private var cliLaterVersion: String?
    @Published private var cliUpdateClosed = false
    @Published var showsDialog = false

    private let dependencies: UpdateDependencies
    private var launchedAt: Date
    private var scheduleTask: Task<Void, Never>?
    private var relaunchTarget: URL?
    private var installingVersion: String?
    private(set) var relaunchWatchdog: Task<Void, Never>?

    init(dependencies: UpdateDependencies) {
        self.dependencies = dependencies
        launchedAt = dependencies.now()
        cliLaterVersion = dependencies.preferences.cliLaterVersion
    }

    var currentVersion: SemanticVersion? { dependencies.currentVersion }

    var automaticChecks: Bool {
        get { dependencies.preferences.automaticChecks }
        set {
            objectWillChange.send()
            dependencies.preferences.automaticChecks = newValue
        }
    }

    var availableRelease: GitHubRelease? {
        switch availability {
        case .available(let release), .skipped(let release): return release
        case .upToDate, nil: return nil
        }
    }

    var isSkipped: Bool {
        if case .skipped = availability { return true }
        return false
    }

    var showsBanner: Bool {
        if phase != .idle { return availableRelease != nil }
        guard case .available(let release) = availability else { return false }
        return release.version != dismissedVersion
    }

    var releaseNotes: String { availableRelease?.notes ?? "" }

    /// A copy signed ad hoc (a local build) has no team to compare an update
    /// against, so it can only be updated through Homebrew or by hand.
    var canInstallInPlace: Bool {
        if case .homebrew = installMethod { return true }
        return dependencies.runningTeamID != nil
    }

    func start() {
        guard scheduleTask == nil, dependencies.currentVersion != nil else { return }
        launchedAt = dependencies.now()
        scheduleTask = Task { [weak self] in await self?.runSchedule() }
    }

    func runSchedule() async {
        while !Task.isCancelled {
            let delay = dependencies.schedule.delay(
                now: dependencies.now(), launchedAt: launchedAt, lastCheckedAt: lastCheckedAt)
            do {
                try await dependencies.sleep(delay)
            } catch {
                return
            }
            if automaticChecks {
                await check(userInitiated: false)
            } else {
                lastCheckedAt = dependencies.now()
            }
        }
    }

    func checkNow() {
        Task { await check(userInitiated: true) }
    }

    func check(userInitiated: Bool) async {
        guard let current = dependencies.currentVersion, !isChecking, !phase.isBusy else { return }
        isChecking = true
        defer {
            isChecking = false
            lastCheckedAt = dependencies.now()
        }
        async let cli = readCLINotice()
        if installMethod == nil {
            let detect = dependencies.detectInstallMethod
            installMethod = await Task.detached { detect() }.value
        }
        do {
            let release = try await latest(from: dependencies.appFeed)
            availability = UpdatePolicy.evaluate(
                current: current, release: release, skippedVersion: dependencies.preferences.skippedVersion)
            checkError = nil
            if case .failed = phase { phase = .idle }
        } catch {
            if userInitiated || availability == nil {
                checkError = DMErrorState(title: "Could not check for updates", message: error.localizedDescription)
            }
        }
        cliNotice = await cli
        if case .updated = cliPhase, cliNotice != nil { cliPhase = .idle }
    }

    /// A CLI older than `--cli-only` would need plain `update`, which moves
    /// the packages pin and syncs; the app never runs that.
    var canUpdateCLIInApp: Bool {
        guard let notice = cliNotice, cliPhase != .needsManualUpdate else { return false }
        return CLISelfUpdate.supportsCLIOnly(notice.installed)
    }

    var showsCLIBanner: Bool {
        CLIUpdateToast.shows(stage: cliToastStage, latest: cliNotice?.latest, laterVersion: cliLaterVersion)
    }

    private var cliToastStage: CLIUpdateToast.Stage {
        switch cliPhase {
        case .idle: return .idle
        case .running: return .running
        case .updated: return .updated(closed: cliUpdateClosed)
        case .failed: return .failed
        case .needsManualUpdate: return .manual
        }
    }

    /// Hides the toast for this CLI version, across relaunches, until a newer
    /// one comes out. Settings → About still offers it.
    func cliLater() {
        guard let latest = cliNotice?.latest else { return }
        dependencies.preferences.cliLaterVersion = latest.description
        cliLaterVersion = latest.description
    }

    /// The toast's way to the terminal command for a CLI the app cannot update.
    /// Nothing runs: the command is only shown.
    func showCLICommand() {
        guard cliNotice != nil, cliPhase != .running else { return }
        cliPhase = .needsManualUpdate
    }

    func closeCLIUpdated() {
        cliUpdateClosed = true
    }

    func updateCLI() async {
        guard let notice = cliNotice, cliPhase != .running else { return }
        guard canUpdateCLIInApp else {
            cliPhase = .needsManualUpdate
            return
        }
        cliUpdateClosed = false
        cliOutput = []
        cliPhase = .running
        let sink = ProcessOutputSink { [weak self] lines in
            if (self?.cliOutput.count ?? 0) < lines.count { self?.cliOutput = lines }
        }
        do {
            try await dependencies.cliUpdater.updateCLI(output: sink.receive)
            cliOutput = sink.snapshot
            let reading = await dependencies.cliVersion()
            guard let version = reading.flatMap({
                CLISelfUpdate.confirmedVersion(versionOutput: $0.output, expected: notice.latest)
            }) else {
                let found = reading.flatMap { SemanticVersion.first(in: $0.output) }?.description ?? "no version"
                cliPhase = .failed(DMErrorState(
                    title: "The CLI did not change",
                    cause: "devmachine version still says \(found), not \(notice.latest).",
                    details: cliDetails(fallback: reading?.output ?? "")))
                return
            }
            cliNotice = nil
            cliPhase = .updated(version)
        } catch {
            cliOutput = sink.snapshot
            if CLISelfUpdate.isUnknownFlag(cliOutput) {
                cliPhase = .needsManualUpdate
                return
            }
            cliPhase = .failed(DMErrorState(
                title: "The CLI was not updated",
                cause: CLISelfUpdate.failureCause(cliOutput) ?? error.localizedDescription,
                details: cliDetails(fallback: error.localizedDescription)))
        }
    }

    private func cliDetails(fallback: String) -> String {
        let output = cliOutput.suffix(40).joined(separator: "\n")
        return output.isEmpty ? fallback : output
    }

    func skipThisVersion() {
        guard let release = availableRelease, let version = release.version else { return }
        dependencies.preferences.skippedVersion = version.description
        availability = .skipped(release)
    }

    func later() {
        dismissedVersion = availableRelease?.version
    }

    func install() async {
        guard let release = availableRelease, !phase.isBusy, !isWaitingForRestart else { return }
        installingVersion = release.version?.description ?? release.tagName
        homebrewOutput = []
        switch installMethod ?? .manual {
        case .homebrew(let brew):
            await installWithHomebrew(brew: brew)
        case .manual:
            await installFromDiskImage(release)
        }
    }

    func requestUpdate() {
        guard availableRelease != nil else { return }
        showsDialog = true
    }

    var dialogContent: UpdateDialogContent? {
        availableRelease.map {
            UpdateDialogContent(
                release: $0, current: currentVersion,
                method: installMethod ?? .manual)
        }
    }

    var isWaitingForRestart: Bool {
        if case .restartNeeded = phase { return true }
        return false
    }

    func quitAndReopen() {
        guard isWaitingForRestart, let app = relaunchTarget else { return }
        relaunch(app)
    }

    func dismissFailure() {
        if case .failed = phase { phase = .idle }
    }

    private func installWithHomebrew(brew: String) async {
        phase = .upgradingWithHomebrew
        let sink = ProcessOutputSink { [weak self] lines in
            if (self?.homebrewOutput.count ?? 0) < lines.count { self?.homebrewOutput = lines }
        }
        do {
            try await dependencies.homebrew.upgrade(brew: brew, output: sink.receive)
            homebrewOutput = sink.snapshot
            relaunch(dependencies.currentAppURL)
        } catch {
            homebrewOutput = sink.snapshot
            let output = homebrewOutput.suffix(40).joined(separator: "\n")
            phase = .failed(DMErrorState(
                title: "Homebrew could not update Devmachine",
                cause: error.localizedDescription,
                details: output.isEmpty ? error.localizedDescription : output))
        }
    }

    private func installFromDiskImage(_ release: GitHubRelease) async {
        phase = .downloading(0)
        do {
            let outcome = try await dependencies.installer.install(release: release) { progress in
                Task { @MainActor [weak self] in self?.show(progress) }
            }
            switch outcome {
            case .replaced(let app): relaunch(app)
            case .needsManualMove(let app): phase = .manualMove(app)
            }
        } catch {
            phase = .failed(DMErrorState(title: "The update was not installed", message: error.localizedDescription))
        }
    }

    private func show(_ progress: UpdateProgress) {
        guard phase.isBusy, phase != .relaunching else { return }
        switch progress {
        case .downloading(let fraction): phase = .downloading(fraction)
        case .verifying: phase = .verifying
        case .installing: phase = .installing
        }
    }

    /// The dialog is a sheet, and AppKit will not quit while a sheet is up,
    /// so it goes first. Anything else that keeps this copy running turns,
    /// after a short wait, into a plain request to quit and reopen by hand.
    private func relaunch(_ app: URL) {
        relaunchTarget = app
        phase = .relaunching
        showsDialog = false
        relaunchWatchdog?.cancel()
        relaunchWatchdog = nil
        do {
            try dependencies.relaunch(app)
        } catch {
            askToQuitAndReopen()
            return
        }
        let sleep = dependencies.sleep
        let timeout = dependencies.relaunchTimeout
        relaunchWatchdog = Task { [weak self] in
            guard (try? await sleep(timeout)) != nil else { return }
            self?.askToQuitAndReopen()
        }
    }

    private func askToQuitAndReopen() {
        guard phase == .relaunching else { return }
        phase = .restartNeeded(installingVersion ?? availableRelease?.tagName ?? "")
        showsDialog = true
    }

    private func latest(from feed: ReleaseFeed) async throws -> GitHubRelease {
        let preferences = dependencies.preferences
        let result = try await feed.latest(cached: preferences.cache(for: feed.url))
        preferences.setCache(result.cache, for: feed.url)
        return result.release
    }

    private func readCLINotice() async -> CLIUpdateNotice? {
        guard let reading = await dependencies.cliVersion(),
              let latest = try? await latest(from: dependencies.cliFeed)
        else { return nil }
        return CLIUpdateAdvice.notice(versionOutput: reading.output, latest: latest, method: reading.method)
    }
}

/// Lines from brew or the CLI arrive on the reading thread. Each one updates the view
/// with the whole list so far, so the order never depends on which main-actor
/// hop lands first.
final class ProcessOutputSink: @unchecked Sendable {
    private let deliver: @MainActor ([String]) -> Void
    private let lock = NSLock()
    private var lines: [String] = []

    init(deliver: @escaping @MainActor ([String]) -> Void) {
        self.deliver = deliver
    }

    var snapshot: [String] { lock.withLock { lines } }

    func receive(_ line: String) {
        let all = lock.withLock {
            lines.append(line)
            return lines
        }
        Task { @MainActor [deliver] in deliver(all) }
    }
}
