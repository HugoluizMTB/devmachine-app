import SwiftUI

public struct UsageBarsView: View {
    public let blocks: [UsageBlock]
    public let accent: Color

    public init(blocks: [UsageBlock], accent: Color) {
        self.blocks = blocks
        self.accent = accent
    }

    public init(blocks: [UsageBlock]) {
        self.init(blocks: blocks, accent: UsagePalette.accent)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                UsageBarRow(block: block, accent: accent)
            }
        }
    }
}

private struct UsageBarRow: View {
    let block: UsageBlock
    let accent: Color

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
                        .fill(accent)
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
