import SwiftUI

/// A usage card before its first snapshot: limit bars, the Stats header, a
/// bar chart and the per-model rows, drawn as placeholders that stretch with
/// the card. Every harness uses this one.
public struct UsageCardSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        shapes(mask: false)
            .overlay {
                if !reduceMotion {
                    UsageSkeletonShimmer().mask(shapes(mask: true))
                }
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
    }

    private func shapes(mask: Bool) -> some View {
        VStack(alignment: .leading, spacing: UsagePanelMetrics.contentSpacing) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(0..<3, id: \.self) { index in
                    limitBlock(index)
                }
            }
            Rectangle().fill(UsagePalette.divider).frame(height: 1)
            VStack(alignment: .leading, spacing: 14) {
                Text(verbatim: "Stats")
                    .font(.headline)
                    .foregroundColor(UsagePalette.primaryText)
                UsageSkeletonLine(font: .caption, share: 0.42)
                chart
                models
            }
        }
        .environment(\.usageSkeletonMask, mask)
    }

    private func limitBlock(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                UsageSkeletonLine(font: .headline, share: [0.34, 0.5, 0.44][index])
                Spacer(minLength: 12)
                UsageSkeletonLine(font: .caption, share: 1)
                    .frame(width: 88)
            }
            UsageSkeletonBar(height: 8, radius: 4)
            UsageSkeletonLine(font: .caption, share: 0.18)
        }
    }

    private static let barHeights: [CGFloat] = [0.45, 0.7, 0.35, 0.9, 0.6, 0.8, 0.5]

    private var chart: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Self.barHeights.indices, id: \.self) { index in
                        UsageSkeletonBar(height: 100 * Self.barHeights[index], radius: 3)
                    }
                }
                .frame(height: 104, alignment: .bottom)
                .padding(.horizontal, 16)
                UsageSkeletonBar(height: 1, radius: 0)
                HStack(spacing: 10) {
                    ForEach(Self.barHeights.indices, id: \.self) { _ in
                        UsageSkeletonBar(height: 7, radius: 2)
                            .padding(.horizontal, 6)
                    }
                }
                .padding(.horizontal, 16)
            }
            VStack(alignment: .leading) {
                ForEach(0..<3, id: \.self) { _ in
                    UsageSkeletonBar(height: 7, radius: 2)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: 28, height: 118)
        }
        .frame(height: 140, alignment: .bottom)
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: 6) {
            UsageSkeletonLine(font: .caption.bold(), share: 0.4)
            ForEach(0..<3, id: \.self) { index in
                HStack {
                    UsageSkeletonLine(font: .caption, share: [0.5, 0.42, 0.36][index])
                    Spacer(minLength: 12)
                    UsageSkeletonLine(font: .caption, share: 1)
                        .frame(width: 72)
                }
            }
            UsageSkeletonLine(font: .caption.bold(), share: 0.5)
        }
    }
}

/// One line of text at `font`, as tall as that line and `share` as wide as
/// the room on offer.
struct UsageSkeletonLine: View {
    let font: Font
    let share: CGFloat

    var body: some View {
        Text(verbatim: " ")
            .font(font)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    UsageSkeletonBar(height: proxy.size.height * 0.62, radius: 3)
                        .frame(width: proxy.size.width * share)
                        .frame(maxHeight: .infinity)
                }
            }
    }
}

struct UsageSkeletonBar: View {
    let height: CGFloat
    let radius: CGFloat
    @Environment(\.usageSkeletonMask) private var isMask

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(isMask ? Color.black : UsagePalette.skeleton)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}

private struct UsageSkeletonShimmer: View {
    @State private var sweeping = false

    var body: some View {
        GeometryReader { proxy in
            let band = max(proxy.size.width * 0.5, 80)
            LinearGradient(
                colors: [.clear, .white.opacity(0.06), .clear],
                startPoint: .leading, endPoint: .trailing)
                .frame(width: band)
                .offset(x: sweeping ? proxy.size.width : -band)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                sweeping = true
            }
        }
    }
}

private struct UsageSkeletonMaskKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var usageSkeletonMask: Bool {
        get { self[UsageSkeletonMaskKey.self] }
        set { self[UsageSkeletonMaskKey.self] = newValue }
    }
}
