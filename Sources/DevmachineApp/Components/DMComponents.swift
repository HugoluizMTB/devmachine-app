import SwiftUI

/// Rounded selection/hover background shared by list rows across the app.
struct DMRowBackground: View {
    let selected: Bool
    var hovering: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(selected ? Color.dmSelection : (hovering ? Color.dmHover : .clear))
    }
}

/// A leading-glyph, title, optional-trailing list row with selection/hover background.
/// Mirrors `SidebarView`'s session/footer rows exactly.
struct DMRow: View {
    let systemImage: String
    let iconColor: Color
    var iconSize: CGFloat = 7
    let title: String
    var titleColor: Color = .dmRowText
    var selected: Bool = false
    var outerHorizontalPadding: CGFloat = 6
    /// Pushes trailing to the right and makes the background fill the full width.
    /// List rows (default). The operador footer passes false to hug the text.
    var fillWidth: Bool = true
    var trailing: AnyView?
    var tap: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        let content = HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(titleColor)
                .lineLimit(1)
            if fillWidth { Spacer() }
            if let trailing { trailing }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DMRowBackground(selected: selected, hovering: hovering))
        .padding(.horizontal, outerHorizontalPadding)
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

/// Uppercase-ish muted section title + optional trailing (count/button) + content below.
/// Mirrors `SidebarView`'s group headers/top bar and `ContextPanel`'s sections.
struct DMSection<Label: View, Trailing: View, Content: View>: View {
    var headerSpacing: CGFloat = 4
    var contentSpacing: CGFloat = 0
    var padding: EdgeInsets
    var showBottomDivider: Bool = false
    @ViewBuilder var label: () -> Label
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            HStack(spacing: headerSpacing) {
                label()
                Spacer()
                trailing()
            }
            content()
        }
        .padding(padding)
        .overlay(alignment: .bottom) {
            if showBottomDivider {
                Rectangle().fill(Color.dmDivider).frame(height: 1)
            }
        }
    }
}

extension DMSection where Trailing == EmptyView {
    init(
        headerSpacing: CGFloat = 4,
        contentSpacing: CGFloat = 0,
        padding: EdgeInsets,
        showBottomDivider: Bool = false,
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            headerSpacing: headerSpacing,
            contentSpacing: contentSpacing,
            padding: padding,
            showBottomDivider: showBottomDivider,
            label: label,
            trailing: { EmptyView() },
            content: content
        )
    }
}

extension DMSection where Content == EmptyView {
    init(
        headerSpacing: CGFloat = 4,
        padding: EdgeInsets,
        showBottomDivider: Bool = false,
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(
            headerSpacing: headerSpacing,
            contentSpacing: 0,
            padding: padding,
            showBottomDivider: showBottomDivider,
            label: label,
            trailing: trailing,
            content: { EmptyView() }
        )
    }
}

/// Small capsule label, e.g. CI status or a source badge. Mirrors `ContextPanel`'s pills.
struct DMPill: View {
    let text: String
    let color: Color
    var font: Font = .system(size: 10, weight: .semibold)
    var backgroundOpacity: Double = 0.15
    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 1

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(color.opacity(backgroundOpacity), in: Capsule())
    }
}

/// Thin rounded progress bar, e.g. plan done/total. Mirrors `ContextPanel.progressBar`.
struct DMProgressBar: View {
    let done: Int
    let total: Int
    var fillColor: Color = .green
    var trackColor: Color = .dmDivider
    var barHeight: CGFloat = 5
    var cornerRadius: CGFloat = 3

    var body: some View {
        let fraction = total > 0 ? min(max(Double(done) / Double(total), 0), 1) : 0
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(trackColor)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(fillColor)
                        .frame(width: geo.size.width * fraction)
                }
        }
        .frame(height: barHeight)
    }
}

/// String-valued stat bubble, e.g. "14.8 / 31 GB". Mirrors `HomeView`'s private `StatBubble`.
struct DMStatBubble: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(verbatim: value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}

/// Floating background-task toast. Moved verbatim from `ContentView.ToastCard`.
struct DMToastCard: View {
    let task: BGTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(task.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if task.completed >= task.total {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                } else {
                    Text("\(task.completed) de \(task.total)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(task.completed), total: Double(max(task.total, 1)))
                .progressViewStyle(.linear)
                .frame(width: 200)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(radius: 10, y: 3)
    }
}
