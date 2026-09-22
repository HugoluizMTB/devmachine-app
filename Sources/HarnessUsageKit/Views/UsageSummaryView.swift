import SwiftUI

public struct UsageSummaryView: View {
    public let metrics: [UsageSummaryMetric]

    public init(metrics: [UsageSummaryMetric]) {
        self.metrics = metrics
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(metrics) { metric in
                HStack {
                    Text(verbatim: metric.label)
                        .foregroundColor(UsagePalette.secondaryText)
                    Spacer()
                    Text(verbatim: metric.value)
                        .foregroundColor(UsagePalette.primaryText)
                }
                .font(.caption)
            }
        }
    }
}
