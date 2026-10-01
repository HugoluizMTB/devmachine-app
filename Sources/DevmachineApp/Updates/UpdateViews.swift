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

    static func updated(_ version: SemanticVersion) -> String { "CLI updated to \(version)" }

    static func terminalLead(manual: Bool) -> String {
        manual ? "Run this once in a terminal:" : "Or run this in a terminal:"
    }

    static func needsManualUpdate(installed: SemanticVersion) -> String {
        "The app can update the CLI from \(CLISelfUpdate.minimumVersion) on. Your \(installed) needs one "
            + "update in a terminal first; after that, the button here does it."
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

private struct UpdateProgressView: View {
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
        if let release = updates.availableRelease {
            VStack(alignment: .leading, spacing: m.row.horizontal) {
                HStack(alignment: .top, spacing: m.row.horizontal) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.dm(16))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: m.space.xxs) {
                        Text(verbatim: "Devmachine \(release.version?.description ?? release.tagName) "
                            + (updates.isWaitingForRestart ? "is installed" : "is available"))
                            .font(.dm(12, weight: .semibold))
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
    let showNotes: () -> Void
    let later: () -> Void
    let update: () -> Void
    @Environment(\.dmMetrics) private var m

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: m.space.sm) {
                secondary
                updateButton(fillsWidth: false)
            }
            VStack(spacing: m.space.md) {
                secondary
                updateButton(fillsWidth: true)
            }
        }
    }

    private var secondary: some View {
        HStack(spacing: m.space.sm) {
            DMButton("What's new", variant: .link, size: .small, action: showNotes)
            Spacer(minLength: m.space.sm)
            DMButton("Later", variant: .ghost, size: .small, action: later)
        }
    }

    private func updateButton(fillsWidth: Bool) -> some View {
        DMButton("Update and Relaunch", size: .small, fillsWidth: fillsWidth, action: update)
    }
}

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
                buttons(primary: content.primaryTitle) { Task { await updates.install() } }
            } else {
                Text(verbatim: "This copy was built on this Mac without a Developer ID signature, so it "
                    + "cannot check that an update is genuine. Download the new version instead.")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
                buttons(primary: "Open Release Page") {
                    if let url = updates.availableRelease?.htmlURL { NSWorkspace.shared.open(url) }
                    close()
                }
            }
        default:
            UpdateProgressView(phase: updates.phase)
            if case .upgradingWithHomebrew = updates.phase {
                ProcessOutputView(lines: updates.homebrewOutput)
            }
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

struct ProcessOutputView: View {
    @Environment(\.dmMetrics) private var m
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(verbatim: line)
                            .font(.dm(10.5, design: .monospaced))
                            .foregroundStyle(Color.dmMuted)
                            .id(index)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(m.space.md)
            }
            .frame(height: m.pt(120))
            .dmSurface(Color.dmSelection, radius: DMRadius.control)
            .onChange(of: lines.count) { _, count in proxy.scrollTo(count - 1, anchor: .bottom) }
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
                + "Updating replaces only this app, never the CLI, its configuration or your machines.")

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
                note(CLIUpdateContent.scopeNote)
            }
        } else if case .updated(let version) = updates.cliPhase {
            VStack(alignment: .leading, spacing: m.space.md) {
                Label {
                    Text(verbatim: CLIUpdateContent.updated(version))
                        .font(.dm(12.5, weight: .semibold))
                        .foregroundStyle(.white)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if !updates.cliOutput.isEmpty {
                    ProcessOutputView(lines: updates.cliOutput)
                }
            }
        }
    }

    @ViewBuilder
    private func cliState(_ notice: CLIUpdateNotice) -> some View {
        switch updates.cliPhase {
        case .running:
            UpdateProgressView(label: CLIUpdateContent.running)
            ProcessOutputView(lines: updates.cliOutput)
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
