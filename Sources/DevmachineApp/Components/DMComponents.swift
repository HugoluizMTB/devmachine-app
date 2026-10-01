import SwiftUI

/// Rounded selection/hover background shared by list rows across the app.
/// `cornerRadius` is points at 100%.
struct DMRowBackground: View {
    let selected: Bool
    var hovering: Bool = false
    var cornerRadius: CGFloat = DMRadius.row
    var style: RoundedCornerStyle = .circular
    var selectedColor: Color = .dmSelection
    @Environment(\.dmMetrics) private var m

    var body: some View {
        RoundedRectangle(cornerRadius: m.pt(cornerRadius), style: style)
            .fill(selected ? selectedColor : (hovering ? Color.dmHover : .clear))
    }
}

/// A leading-glyph, title, optional-trailing list row with selection/hover background.
/// Mirrors `SidebarView`'s session/footer rows exactly. Sizes are points at 100%.
struct DMRow: View {
    /// No glyph at all when nil: a row that is fine has nothing to say, and a
    /// column of dots down the sidebar says nothing while looking like an alarm.
    var systemImage: String?
    var iconColor: Color = .dmMuted
    var iconSize: CGFloat = DMIconSize.dot
    /// Drawn in place of `systemImage` when the glyph needs more than a name
    /// and a colour, such as a spoken label.
    var leading: AnyView?
    let title: String
    var titleColor: Color = .dmRowText
    var selected: Bool = false
    var outerHorizontalPadding: CGFloat = DMRowInset.outer
    /// Pushes trailing to the right and makes the background fill the full width.
    /// List rows (default). The ops footer passes false to hug the text.
    var fillWidth: Bool = true
    var trailing: AnyView?
    /// Shown before `trailing`, and only while the pointer is on the row.
    var trailingHover: AnyView?
    var tap: (() -> Void)?
    @Environment(\.dmMetrics) private var m
    @State private var hovering = false

    var body: some View {
        let content = HStack(spacing: m.space.md) {
            if let leading {
                leading
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.dm(iconSize))
                    .foregroundStyle(iconColor)
            }
            Text(title)
                .font(.dm(DMMetrics.baseFontSize))
                .foregroundStyle(titleColor)
                .lineLimit(1)
            if fillWidth { Spacer() }
            if hovering, let trailingHover { trailingHover }
            if let trailing { trailing }
        }
        .padding(.horizontal, m.row.horizontal)
        .padding(.vertical, m.row.vertical)
        .background(DMRowBackground(selected: selected, hovering: hovering))
        .padding(.horizontal, m.pt(outerHorizontalPadding))
        .contentShape(Rectangle())
        // Hover on the whole row shape, not on the background: children (text,
        // count) sit on top and would otherwise steal the hover from the background.
        .onHover { hovering = $0 }

        // Only attach a tap recognizer when this row owns its tap. Rows wrapped in
        // a Button pass tap == nil, so the Button (not a competing gesture) handles clicks.
        if let tap {
            content.onTapGesture { tap() }
        } else {
            content
        }
    }
}

/// The app's one line. Areas are told apart by spacing and tint first; this
/// is for the rare place where nothing else says where one ends.
struct DMHairline: View {
    var axis: Axis = .horizontal

    var body: some View {
        Rectangle()
            .fill(Color.dmDivider)
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
    }
}

/// A table row without a separator: every other row carries a faint tint
/// and the row under the pointer a stronger one.
struct DMTableRow<Content: View>: View {
    let index: Int
    @ViewBuilder var content: () -> Content
    @Environment(\.dmMetrics) private var m
    @State private var hovering = false

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: m.radius.row, style: .continuous)
                    .fill(fill))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }

    private var fill: Color {
        if hovering { return .dmHover }
        return index.isMultiple(of: 2) ? .clear : .dmStripe
    }
}

/// Uppercase-ish muted section title + optional trailing (count/button) + content below.
/// Mirrors `SidebarView`'s group headers/top bar and `ContextPanel`'s sections.
/// Spacing and padding are points at 100% (`DMSectionInset`).
struct DMSection<Label: View, Trailing: View, Content: View>: View {
    var headerSpacing: CGFloat = DMSpace.xs
    var contentSpacing: CGFloat = 0
    var padding: EdgeInsets
    @ViewBuilder var label: () -> Label
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    @Environment(\.dmMetrics) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: m.pt(contentSpacing)) {
            HStack(spacing: m.pt(headerSpacing)) {
                label()
                Spacer()
                trailing()
            }
            content()
        }
        .padding(m.insets(padding))
    }
}

