import AppKit
import DevmachineCore
import MarkdownUI
import SwiftUI

/// The CLI block's wording, kept apart from the view so it is tested.
enum CLIUpdateContent {
    static let buttonTitle = "Update CLI"
    static let running = "Updating the CLI…"
    static let scopeNote = "Updating the CLI replaces only the devmachine program. It does not change your "
        + "configuration, packages or machines, and it never types into a session."

    static let scopeNoteWithPackages = "Updating the CLI replaces the devmachine program, pins the newest "
        + "packages release and updates the skills on this Mac. Your machines change only when you sync, and "
        + "it never types into a session."

    static func scopeNote(installed: SemanticVersion) -> String {
        CLIUpdateCommand.forCLI(installed: installed) == .noMachines ? scopeNoteWithPackages : scopeNote
    }

    static func updated(_ version: SemanticVersion) -> String { "CLI updated to \(version)" }

    /// "CLI updated to 0.8.0 · packages pinned v33 · skills updated". The
    /// version comes from `devmachine version`, read after the update.
    static func updated(_ version: SemanticVersion, report: CLIUpdateReport?) -> String {
        guard let report else { return updated(version) }
        return ([updated(version)] + report.packagesAndSkills).joined(separator: " · ")
    }

    static func terminalLead(manual: Bool) -> String {
        manual ? "Run this once in a terminal:" : "Or run this in a terminal:"
    }

    static func available(_ version: SemanticVersion) -> String { "devmachine CLI \(version) is available" }
    static let toastNote = "Updates only the CLI. Your machines and configuration stay as they are."
    static let updatedNote = "Your machines and configuration stay as they are."
    static let toastNoteWithPackages = "Also pins the newest packages and updates skills. Your machines change "
        + "only when you sync."
    static let syncNote = "Your machines change only when you sync."

    static func toastNote(installed: SemanticVersion) -> String {
        CLIUpdateCommand.forCLI(installed: installed) == .noMachines ? toastNoteWithPackages : toastNote
    }

    static func updatedNote(report: CLIUpdateReport?) -> String {
        report == nil ? updatedNote : syncNote
    }
    static let toastButtonTitle = "Update"
    static let detailsTitle = "Details"

    static func needsManualUpdate(installed: SemanticVersion) -> String {
        "The app can update the CLI from \(CLISelfUpdate.minimumVersion) on. Your \(installed) needs one "
            + "update in a terminal first; after that, the button here does it."
    }
}

/// The packages card's wording, kept apart from the view so it is tested.
enum PackagesUpdateContent {
    static func available(_ version: String) -> String { "Packages \(version) is available" }
    static let note = "New packages and skills for your machines. Your machines change only when you sync."
    static let running = "Pinning the packages and updating skills…"
    static let updateTitle = "Update"
    static let detailsTitle = "Details"
    static let syncSuggestion = "Sync your machines from Settings → Machines"
    static let openMachinesTitle = "Open Machines"

    static func done(_ report: CLIUpdateReport?) -> String {
        guard let report else { return "Packages and skills updated" }
        let summary = report.packagesAndSkills.joined(separator: " · ")
        return summary.prefix(1).uppercased() + summary.dropFirst()
    }
}

/// The app card's title, which names what its dialog also updates.
enum AppUpdateCardContent {
    static func title(version: String, installed: Bool, cli: SemanticVersion?, packages: String?) -> String {
        let head = "Devmachine \(version) " + (installed ? "is installed" : "is available")
        guard !installed else { return head }
        let also = [cli.map { "the CLI to \($0)" }, packages.map { "packages to \($0)" }].compactMap { $0 }
        guard !also.isEmpty else { return head }
        return head + " · also updates " + also.joined(separator: " and ")
    }
}

/// The app dialog's three steps, kept apart from the view so it is tested.
enum UnifiedUpdateContent {
    static let updateOnlyTheAppTitle = "Update only the app"
    static let toolsRunning = "Updating the CLI and packages…"

