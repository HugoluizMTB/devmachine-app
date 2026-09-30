import SwiftUI

public struct UsageHeaderView: View {
    public let title: String
    public let systemImage: String
    public let refreshedAt: Date?
    public let onRefresh: () -> Void
    /// Holds the "Refreshed at" line's place while the first snapshot loads.
    public let reservesSubtitle: Bool

    public init(
        title: String, systemImage: String, refreshedAt: Date?, reservesSubtitle: Bool = false,
        onRefresh: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.refreshedAt = refreshedAt
        self.reservesSubtitle = reservesSubtitle
        self.onRefresh = onRefresh
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label {
                    Text(verbatim: title)
                } icon: {
                    Image(systemName: systemImage)
                }
                    .font(.title2)
                    .bold()
                    .foregroundColor(UsagePalette.primaryText)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }

            if let refreshedAt {
                Text(verbatim: "Refreshed at \(Self.timeFormatter.string(from: refreshedAt))")
                    .font(.caption)
                    .foregroundColor(UsagePalette.secondaryText)
            } else if reservesSubtitle {
                UsageSkeletonLine(font: .caption, share: 0.3)
                    .accessibilityHidden(true)
            }
        }
    }
}
