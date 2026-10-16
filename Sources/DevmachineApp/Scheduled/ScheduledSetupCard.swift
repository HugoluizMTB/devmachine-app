import SwiftUI
import DevmachineCore

/// A workspace's first scheduled task while the CLI sets the package up:
/// the steps it has reached, from the lines it prints.
struct ScheduledSetupCard: View {
    @Environment(\.dmMetrics) private var m
    let progress: ScheduledSetupProgress

    static let note = "This can take a few minutes. It only happens the first time on this workspace."
    static let finishingNote = "This can take a few minutes."

    static func steps(_ progress: ScheduledSetupProgress) -> [DMJobStep] {
        progress.steps.enumerated().map { index, step in
            let state: DMJobStep.State
            switch step.state {
            case .waiting: state = .waiting
            case .running: state = .running
            case .done: state = .done
            }
            return DMJobStep(id: String(index), title: step.title, state: state, detail: step.detail)
        }
    }

    var body: some View {
        DMJobCard(
            title: progress.finishing
                ? "Finishing scheduled's setup on \(progress.workspace)" : "Setting up scheduled on \(progress.workspace)",
            status: .running, steps: Self.steps(progress)
        ) {
            Text(verbatim: progress.finishing ? Self.finishingNote : Self.note)
                .font(.dm(10.5))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
