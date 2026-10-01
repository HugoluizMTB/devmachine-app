import SwiftUI

/// A magnifying glass and a borderless field, with room for trailing
/// controls (a count, a clear button, a close button). Sizes are points at 100%.
struct DMSearchField<Trailing: View>: View {
    let prompt: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding?
    var fontSize: CGFloat = 12
    var iconSize: CGFloat = 11
    var spacing: CGFloat = 8
    var iconColor: Color = .dmMuted
    var textColor: Color?
    var fieldWidth: CGFloat?
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dmMetrics) private var m

    var body: some View {
        HStack(spacing: m.pt(spacing)) {
            Image(systemName: "magnifyingglass")
                .font(.dm(iconSize))
                .foregroundStyle(iconColor)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.dm(fontSize))
                .modifier(DMInheritableTint(tint: textColor))
                .frame(width: fieldWidth.map(m.pt))
                .modifier(DMOptionalFocus(focus: focus))
            trailing()
        }
    }
}

extension DMSearchField where Trailing == EmptyView {
    init(
        prompt: String, text: Binding<String>, focus: FocusState<Bool>.Binding? = nil,
        fontSize: CGFloat = 12, iconSize: CGFloat = 11, spacing: CGFloat = 8,
        iconColor: Color = .dmMuted, textColor: Color? = nil, fieldWidth: CGFloat? = nil
    ) {
        self.init(
            prompt: prompt, text: text, focus: focus, fontSize: fontSize, iconSize: iconSize,
            spacing: spacing, iconColor: iconColor, textColor: textColor,
            fieldWidth: fieldWidth, trailing: { EmptyView() })
    }
}

private struct DMOptionalFocus: ViewModifier {
    let focus: FocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        if let focus {
            content.focused(focus)
        } else {
            content
        }
    }
}

extension View {
    /// A text field on a dark translucent surface: the Settings page's inputs.
    func dmField() -> some View {
        modifier(DMFieldModifier())
    }
}

private struct DMFieldModifier: ViewModifier {
    @Environment(\.dmMetrics) private var m

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.dm(DMMetrics.baseFontSize))
            .foregroundStyle(.white)
            .padding(.horizontal, m.row.horizontal)
            .padding(.vertical, m.row.vertical)
            .dmSurface(Color.dmSelection, radius: DMRadius.row, style: .continuous)
    }
}
