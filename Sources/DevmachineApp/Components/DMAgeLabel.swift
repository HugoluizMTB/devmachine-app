import SwiftUI
import DevmachineCore

/// How old the data on screen is, said quietly, and only once it is old
/// enough to matter: a cached list is drawn at once and refreshed behind it.
struct DMAgeLabel: View {
    @Environment(\.dmMetrics) private var m
    let since: Date?
    var staleAfter: TimeInterval = 60
    var isRefreshing = false

    static func text(since: Date, now: Date) -> String {
        let age = StatsFreshness.ageText(since: since, now: now)
        return age.prefix(1).uppercased() + age.dropFirst()
    }

    var body: some View {
        if let since {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                if context.date.timeIntervalSince(since) >= staleAfter {
                    HStack(spacing: m.space.xs) {
                        if isRefreshing {
                            ProgressView().controlSize(.mini).scaleEffect(0.7)
                        }
                        Text(verbatim: Self.text(since: since, now: context.date))
                            .font(.dm(10.5))
                            .foregroundStyle(Color.dmMuted)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
