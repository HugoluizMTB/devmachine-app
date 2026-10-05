import AppKit
import DevmachineCore
import SwiftUI

/// How a failed setup step ends, in the Add machine wizard and the first
/// run alike: what went wrong in plain words (`SetupFailureHelp`), the
/// buttons that fix it, the last log lines to copy, and Report a bug.
struct SetupFailurePanel: View {
    let step: MachinePlanStep?
    let lines: [String]
    /// The runner's own words, when the log has none (a stop, a refusal).
    let problem: String?
    let exitCode: Int32?
    var onRetry: (() -> Void)?
    var onEditAnswers: (() -> Void)?
    @Environment(\.dmMetrics) private var m

    private var help: SetupFailureHelp? {
        step.map { SetupFailureHelp.help(for: $0, lines: lines + [problem].compactMap { $0 }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            DMErrorStateView(
                state: DMErrorState(
                    title: help?.title ?? "The setup stopped",
                    cause: cause,
                    details: details),
                retry: offersRetry ? onRetry : nil, retryTitle: "Retry")
            FlowLayout(spacing: DMSpace.sm) {
                ForEach(Array(extraActions.enumerated()), id: \.offset) { _, action in
                    button(action)
                }
                DMReportBugButton {
                    BugReportEnvironment.report(
                        title: "Setup failed: " + (step?.title ?? "unknown step"),
                        stepID: step?.id ?? "unknown", command: step?.displayLine ?? "",
                        exitCode: exitCode, lines: lines)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var cause: String {
        var text = help?.whatToDo ?? "Retry runs it again. Steps already done are skipped."
        if help?.cause == nil, let problem, !problem.isEmpty { text = problem + "\n\n" + text }
        return text
    }

    private var details: String {
        let tail = lines.suffix(30).joined(separator: "\n")
        return tail.isEmpty ? (step?.displayLine ?? problem ?? "") : tail
    }

    private var offersRetry: Bool {
        onRetry != nil && (help?.actions.contains(.retry) ?? true)
    }

    private var extraActions: [SetupFailureHelp.Action] {
        (help?.actions ?? [.editAnswers("Back")]).filter { action in
            if case .retry = action { return false }
            if case .editAnswers = action { return onEditAnswers != nil }
            return true
        }
    }

    @ViewBuilder
    private func button(_ action: SetupFailureHelp.Action) -> some View {
        switch action {
        case .retry:
            EmptyView()
        case let .editAnswers(title):
            DMButton(title, systemImage: "chevron.left", variant: .outline, size: .small) { onEditAnswers?() }
        case let .open(title, url):
            DMButton(title, systemImage: "arrow.up.right.square", variant: .outline, size: .small) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
