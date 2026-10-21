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
    /// Streams the log to `output` and returns stdout, which holds the JSON
    /// report for a command that prints one.
    func run(_ command: CLIUpdateCommand, output: @escaping @Sendable (String) -> Void) async throws -> Data
}

enum CLIUpdateError: LocalizedError, Equatable {
    case exited(Int32)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .exited(let status): return "devmachine update exited with status \(status)."
        case .unavailable: return "The devmachine CLI cannot be run from here."
        }
    }
}

struct UnavailableCLIUpdater: CLIUpdating {
    func run(_ command: CLIUpdateCommand, output: @escaping @Sendable (String) -> Void) async throws -> Data {
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

enum PackagesUpdatePhase: Equatable {
    case idle
    case running
    case done(CLIUpdateReport?)
    case failed(DMErrorState)
}

/// Step 1 of the app dialog: the CLI, the packages pin and the skills,
/// brought up before the app so a new build never needs what the Mac lacks.
enum ToolsStepPhase: Equatable {
    case idle
    case running
    case upToDate
    case done
    case failed(DMErrorState)
    case needsManualUpdate(String)
    case bypassed
}

enum UnifiedUpdateStep: Equatable, CaseIterable {
    case tools
    case app
    case relaunch
}

enum UnifiedUpdateStepStatus: Equatable {
    case waiting
    case running
    case done
    case skipped
    case failed
}

/// What each of the dialog's three steps shows, read from step 1 and the
/// app's install phase.
struct UnifiedUpdateSteps: Equatable {
    let tools: UnifiedUpdateStepStatus
    let app: UnifiedUpdateStepStatus
    let relaunch: UnifiedUpdateStepStatus

    init(tools: UnifiedUpdateStepStatus, app: UnifiedUpdateStepStatus, relaunch: UnifiedUpdateStepStatus) {
        self.tools = tools
        self.app = app
        self.relaunch = relaunch
    }

    init(tools: ToolsStepPhase, toolsBehind: Bool, phase: UpdatePhase) {
        switch tools {
        case .idle: self.tools = toolsBehind ? .waiting : .skipped
        case .running: self.tools = .running
        case .upToDate, .bypassed: self.tools = .skipped
        case .done: self.tools = .done
        case .failed, .needsManualUpdate: self.tools = .failed
        }
        switch phase {
        case .idle:
            app = .waiting
            relaunch = .waiting
        case .downloading, .verifying, .installing, .upgradingWithHomebrew:
            app = .running
            relaunch = .waiting
        case .relaunching:
            app = .done
            relaunch = .running
        case .restartNeeded:
            app = .done
            relaunch = .failed
        case .manualMove:
            app = .done
            relaunch = .skipped
        case .failed:
            app = .failed
            relaunch = .waiting
        }
    }

    func status(_ step: UnifiedUpdateStep) -> UnifiedUpdateStepStatus {
        switch step {
        case .tools: return tools
        case .app: return app
        case .relaunch: return relaunch
        }
    }
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
    var packagesOutdated: @Sendable () async throws -> Data = { throw CLIUpdateError.unavailable }
    var afterToolsUpdate: @MainActor () async -> Void = {}
    var currentAppURL: URL
    var relaunchTimeout: TimeInterval = 10
    var relaunch: @MainActor (URL) throws -> Void
}

/// Looks for a newer Devmachine.app, devmachine CLI and packages release, and
/// updates each when the person asks. For the CLI it runs `update
/// --no-machines` (CLI 0.7.31+) or `update --cli-only`: the binary, the
/// packages pin and the skills on this Mac, never a machine or a sync.
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
    @Published private(set) var cliReport: CLIUpdateReport?
    @Published private(set) var packagesNotice: PackagesOutdated?
    @Published private(set) var packagesPhase: PackagesUpdatePhase = .idle
    @Published private(set) var packagesOutput: [String] = []
    @Published private var packagesLaterVersion: String?
    @Published private var packagesUpdateClosed = false
    @Published private(set) var toolsStep: ToolsStepPhase = .idle
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
        packagesLaterVersion = dependencies.preferences.packagesLaterVersion
    }