extension DMSection where Trailing == EmptyView {
    init(
        headerSpacing: CGFloat = DMSpace.xs,
        contentSpacing: CGFloat = 0,
        padding: EdgeInsets,
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            headerSpacing: headerSpacing,
            contentSpacing: contentSpacing,
            padding: padding,
            label: label,
            trailing: { EmptyView() },
            content: content
        )
    }
}

extension DMSection where Content == EmptyView {
    init(
        headerSpacing: CGFloat = DMSpace.xs,
        padding: EdgeInsets,
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(
            headerSpacing: headerSpacing,
            contentSpacing: 0,
            padding: padding,
            label: label,
            trailing: trailing,
            content: { EmptyView() }
        )
    }
}

/// Muted bold title for a `DMSection` header, e.g. AGENTS, HISTORY.
struct DMSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.dm(10, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(Color.dmMuted)
    }
}

/// Muted bold value on the trailing edge of a `DMSection` header, e.g. a count.
struct DMSectionValue: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.dm(10, weight: .bold))
            .foregroundStyle(Color.dmMuted)
    }
}

/// Small capsule label, e.g. CI status or a source badge. Mirrors `ContextPanel`'s pills.
/// Paddings are points at 100%.
struct DMPill: View {
    let text: String
    let color: Color
    var font: Font = .dm(10, weight: .semibold)
    var backgroundOpacity: Double = 0.15
    var horizontalPadding: CGFloat = DMSpace.sm
    var verticalPadding: CGFloat = 1
    @Environment(\.dmMetrics) private var m

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, m.pt(horizontalPadding))
            .padding(.vertical, m.pt(verticalPadding))
            .background(color.opacity(backgroundOpacity), in: Capsule())
    }
}

/// Thin rounded progress bar, e.g. plan done/total. Mirrors `ContextPanel.progressBar`.
/// `barHeight` and `cornerRadius` are points at 100%.
struct DMProgressBar: View {
    let done: Int
    let total: Int
    var fillColor: Color = .green
    var trackColor: Color = .dmDivider
    var barHeight: CGFloat = 5
    var cornerRadius: CGFloat = 3
    @Environment(\.dmMetrics) private var m

    /// How full the bar is, from 0 to 1. A zero or negative total reads as
    /// "nothing to do", not as division by zero.
    static func fraction(done: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(done) / Double(total), 0), 1)
    }

    var body: some View {
        // The fill is scaled, not measured: a `GeometryReader` here reported the
        // width of a container the bar was not drawn in, so the track spanned
        // the window while the fill stopped at the sidebar's edge.
        RoundedRectangle(cornerRadius: m.pt(cornerRadius))
            .fill(trackColor)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: m.pt(cornerRadius))
                    .fill(fillColor)
                    .scaleEffect(
                        x: Self.fraction(done: done, total: total), y: 1, anchor: .leading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: m.pt(barHeight))
    }
}

/// String-valued stat bubble, e.g. "14.8 / 31 GB". Mirrors `HomeView`'s private `StatBubble`.
struct DMStatBubble: View {
    let value: String
    let label: String
    @Environment(\.dmMetrics) private var m

    var body: some View {
        VStack(spacing: m.pt(3)) {
            Text(verbatim: value)
                .font(.dm(24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.dm(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, m.pt(14))
        .padding(.horizontal, m.space.xl)
        .dmGlass(radius: DMRadius.bubble, stroke: .white.opacity(0.15))
    }
}

/// Floating background-task toast. Moved verbatim from `ContentView.ToastCard`.
struct DMToastCard: View {
    let task: BGTask
    var onAction: (() -> Void)? = nil

    @Environment(\.dmMetrics) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            HStack(spacing: m.row.horizontal) {
                Text(task.label)
                    .font(.dm(12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: m.space.sm)
                if task.completed >= task.total {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.dm(12))
                } else if task.showsCount {
                    // `Text("\(int)")` localizes: pt-BR renders 5182 as 5.182.
                    Text(verbatim: "\(task.completed) of \(task.total)")
                        .font(.dm(11))
                        .foregroundStyle(.secondary)
                }
            }
            // The app's own bar, not the system one: the native linear
            // ProgressView drew its track across the window while the fill
            // stopped short.
            DMProgressBar(done: task.completed, total: task.total, fillColor: .accentColor)
            if let action = task.action, let onAction {
                DMButton(action.title, variant: .link, size: .small, action: onAction)
            }
        }
        // The card is as wide as its bar, and no wider. The `Spacer` that pushes
        // the count to the right would otherwise take every point on offer, and the
        // card stretched to the window's edge with a short bar sitting in it.
        .frame(width: m.card.toast, alignment: .leading)
        .dmToastChrome()
    }
}