    static func title(_ step: UnifiedUpdateStep, appVersion: String) -> String {
        switch step {
        case .tools: return "CLI and packages"
        case .app: return "Devmachine \(appVersion)"
        case .relaunch: return "Relaunch"
        }
    }

    static func toolsDetail(cli: CLIUpdateNotice?, packages: PackagesOutdated?) -> String {
        let parts = [
            cli.map { "CLI \($0.installed) → \($0.latest)" },
            packages.map { "packages \($0.pinned) → \($0.latest)" },
        ].compactMap { $0 }
        return parts.isEmpty ? "Up to date" : parts.joined(separator: " · ")
    }

    static func status(_ status: UnifiedUpdateStepStatus) -> String {
        switch status {
        case .waiting: return "Waiting"
        case .running: return "Running"
        case .done: return "Done"
        case .upToDate: return "Up to date"
        case .couldNotCheck: return "Could not check"
        case .skipped: return "Skipped"
        case .failed: return "Failed"
        case .moveByHand: return "Move it by hand"
        }
    }
}

/// Kept apart from the view so the wording is tested, and is the same for a
/// Homebrew and a disk image install.
struct UpdateDialogContent: Equatable {
    static let sessionsNote = "Your sessions keep running. Updating only restarts this app — every terminal "
        + "and agent, on this Mac or on your machines, carries on and is right where you left it when "
        + "Devmachine reopens."

    let title: String
    let subtitle: String?
    let notes: String
    let sessionsNote = UpdateDialogContent.sessionsNote
    let homebrewCommand: String?
    let primaryTitle = "Update and Relaunch"
    static let quitAndReopenTitle = "Quit and Reopen"

    static func restartNeeded(version: String) -> String {
        "Updated to \(version) — quit and reopen Devmachine to finish."
    }

    init(release: GitHubRelease, current: SemanticVersion?, method: AppInstallMethod) {
        title = "Update Devmachine to \(release.version?.description ?? release.tagName)"
        subtitle = current.map { "You have \($0)." }
        notes = release.notes
        if case .homebrew = method {
            homebrewCommand = HomebrewAppUpgrade.displayCommand
        } else {
            homebrewCommand = nil
        }
    }
}

private func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

struct UpdateProgressView: View {
    @Environment(\.dmMetrics) private var m
    let label: String
    let done: Int

    init(label: String, done: Int = 0) {
        self.label = label
        self.done = done
    }

    init(phase: UpdatePhase) {
        self.init(label: Self.label(phase), done: Self.done(phase))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            Text(verbatim: label)
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
            DMProgressBar(done: done, total: 100, fillColor: .accentColor)
        }
    }

    private static func label(_ phase: UpdatePhase) -> String {
        switch phase {
        case .downloading(let fraction): return "Downloading… \(Int((fraction * 100).rounded()))%"
        case .verifying: return "Checking the download…"
        case .installing: return "Installing…"
        case .upgradingWithHomebrew: return "Updating with Homebrew…"
        case .relaunching: return "Relaunching…"
        default: return ""
        }
    }

    private static func done(_ phase: UpdatePhase) -> Int {
        switch phase {
        case .downloading(let fraction): return Int((fraction * 100).rounded())
        case .verifying: return 100
        case .installing, .relaunching: return 100
        default: return 0
        }
    }
}

private struct RestartNeededView: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var updates: UpdateController
    let version: String

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            Text(verbatim: UpdateDialogContent.restartNeeded(version: version))
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                DMButton(UpdateDialogContent.quitAndReopenTitle, size: .small) { updates.quitAndReopen() }
            }
        }
    }
}

/// The toast that says a new version is out. It never installs on its own:
/// every path to an install goes through the dialog.
struct UpdateBanner: View {
    @EnvironmentObject private var updates: UpdateController
    @EnvironmentObject private var model: AppModel
    @Environment(\.dmMetrics) private var m