    private static let log = AppLogChannel(category: "updates")

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
        guard let current = dependencies.currentVersion, !isChecking, !phase.isBusy, toolsStep != .running
        else { return }
        isChecking = true
        defer {
            isChecking = false
            lastCheckedAt = dependencies.now()
        }
        async let cli = readCLIState()
        if installMethod == nil {
            let detect = dependencies.detectInstallMethod
            installMethod = await Task.detached { detect() }.value
        }
        do {
            let release = try await latest(from: dependencies.appFeed)
            availability = UpdatePolicy.evaluate(
                current: current, release: release, skippedVersion: dependencies.preferences.skippedVersion)
            Self.log.info("app update check (\(userInitiated ? "asked" : "automatic")): \(current) installed, "
                + "\(release.tagName) is the latest")
            checkError = nil
            if case .failed = phase { phase = .idle }
        } catch {
            Self.log.error("app update check failed: \(error.localizedDescription)")
            if userInitiated || availability == nil {
                checkError = DMErrorState(title: "Could not check for updates", message: error.localizedDescription)
            }
        }
        let state = await cli
        cliNotice = state.notice
        if case .updated = cliPhase, cliNotice != nil { cliPhase = .idle }
        if packagesPhase != .running {
            packagesNotice = state.packages
        }
    }

    /// A CLI older than `--cli-only` would need plain `update`, which moves
    /// the packages pin and syncs; the app never runs that.
    var canUpdateCLIInApp: Bool {
        guard let notice = cliNotice, cliPhase != .needsManualUpdate else { return false }
        return CLISelfUpdate.supportsCLIOnly(notice.installed)
    }

    /// The app card covers the CLI and packages cards: its dialog updates
    /// them first.
    var showsCLIBanner: Bool {
        guard !showsBanner else { return false }
        return CLIUpdateToast.shows(stage: cliToastStage, latest: cliNotice?.latest, laterVersion: cliLaterVersion)
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
        await runCLIUpdate(notice)
        await dependencies.afterToolsUpdate()
    }

    private func runCLIUpdate(_ notice: CLIUpdateNotice) async {
        let command = CLIUpdateCommand.forCLI(installed: notice.installed)
        cliUpdateClosed = false
        cliOutput = []
        cliReport = nil
        cliPhase = .running
        let sink = ProcessOutputSink { [weak self] lines in
            if (self?.cliOutput.count ?? 0) < lines.count { self?.cliOutput = lines }
        }
        do {
            let stdout = try await dependencies.cliUpdater.run(command, output: sink.receive)
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
            if command.printsJSON { cliReport = CLIUpdateReport.parse(stdout) }
            if let report = cliReport, let latest = packagesNotice?.latest,
               PackagesUpdateToast.isCovered(latest: latest, by: report), packagesPhase != .running {
                packagesNotice = nil
            }
            cliPhase = .updated(version)
        } catch {
            cliOutput = sink.snapshot
            if command.isUnknownFlag(cliOutput) {
                cliPhase = .needsManualUpdate
                return
            }
            Self.log.error("CLI update failed: \(error.localizedDescription)")
            cliPhase = .failed(DMErrorState(
                title: "The CLI was not updated",
                cause: CLISelfUpdate.failureCause(cliOutput) ?? error.localizedDescription,
                details: cliDetails(fallback: error.localizedDescription)))
        }
    }

    var showsPackagesBanner: Bool {
        guard !showsBanner else { return false }
        return PackagesUpdateToast.shows(
            stage: packagesToastStage, notice: packagesNotice, laterVersion: packagesLaterVersion)
    }

    private var packagesToastStage: PackagesUpdateToast.Stage {
        switch packagesPhase {
        case .idle: return .idle
        case .running: return .running
        case .done: return .done(closed: packagesUpdateClosed)
        case .failed: return .failed
        }
    }

    /// Hides the card for this packages release, across relaunches, until a
    /// newer one comes out.
    func packagesLater() {
        guard let latest = packagesNotice?.latest else { return }
        dependencies.preferences.packagesLaterVersion = latest
        packagesLaterVersion = latest
    }

    func closePackagesUpdated() {
        packagesUpdateClosed = true
        packagesPhase = .idle
    }

    /// Pins the newest packages release and updates the skills on this Mac:
    /// `update --no-machines --skip-cli`. Machines change only at a sync,
    /// which this never runs.
    func updatePackages() async {
        guard let notice = packagesNotice, packagesPhase != .running else { return }
        await runPackagesUpdate(notice)
        await dependencies.afterToolsUpdate()
    }

    private func runPackagesUpdate(_ notice: PackagesOutdated) async {
        packagesUpdateClosed = false
        packagesOutput = []
        packagesPhase = .running
        let sink = ProcessOutputSink { [weak self] lines in
            if (self?.packagesOutput.count ?? 0) < lines.count { self?.packagesOutput = lines }
        }
        do {
            let stdout = try await dependencies.cliUpdater.run(.packagesOnly, output: sink.receive)
            packagesOutput = sink.snapshot
            let report = CLIUpdateReport.parse(stdout)
            guard let report, PackagesUpdateToast.isCovered(latest: notice.latest, by: report) else {
                packagesPhase = .failed(DMErrorState(
                    title: "The packages pin did not move",
                    cause: report.map { "The CLI pinned \($0.packagesTo ?? "nothing"), not \(notice.latest)." }
                        ?? "The CLI did not report what it pinned.",
                    details: details(packagesOutput, fallback: String(decoding: stdout, as: UTF8.self))))
                return
            }
            packagesNotice = nil
            packagesPhase = .done(report)
        } catch {
            packagesOutput = sink.snapshot
            Self.log.error("packages update failed: \(error.localizedDescription)")
            packagesPhase = .failed(DMErrorState(
                title: "Packages were not updated",
                cause: CLISelfUpdate.failureCause(packagesOutput) ?? error.localizedDescription,
                details: details(packagesOutput, fallback: error.localizedDescription)))
        }
    }

    var toolsBehind: Bool { cliNotice != nil || packagesNotice != nil }

    var dialogSteps: UnifiedUpdateSteps {
        UnifiedUpdateSteps(tools: toolsStep, toolsBehind: toolsBehind, phase: phase)
    }

    var appCardTitle: String {
        guard let release = availableRelease else { return "" }
        return AppUpdateCardContent.title(
            version: release.version?.description ?? release.tagName, installed: isWaitingForRestart,
            cli: cliNotice?.latest, packages: packagesNotice?.latest)
    }

    /// Step 1 runs the cards' own updates, never a command of its own: the
    /// CLI card's when the CLI is behind, then the packages card's when the
    /// pin is still behind. True when the app may go on to step 2.
    func updateTools() async -> Bool {
        guard availableRelease != nil, toolsStep != .running, !phase.isBusy, !isWaitingForRestart else { return false }
        guard toolsBehind else {
            toolsStep = .upToDate
            return true
        }
        toolsStep = .running
        if let notice = cliNotice {
            await updateCLI()
            switch cliPhase {
            case .updated:
                cliUpdateClosed = true
            case .failed(let error):
                toolsStep = .failed(error)
                return false
            case .needsManualUpdate:
                toolsStep = .needsManualUpdate(notice.command)
                return false
            case .idle, .running:
                toolsStep = .idle
                return false
            }
        }
        if packagesNotice != nil {
            await updatePackages()
            switch packagesPhase {
            case .done:
                closePackagesUpdated()
            case .failed(let error):
                toolsStep = .failed(error)
                return false
            case .idle, .running:
                toolsStep = .idle
                return false
            }
        }
        toolsStep = .done
        return true
    }

    /// The app dialog's "Update and Relaunch": step 1, then the install and
    /// the relaunch exactly as before. A step 1 that did not finish leaves
    /// the app alone.
    func updateAll() async {
        guard await updateTools() else { return }
        await install()
    }

    func updateOnlyTheApp() async {
        guard availableRelease != nil, toolsStep != .running, !phase.isBusy, !isWaitingForRestart else { return }
        toolsStep = .bypassed
        await install()
    }

    private func details(_ lines: [String], fallback: String) -> String {
        let output = lines.suffix(40).joined(separator: "\n")
        return output.isEmpty ? fallback : output
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
        if toolsStep != .running, !phase.isBusy { toolsStep = .idle }
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
            Self.log.error("Homebrew update failed: \(error.localizedDescription)")
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
            Self.log.error("app update install failed: \(error.localizedDescription)")
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

    /// The installed CLI is read once for both cards. `packages outdated`
    /// falls back to its last stored answer offline and fails only when it
    /// never had one, so a failure means "unknown": no card, only a log line.
    private func readCLIState() async -> (notice: CLIUpdateNotice?, packages: PackagesOutdated?) {
        guard let reading = await dependencies.cliVersion() else { return (nil, nil) }
        async let packages = readPackages(installed: SemanticVersion.first(in: reading.output))
        let notice = (try? await latest(from: dependencies.cliFeed)).flatMap {
            CLIUpdateAdvice.notice(versionOutput: reading.output, latest: $0, method: reading.method)
        }
        return (notice, await packages)
    }

    private func readPackages(installed: SemanticVersion?) async -> PackagesOutdated? {
        guard let installed, PackagesUpdateToast.isSupported(installed: installed) else { return nil }
        do {
            return PackagesUpdateToast.offered(try PackagesOutdated.parse(try await dependencies.packagesOutdated()))
        } catch {
            Self.log.error("packages outdated failed: \(error.localizedDescription)")
            return nil
        }
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
