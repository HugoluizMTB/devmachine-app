import SwiftUI

/// A quiet sign that a session is producing output: one character turning, in
/// place of the count. Replaces the progress bar the agent used to draw across
/// the top of the pane, which was hard to ignore.
struct WorkingIndicator: View {
    private static let frames = ["/", "—", "\\", "|"]
    private static let interval = 0.12

    @State private var step = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: WorkingIndicator.interval)) { timeline in
            let tick = Int(timeline.date.timeIntervalSinceReferenceDate / WorkingIndicator.interval)
            Text(verbatim: WorkingIndicator.frames[abs(tick) % WorkingIndicator.frames.count])
                .font(.dm(10, design: .monospaced))
                .foregroundStyle(Color.dmMuted)
                .frame(width: 10)
        }
    }
}