    var body: some View {
        if updates.availableRelease != nil {
            VStack(alignment: .leading, spacing: m.row.horizontal) {
                HStack(alignment: .top, spacing: m.row.horizontal) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.dm(16))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: m.space.xxs) {
                        Text(verbatim: updates.appCardTitle)
                            .font(.dm(12, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: "Your sessions keep running.")
                            .font(.dm(11))
                            .foregroundStyle(Color.dmMuted)
                    }
                }
                if case .restartNeeded(let version) = updates.phase {
                    RestartNeededView(version: version)
                } else if updates.phase.isBusy {
                    UpdateProgressView(phase: updates.phase)
                } else {
                    UpdateBannerActions(
                        showNotes: { model.openSettings(.about) },
                        later: { updates.later() },
                        update: { updates.requestUpdate() })
                }
            }
            .frame(width: m.card.banner, alignment: .leading)
            .padding(m.space.lg)
            .dmGlass(radius: DMRadius.toast)
            .shadow(radius: m.pt(10), y: m.pt(3))
        }
    }
}

/// One row while the three buttons fit the card. The card grows with the
/// text, so this holds at every text size; a longer label moves the update
/// button to a full-width row of its own instead of past the edge.
struct UpdateBannerActions: View {
    var notesTitle = "What's new"
    var updateTitle = "Update and Relaunch"
    var laterTitle = "Later"
    let showNotes: () -> Void
    let later: () -> Void
    let update: (() -> Void)?
    @Environment(\.dmMetrics) private var m

    var body: some View {
        if let update {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: m.space.sm) {
                    secondary
                    updateButton(fillsWidth: false, action: update)
                }
                VStack(spacing: m.space.md) {
                    secondary
                    updateButton(fillsWidth: true, action: update)
                }
            }
        } else {
            secondary
        }
    }

    private var secondary: some View {
        HStack(spacing: m.space.sm) {
            DMButton(notesTitle, variant: .link, size: .small, action: showNotes)
            Spacer(minLength: m.space.sm)
            DMButton(laterTitle, variant: .ghost, size: .small, action: later)
        }
    }

    private func updateButton(fillsWidth: Bool, action: @escaping () -> Void) -> some View {
        DMButton(updateTitle, size: .small, fillsWidth: fillsWidth, action: action)
    }
}

/// The corner toast for a newer devmachine CLI, below the app's own. Update
/// runs `update --no-machines` (0.7.31+) or `update --cli-only`, and only on
/// a CLI that has one; any other CLI gets the terminal command to copy, which
/// the app never runs or types.
struct CLIUpdateBanner: View {
    @EnvironmentObject private var updates: UpdateController
    @EnvironmentObject private var model: AppModel
    @Environment(\.dmMetrics) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: m.row.horizontal) {
            if case .updated(let version) = updates.cliPhase {
                header(
                    icon: "checkmark.circle.fill", tint: .green,
                    title: CLIUpdateContent.updated(version, report: updates.cliReport),
                    note: CLIUpdateContent.updatedNote(report: updates.cliReport))
                UpdateBannerActions(
                    notesTitle: CLIUpdateContent.detailsTitle, laterTitle: "Close",
                    showNotes: { model.openSettings(.about) }, later: { updates.closeCLIUpdated() }, update: nil)
            } else if let notice = updates.cliNotice {
                header(
                    icon: "terminal.fill", tint: .accentColor, title: CLIUpdateContent.available(notice.latest),
                    note: CLIUpdateContent.toastNote(installed: notice.installed))
                state(notice)
            }
        }
        .frame(width: m.card.banner, alignment: .leading)
        .dmToastChrome()
    }

    private func header(icon: String, tint: Color, title: String, note: String) -> some View {
        UpdateToastHeader(icon: icon, tint: tint, title: title, note: note)
    }

    @ViewBuilder
    private func state(_ notice: CLIUpdateNotice) -> some View {
        switch updates.cliPhase {
        case .running:
            UpdateProgressView(label: CLIUpdateContent.running)
        case .failed(let error):
            DMErrorStateView(state: error, retry: { Task { await updates.updateCLI() } })
            actions(update: nil)
        case .needsManualUpdate:
            VStack(alignment: .leading, spacing: m.space.sm) {
                Text(verbatim: CLIUpdateContent.terminalLead(manual: true))
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                DMCommandBlock(notice.command, wraps: true)
            }
            actions(update: nil)
        case .idle, .updated:
            actions(update: update)
        }
    }

    private func actions(update: (() -> Void)?) -> some View {
        UpdateBannerActions(
            notesTitle: CLIUpdateContent.detailsTitle, updateTitle: CLIUpdateContent.toastButtonTitle,
            showNotes: { model.openSettings(.about) }, later: { updates.cliLater() }, update: update)
    }

    private func update() {
        if updates.canUpdateCLIInApp {
            Task { await updates.updateCLI() }
        } else {
            updates.showCLICommand()
        }
    }
}

