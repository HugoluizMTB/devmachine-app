import SwiftUI

/// The cards of jobs still running: the app's background tasks and a
/// workspace being set up for scheduled tasks. They sit in the window's
/// corner, or over a sheet that asks for them (`showsProgressCards`): a
/// sheet dims the window under it, and a card there reads as disabled.
struct ProgressCards: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var scheduled = ScheduledStore.shared

    var body: some View {
        if let setup = scheduled.setup {
            ScheduledSetupCard(progress: setup)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
        ForEach(model.activeTasks) { task in
            DMToastCard(task: task)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

private struct ProgressCardsOverSheet: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var scheduled = ScheduledStore.shared
    @Environment(\.dmMetrics) private var m

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: m.space.md) {
                    ProgressCards()
                }
                .padding(m.space.lg)
                .animation(.easeInOut(duration: 0.2), value: model.activeTasks)
                .animation(.easeInOut(duration: 0.2), value: scheduled.setup)
            }
            .onAppear { model.sheetsShowingProgress += 1 }
            .onDisappear { model.sheetsShowingProgress = max(0, model.sheetsShowingProgress - 1) }
    }
}

extension View {
    /// Draws the progress cards over this part of a sheet while the sheet
    /// is open, in place of the window's corner.
    func showsProgressCards() -> some View {
        modifier(ProgressCardsOverSheet())
    }
}
