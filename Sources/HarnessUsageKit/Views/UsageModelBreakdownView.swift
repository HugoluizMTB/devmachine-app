import SwiftUI

public struct UsageModelBreakdownView: View {
    public let models: [ModelTokens]
    public let mostUsed: String?

    public init(models: [ModelTokens], mostUsed: String?) {
        self.models = models
        self.mostUsed = mostUsed
    }

    private var totalTokens: Int64 {
        models.reduce(0) { $0 + $1.tokens }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Usage by model (7 days)")
                .font(.caption)
                .bold()
                .foregroundColor(UsagePalette.primaryText)

            ForEach(models) { model in
                HStack {
                    Text(verbatim: model.model)
                        .font(.caption)
                        .foregroundColor(UsagePalette.primaryText)
                    Spacer()
                    let percent = totalTokens > 0 ? Double(model.tokens) / Double(totalTokens) * 100 : 0
                    Text(verbatim: "\(UsageFormat.tokens(model.tokens)) (\(String(format: "%.1f", percent))%)")
                        .font(.caption)
                        .foregroundColor(UsagePalette.secondaryText)
                }
            }

            Text(verbatim: "Most used model: \(mostUsed ?? "—")")
                .font(.caption)
                .bold()
                .foregroundColor(UsagePalette.primaryText)
        }
    }
}
