import SwiftUI

/// A placeholder shaped like the content it stands in for, shown while a
/// view waits for its first answer. Wrap the placeholder layout in it; the
/// blocks inside share one shimmer, and VoiceOver hears a single "Loading".
struct DMSkeleton<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            .overlay {
                if !reduceMotion {
                    DMSkeletonShimmer()
                        .mask(content().environment(\.dmSkeletonMask, true))
                }
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
    }
}

/// How wide a skeleton bar is: all the room on offer, a share of it, or a
/// fixed size for something that never stretches (an icon, a count), in
/// points at 100%.
enum DMSkeletonWidth: Equatable {
    case fill
    case fraction(CGFloat)
    case fixed(CGFloat)

    /// A share that differs from row to row, so a column of bars reads as text.
    static func varied(_ index: Int, shares: [CGFloat] = [0.72, 0.5, 0.86, 0.6, 0.44, 0.78]) -> DMSkeletonWidth {
        .fraction(shares[abs(index) % shares.count])
    }
}

/// One rounded bar. `height` and `radius` are points at 100%.
struct DMSkeletonBlock: View {
    var width: DMSkeletonWidth = .fill
    var height: CGFloat
    var radius: CGFloat = DMRadius.terminal
    var alignment: HorizontalAlignment = .leading
    @Environment(\.dmSkeletonMask) private var isMask
    @Environment(\.dmMetrics) private var m

    var body: some View {
        let height = m.pt(height)
        switch width {
        case .fill:
            bar.frame(maxWidth: .infinity).frame(height: height)
        case .fixed(let points):
            bar.frame(width: m.pt(points), height: height)
        case .fraction(let share):
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay {
                    GeometryReader { proxy in
                        bar.frame(width: proxy.size.width * min(max(share, 0), 1))
                            .frame(width: proxy.size.width, alignment: Alignment(horizontal: alignment, vertical: .center))
                    }
                }
        }
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: m.pt(radius), style: .continuous)
            .fill(isMask ? Color.black : Color.dmSkeleton)
    }
}

/// A bar standing in for one line of text at `size`: as tall as that line
/// really is, so the real text lands where the bar was.
struct DMSkeletonText: View {
    let size: CGFloat
    var weight: Font.Weight = .regular
    var width: DMSkeletonWidth = .fill
    var alignment: HorizontalAlignment = .leading
    @Environment(\.dmMetrics) private var m

    var body: some View {
        Text(verbatim: " ")
            .font(.dm(size, weight: weight))
            .hidden()
            .frame(width: fixedWidth)
            .frame(maxWidth: fixedWidth == nil ? .infinity : nil)
            .overlay(alignment: Alignment(horizontal: alignment, vertical: .center)) {
                DMSkeletonBlock(
                    width: width, height: m.base((DMFont.size(size) * 0.72).rounded()), radius: 3,
                    alignment: alignment)
            }
    }

    private var fixedWidth: CGFloat? {
        if case .fixed(let points) = width { return m.pt(points) }
        return nil
    }
}

/// Repeats a placeholder row as many times as the height on offer holds, so a
/// tall window is not half empty and a short one does not overflow.
/// `rowHeight` is points at 100%.
struct DMSkeletonRows<Row: View>: View {
    let rowHeight: CGFloat
    var minimum = 2
    var maximum = 40
    @ViewBuilder var row: (Int) -> Row
    @Environment(\.dmMetrics) private var m

    var body: some View {
        GeometryReader { proxy in
            let fits = Int(proxy.size.height / max(m.pt(rowHeight), 1))
            let count = min(max(fits, minimum), maximum)
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    row(index)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .clipped()
    }
}

private struct DMSkeletonShimmer: View {
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

private struct DMSkeletonMaskKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside the copy of a skeleton used as the shimmer's mask, where
    /// every block is drawn opaque so the band shows at full strength.
    var dmSkeletonMask: Bool {
        get { self[DMSkeletonMaskKey.self] }
        set { self[DMSkeletonMaskKey.self] = newValue }
    }
}
