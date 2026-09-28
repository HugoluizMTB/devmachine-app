import SwiftUI

/// Horizontal pill tab bar shared by the menubar popover and the context panel.
struct DMTabStrip<Tab: Hashable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String
    var systemImage: (Tab) -> String? = { _ in nil }
    var fontSize: CGFloat = 13
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 5
    var cornerRadius: CGFloat = DMRadius.control
    var spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(tabs, id: \.self) { tab in
                DMTabButton(
                    title: title(tab),
                    systemImage: systemImage(tab),
                    selected: tab == selection,
                    fontSize: fontSize,
                    horizontalPadding: horizontalPadding,
                    verticalPadding: verticalPadding,
                    cornerRadius: cornerRadius
                ) {
                    selection = tab
                }
            }
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}

private struct DMTabButton: View {
    let title: String
    let systemImage: String?
    let selected: Bool
    let fontSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .font(.dm(fontSize, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.dmRowText : Color.dmMuted)
                .padding(.vertical, verticalPadding)
                .padding(.horizontal, horizontalPadding)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(backgroundFill)
                )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: selected)
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }

    private var backgroundFill: Color {
        if selected {
            return Color.dmActive
        }
        return hovering ? Color.white.opacity(0.05) : Color.clear
    }
}
