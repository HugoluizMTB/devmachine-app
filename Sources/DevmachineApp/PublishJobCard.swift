import SwiftUI
import AppKit
import DevmachineCore

/// A publish or a removal in the corner: each step as the CLI reports it,
/// then the live address, the reason it waits for a sync, or the CLI's own
/// error with Retry.
struct PublishJobCard: View {
    @Environment(\.dmMetrics) private var m
    let job: PublishJob
    let onRetry: () -> Void
    let onDismiss: () -> Void

    private var progress: PublishProgress { job.progress }

    static func status(_ outcome: PublishProgress.Outcome) -> DMJobStatus {
        switch outcome {
        case .running: return .running
        case .live, .removed: return .success
        case .saved: return .attention
        case .failed: return .failed
        }
    }

    static func steps(_ progress: PublishProgress) -> [DMJobStep] {
        progress.steps.map { step in
            DMJobStep(id: step.id.rawValue, title: step.title, state: state(step.state), detail: step.detail)
        }
    }

    private static func state(_ state: PublishProgress.StepState) -> DMJobStep.State {
        switch state {
        case .waiting: return .waiting
        case .running: return .running
        case .done: return .done
        case .attention: return .attention
        case .failed: return .failed
        case .skipped: return .skipped
        }
    }

    private var title: String {
        if case .failed = progress.outcome { return progress.host }
        return progress.headline
    }

    var body: some View {
        DMJobCard(
            title: title,
            status: Self.status(progress.outcome),
            steps: Self.steps(progress),
            onClose: onDismiss,
            footer: { footer })
    }

    @ViewBuilder
    private var footer: some View {
        switch progress.outcome {
        case .running:
            EmptyView()
        case .live(let url):
            HStack(spacing: m.space.sm) {
                DMButton("Open", systemImage: "arrow.up.right.square", variant: .outline, size: .small) {
                    NSWorkspace.shared.open(url)
                }
                DMCopyButton(text: url.absoluteString)
            }
        case .removed, .saved:
            EmptyView()
        case .saved(let reason) where !progress.steps.contains { $0.detail == reason }:
            Text(verbatim: reason)
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let details):
            DMErrorStateView(
                state: DMErrorState(title: progress.headline, message: details),
                retry: onRetry, retryTitle: "Retry")
                .frame(maxWidth: .infinity)
        }
    }
}
