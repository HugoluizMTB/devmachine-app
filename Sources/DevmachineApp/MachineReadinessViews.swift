import SwiftUI
import DevmachineCore

/// The card's words for each state, kept apart from the view so they are
/// tested.
enum MachineReadinessContent {
    static let prepareTitle = "Prepare"

    static func title(machine: String, state: MachineReadiness, job: PrepareJob?) -> String {
        switch job?.phase {
        case .running: return "Preparing \(machine)…"
        case .succeeded: return "\(machine) is ready"
        case .failed, nil: break
        }
        if case .outdated = state { return "\(machine)'s devmachine-app package is out of date" }
        return "\(machine) isn't ready for the app yet"
    }

    static let missingBody = "The app reads this machine's stats, logs and session context through the "
        + "devmachine-app package. Prepare adds it and applies only that package."

    static let oldCLIBody = "Your devmachine CLI can't prepare a machine from here yet (it needs "
        + "\(MachinePrepare.minimumCLIVersion) or newer). Update the CLI first, or run this in a terminal:"

    static let outdatedBody = "It comes from an older packages release than this app needs. The release "
        + "is pinned once for every machine, so the app doesn't move it for you. Run this in a terminal:"

    static let updateCLITitle = "Update the CLI first"

    static func commands(machine: String, state: MachineReadiness, declared: Bool) -> [String] {
        if case .outdated = state { return MachinePrepare.outdatedCommands(machine: machine) }
        return MachinePrepare.manualCommands(machine: machine, declared: declared)
    }
}

/// One machine that is missing what the app runs on it: a calm card with
/// one Prepare button, the live log while it runs, and the exact error with
/// Try again when it fails. `compact` is the sidebar's version.
struct MachineReadinessCard: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: MachineReadinessStore
    let machine: String
    var compact = false

    private var state: MachineReadiness { store.state(for: machine) }
    private var job: PrepareJob? { store.jobs[machine] }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? m.space.sm : m.space.md) {
            header
            content
        }
        .padding(compact ? m.space.md : m.space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: m.space.sm) {
            icon
            Text(verbatim: MachineReadinessContent.title(machine: machine, state: state, job: job))
                .font(.dm(compact ? 11.5 : 12.5, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if case .succeeded = job?.phase {
                DMButton(icon: "xmark", label: "Dismiss", size: .small) { store.dismissJob(machine) }
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch job?.phase {
        case .running:
            ProgressView().controlSize(.mini)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        default:
            Image(systemName: "shippingbox").foregroundStyle(Color.dmMuted)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch job?.phase {
        case .running:
            ProcessOutputView(lines: job?.output ?? [])
        case .succeeded:
            EmptyView()
        case let .failed(error):
            DMErrorStateView(state: error, retry: { Task { await store.prepare(machine) } })
                .frame(maxWidth: .infinity)
        case nil:
            idle
        }
    }

    @ViewBuilder
    private var idle: some View {
        if state.needsPrepare, store.canPrepareInApp {
            paragraph(MachineReadinessContent.missingBody)
            DMButton(MachineReadinessContent.prepareTitle, systemImage: "wrench.and.screwdriver", size: .small) {
                Task { await store.prepare(machine) }
            }
        } else if state.needsPrepare {
            paragraph(MachineReadinessContent.oldCLIBody)
            DMCommandBlock(MachineReadinessContent.commands(
                machine: machine, state: state, declared: store.isDeclared(machine)), wraps: compact)
            DMButton(MachineReadinessContent.updateCLITitle, variant: .link, size: .small) {
                model.openSettings(.about)
            }
        } else if case .outdated = state {
            paragraph(MachineReadinessContent.outdatedBody)
            DMCommandBlock(
                MachineReadinessContent.commands(machine: machine, state: state, declared: true), wraps: compact)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dm(compact ? 10.5 : 11.5))
            .foregroundStyle(Color.dmMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A workspace whose sessions could not be listed: the reason and the fix,
/// where the list would otherwise be empty.
struct SessionProblemView: View {
    @Environment(\.dmMetrics) private var m
    let presentation: SessionProblemPresentation
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            DMErrorStateView(
                state: DMErrorState(
                    title: presentation.title, cause: presentation.cause, details: presentation.details),
                retry: retry)
                .frame(maxWidth: .infinity)
            if !presentation.commands.isEmpty {
                DMCommandBlock(presentation.commands, wraps: true)
            }
        }
        .padding(m.space.md)
    }
}
