import SwiftUI

/// A card to pick one option, or to turn one on among several: what kind of
/// machine to add, which packages go on it. The whole card is the button.
struct DMChoiceCard: View {
    let title: String
    var systemImage: String?
    var detail: String
    /// A quiet tag after the title (RECOMMENDED, YOURS).
    var badge: String?
    let selected: Bool
    /// A checkbox when several can be on, a radio mark when only one.
    var multiple = false
    let action: () -> Void
    @Environment(\.dmMetrics) private var m
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: m.space.md) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.dm(DMIconSize.lg))
                        .foregroundStyle(selected ? Color.accentColor : Color.dmMuted)
                        .frame(width: m.pt(DMIconSize.lg) + m.space.md)
                }
                VStack(alignment: .leading, spacing: m.space.xs) {
                    HStack(spacing: m.space.sm) {
                        Text(verbatim: title)
                            .font(.dm(12.5, weight: .semibold))
                            .foregroundStyle(Color.dmRowText)
                        if let badge { DMKindLabel(text: badge) }
                    }
                    Text(verbatim: detail)
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: mark)
                    .font(.dm(DMIconSize.md))
                    .foregroundStyle(selected ? Color.accentColor : Color.dmMuted)
            }
            .padding(m.space.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .dmSurface(
                selected ? Color.dmSelection : (hovering && isEnabled ? Color.dmHover : Color.dmBand),
                radius: DMRadius.panel,
                stroke: selected ? Color.accentColor.opacity(0.7) : Color.dmStroke)
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var mark: String {
        switch (multiple, selected) {
        case (true, true): return "checkmark.square.fill"
        case (true, false): return "square"
        case (false, true): return "checkmark.circle.fill"
        case (false, false): return "circle"
        }
    }
}
