import SwiftUI

public struct UsageBarsView: View {
    public let blocks: [UsageBlock]

    public init(blocks: [UsageBlock]) {
        self.blocks = blocks
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                UsageBarRow(block: block)
            }
        }
    }
}

private struct UsageBarRow: View {
    let block: UsageBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: block.label)
                    .font(.headline)
                    .foregroundColor(UsagePalette.primaryText)
                Spacer()
                if !block.resets.isEmpty {
                    Text(verbatim: "resets \(block.resets)")
                        .font(.caption)
                        .foregroundColor(UsagePalette.secondaryText)
                }
            }

            GeometryReader { geometry in
                let fraction = min(max(Double(block.percent) / 100.0, 0), 1)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(UsagePalette.track)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(UsagePalette.accent)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 8)

            Text(verbatim: "\(block.percent)% used")
                .font(.caption)
                .foregroundColor(UsagePalette.secondaryText)
        }
    }
}