struct UpdateToastHeader: View {
    let icon: String
    let tint: Color
    let title: String
    let note: String
    @Environment(\.dmMetrics) private var m

    var body: some View {
        HStack(alignment: .top, spacing: m.row.horizontal) {
            Image(systemName: icon)
                .font(.dm(16))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: m.space.xxs) {
                Text(verbatim: title)
                    .font(.dm(12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: note)
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The corner card for a newer packages release, under the CLI's. Update
/// pins it and updates the skills on this Mac (`update --no-machines
/// --skip-cli`); it never syncs, so the done card only points at Settings →
/// Machines.
struct PackagesUpdateBanner: View {
    @EnvironmentObject private var updates: UpdateController
    @EnvironmentObject private var model: AppModel
    @Environment(\.dmMetrics) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: m.row.horizontal) {
            switch updates.packagesPhase {
            case .done(let report):
                UpdateToastHeader(
                    icon: "checkmark.circle.fill", tint: .green, title: PackagesUpdateContent.done(report),
                    note: PackagesUpdateContent.syncSuggestion)
                UpdateBannerActions(
                    notesTitle: PackagesUpdateContent.openMachinesTitle, laterTitle: "Close",
                    showNotes: { model.openSettings(.machines) }, later: { updates.closePackagesUpdated() },
                    update: nil)
            case .idle, .running, .failed:
                if let notice = updates.packagesNotice {
                    UpdateToastHeader(
                        icon: "shippingbox.fill", tint: .accentColor,
                        title: PackagesUpdateContent.available(notice.latest), note: PackagesUpdateContent.note)
                    state(notice)
                }
            }
        }
        .frame(width: m.card.banner, alignment: .leading)
        .dmToastChrome()
    }

    @ViewBuilder
    private func state(_ notice: PackagesOutdated) -> some View {
        switch updates.packagesPhase {
        case .running:
            UpdateProgressView(label: PackagesUpdateContent.running)
        case .failed(let error):
            DMErrorStateView(state: error, retry: { Task { await updates.updatePackages() } })
            actions(notice, update: nil)
        case .idle, .done:
            actions(notice, update: { Task { await updates.updatePackages() } })
        }
    }

    private func actions(_ notice: PackagesOutdated, update: (() -> Void)?) -> some View {
        UpdateBannerActions(
            notesTitle: PackagesUpdateContent.detailsTitle, updateTitle: PackagesUpdateContent.updateTitle,
            showNotes: { showDetails(notice) }, later: { updates.packagesLater() }, update: update)
    }

    private func showDetails(_ notice: PackagesOutdated) {
        if let url = notice.notesURL {
            NSWorkspace.shared.open(url)
        } else {
            model.openSettings(.packages)
        }
    }
}

/// The CLI, the packages pin and the skills come first, then the app, then
/// the relaunch: a new app never starts against a CLI it needs to be newer.
struct UpdateDialog: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var updates: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: m.pt(14)) {
            if let content = updates.dialogContent {
                VStack(alignment: .leading, spacing: m.pt(3)) {
                    Text(verbatim: content.title)
                        .font(.dm(15, weight: .semibold))
                    if let subtitle = content.subtitle {
                        Text(verbatim: subtitle)
                            .font(.dm(11))
                            .foregroundStyle(Color.dmMuted)
                    }
                }
                if !content.notes.isEmpty {
                    ViewThatFits(in: .vertical) {
                        notes(content.notes)
                        ScrollView { notes(content.notes) }
                    }
                    .frame(maxHeight: m.pt(180))
                }
                UnifiedUpdateStepsView()
                if let command = content.homebrewCommand {
                    VStack(alignment: .leading, spacing: m.space.sm) {
                        Text(verbatim: "Installed with Homebrew. The app runs this for you:")
                            .font(.dm(11))
                            .foregroundStyle(Color.dmMuted)
                        DMCommandBlock(command)
                    }
                }
                Text(verbatim: content.sessionsNote)
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
                state(content)
            }
        }
        .padding(m.pt(20))
        .frame(width: m.card.sheetLarge)
    }

    @ViewBuilder
    private func state(_ content: UpdateDialogContent) -> some View {
        switch updates.toolsStep {
        case .running:
            UpdateProgressView(label: UnifiedUpdateContent.toolsRunning)
            DMLogView(lines: updates.packagesPhase == .running ? updates.packagesOutput : updates.cliOutput)
        case .failed(let error) where updates.phase == .idle:
            DMErrorStateView(state: error, retry: { start() })
            toolsStepButtons()
        case .needsManualUpdate(let command) where updates.phase == .idle:
            VStack(alignment: .leading, spacing: m.space.sm) {
                Text(verbatim: CLIUpdateContent.terminalLead(manual: true))
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                DMCommandBlock(command, wraps: true)
            }
            toolsStepButtons()
        default:
            appState(content)
        }
    }

    @ViewBuilder
    private func appState(_ content: UpdateDialogContent) -> some View {
        switch updates.phase {
        case .failed(let error):
            DMErrorStateView(state: error, retry: { Task { await updates.install() } })
            HStack {
                Spacer()
                DMButton("Close", variant: .outline) { close() }
            }
        case .restartNeeded(let version):
            Text(verbatim: UpdateDialogContent.restartNeeded(version: version))
                .font(.dm(11.5))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                DMButton("Close", variant: .outline) { close() }
                DMButton(UpdateDialogContent.quitAndReopenTitle) { updates.quitAndReopen() }
                    .keyboardShortcut(.defaultAction)
            }
        case .manualMove(let app):
            Text(verbatim: "Devmachine cannot write to its own folder. Move the new app into Applications, "
                + "replacing the old one, then open it.")
                .font(.dm(11.5))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                DMButton("Close", variant: .outline) { close() }
                DMButton("Show in Finder") { revealInFinder(app) }
            }
        case .idle:
            if updates.canInstallInPlace {
                buttons(primary: content.primaryTitle) { start() }
            } else {
                Text(verbatim: "This copy was built on this Mac without a Developer ID signature, so it "
                    + "cannot check that an update is genuine. Download the new version instead.")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
                buttons(primary: "Open Release Page") { start() }
            }
        default:
            UpdateProgressView(phase: updates.phase)
            if case .upgradingWithHomebrew = updates.phase {
                DMLogView(lines: updates.homebrewOutput)
            }
        }
    }

    private func start() {
        if updates.canInstallInPlace {
            Task { await updates.updateAll() }
        } else {
            Task {
                if await updates.updateTools() { openReleasePage() }
            }
        }
    }

    private func updateOnlyTheApp() {
        if updates.canInstallInPlace {
            Task { await updates.updateOnlyTheApp() }
        } else {
            openReleasePage()
        }
    }

    private func openReleasePage() {
        if let url = updates.availableRelease?.htmlURL { NSWorkspace.shared.open(url) }
        close()
    }

    private func toolsStepButtons() -> some View {
        HStack {
            Spacer()
            DMButton("Cancel", variant: .outline) { close() }
                .keyboardShortcut(.cancelAction)
            DMButton(UnifiedUpdateContent.updateOnlyTheAppTitle) { updateOnlyTheApp() }
        }
    }

    private func notes(_ text: String) -> some View {
        Markdown(text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buttons(primary: String, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            DMButton("Cancel", variant: .outline) { close() }
                .keyboardShortcut(.cancelAction)
            DMButton(primary, action: action)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func close() {
        updates.dismissFailure()
        updates.showsDialog = false
    }
}

private struct UnifiedUpdateStepsView: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var updates: UpdateController

    var body: some View {
        let steps = updates.dialogSteps
        VStack(alignment: .leading, spacing: m.space.sm) {
            ForEach(UnifiedUpdateStep.allCases, id: \.self) { step in
                row(step, status: steps.status(step))
            }
        }
        .padding(m.space.md)
        .dmSurface(Color.dmBand, radius: DMRadius.panel)
    }

    private func row(_ step: UnifiedUpdateStep, status: UnifiedUpdateStepStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: m.space.md) {
            icon(status)
                .frame(width: m.pt(14))
            VStack(alignment: .leading, spacing: m.space.xxs) {
                Text(verbatim: UnifiedUpdateContent.title(step, appVersion: appVersion))
                    .font(.dm(12, weight: .medium))
                if let detail = detail(step, status: status) {
                    Text(verbatim: detail)
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: m.space.sm)
            Text(verbatim: UnifiedUpdateContent.status(status))
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
        }
    }

    private var appVersion: String {
        updates.availableRelease.map { $0.version?.description ?? $0.tagName } ?? ""
    }

    private func detail(_ step: UnifiedUpdateStep, status: UnifiedUpdateStepStatus) -> String? {
        guard step == .tools, status == .waiting || status == .running || status == .failed else { return nil }
        return UnifiedUpdateContent.toolsDetail(cli: updates.cliNotice, packages: updates.packagesNotice)
    }

    @ViewBuilder
    private func icon(_ status: UnifiedUpdateStepStatus) -> some View {
        switch status {
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .upToDate:
            Image(systemName: "checkmark.circle").foregroundStyle(Color.dmMuted)
        case .skipped, .couldNotCheck:
            Image(systemName: "minus.circle").foregroundStyle(Color.dmMuted)
        case .moveByHand:
            Image(systemName: "hand.point.right").foregroundStyle(Color.dmMuted)
        case .waiting:
            Image(systemName: "circle").foregroundStyle(Color.dmMuted)
        }
    }
}

struct UpdatesSettingsView: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var updates: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: m.pt(22)) {
            appBlock
            cliBlock
        }
    }

    private var appBlock: some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            HStack(spacing: m.space.md) {
                Text(verbatim: "Devmachine")
                    .font(.dm(13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(verbatim: updates.currentVersion?.description ?? "development build")
                    .font(.dm(11.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                DMButton("Check for Updates…", variant: .outline, size: .small, isLoading: updates.isChecking) {
                    updates.checkNow()
                }
                .disabled(updates.currentVersion == nil || updates.phase.isBusy)
            }
            Text(verbatim: statusLine)
                .font(.dm(11))
                .foregroundStyle(.white.opacity(0.55))
            Toggle(isOn: Binding(get: { updates.automaticChecks }, set: { updates.automaticChecks = $0 })) {
                Text(verbatim: "Check for updates automatically")
                    .font(.dm(12))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            note("Looks at launch and every 6 hours. Nothing installs until you click Update and Relaunch. "
                + "A CLI or packages pin that is behind is updated first, then this app. Your configuration "
                + "and machines stay as they are.")

            if let error = updates.checkError {
                DMErrorStateView(state: error, retry: { updates.checkNow() })
            }
            if let release = updates.availableRelease {
                releaseBlock(release)
            }
        }
    }

    private func releaseBlock(_ release: GitHubRelease) -> some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            Text(verbatim: "Devmachine \(release.version?.description ?? release.tagName)"
                + (updates.isSkipped ? " · skipped" : ""))
                .font(.dm(12.5, weight: .semibold))
                .foregroundStyle(.white)
            if !release.notes.isEmpty {
                Markdown(release.notes)
                    .markdownTextStyle { ForegroundColor(.white.opacity(0.8)) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if case .homebrew = updates.installMethod {
                VStack(alignment: .leading, spacing: m.space.sm) {
                    Text(verbatim: "Installed with Homebrew")
                        .font(.dm(11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    DMCommandBlock(HomebrewAppUpgrade.displayCommand)
                }
            }
            if updates.phase.isBusy {
                UpdateProgressView(phase: updates.phase)
            }
            if case .failed(let error) = updates.phase {
                DMErrorStateView(state: error, retry: { updates.requestUpdate() })
            }
            HStack(spacing: m.space.md) {
                if updates.isWaitingForRestart {
                    DMButton(UpdateDialogContent.quitAndReopenTitle, size: .small) { updates.quitAndReopen() }
                } else {
                    DMButton("Update and Relaunch", size: .small) { updates.requestUpdate() }
                        .disabled(updates.phase.isBusy)
                }
                if !updates.isSkipped, !updates.isWaitingForRestart {
                    DMButton("Skip This Version", variant: .outline, size: .small) { updates.skipThisVersion() }
                }
                if let url = release.htmlURL {
                    DMButton("Release Page", variant: .link, size: .small) { NSWorkspace.shared.open(url) }
                }
            }
            note("Your sessions keep running.")
        }
        .padding(m.pt(14))
        .dmSurface(Color.white.opacity(0.06), radius: DMRadius.panel)
    }

    @ViewBuilder
    private var cliBlock: some View {
        if let notice = updates.cliNotice {
            VStack(alignment: .leading, spacing: m.space.md) {
                Text(verbatim: "devmachine CLI \(notice.latest) is available")
                    .font(.dm(12.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text(verbatim: "You have \(notice.installed).")
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.55))
                cliState(notice)
                Text(verbatim: CLIUpdateContent.terminalLead(manual: !updates.canUpdateCLIInApp))
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.55))
                DMCommandBlock(notice.command)
                note(CLIUpdateContent.scopeNote(installed: notice.installed))
            }
        } else if case .updated(let version) = updates.cliPhase {
            VStack(alignment: .leading, spacing: m.space.md) {
                Label {
                    Text(verbatim: CLIUpdateContent.updated(version, report: updates.cliReport))
                        .font(.dm(12.5, weight: .semibold))
                        .foregroundStyle(.white)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if !updates.cliOutput.isEmpty {
                    DMLogView(lines: updates.cliOutput)
                }
            }
        }
    }

    @ViewBuilder
    private func cliState(_ notice: CLIUpdateNotice) -> some View {
        switch updates.cliPhase {
        case .running:
            UpdateProgressView(label: CLIUpdateContent.running)
            DMLogView(lines: updates.cliOutput)
        case .failed(let error):
            DMErrorStateView(state: error, retry: { Task { await updates.updateCLI() } })
        case .needsManualUpdate:
            Text(verbatim: CLIUpdateContent.needsManualUpdate(installed: notice.installed))
                .font(.dm(11))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        case .idle, .updated:
            if updates.canUpdateCLIInApp {
                DMButton(CLIUpdateContent.buttonTitle, size: .small) { Task { await updates.updateCLI() } }
            } else {
                Text(verbatim: CLIUpdateContent.needsManualUpdate(installed: notice.installed))
                    .font(.dm(11))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusLine: String {
        guard updates.currentVersion != nil else {
            return "Updates work in the packaged app, not in a development build."
        }
        switch updates.phase {
        case .restartNeeded(let version): return UpdateDialogContent.restartNeeded(version: version)
        case .relaunching: return "Relaunching…"
        default: break
        }
        if updates.isChecking { return "Checking…" }
        switch updates.availability {
        case .upToDate:
            return "Up to date" + (updates.lastCheckedAt.map { " · checked \(Self.time.string(from: $0))" } ?? "")
        case .available(let release), .skipped(let release):
            return "Version \(release.version?.description ?? release.tagName) is available."
        case nil:
            return "Not checked yet."
        }
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dm(10))
            .foregroundStyle(.white.opacity(0.45))
            .fixedSize(horizontal: false, vertical: true)
    }
}
