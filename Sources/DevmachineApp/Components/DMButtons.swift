import SwiftUI

/// A bare SF Symbol that acts as a button: refresh, close, add, the sidebar
/// footer. `size` nil keeps the font the button inherits, `tint` nil keeps the
/// inherited colour. `fillsWidth` takes every point across and only the
/// height of `hitSize`.
struct DMIconButtonStyle: ButtonStyle {
    var size: CGFloat?
    var weight: Font.Weight = .regular
    var tint: Color? = .dmMuted
    var hitSize: CGSize?
    var fillsWidth = false

    func makeBody(configuration: Configuration) -> some View {
        DMIconButtonBody(style: self, configuration: configuration)
    }
}

private struct DMIconButtonBody: View {
    let style: DMIconButtonStyle
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(style.size.map { .dm($0, weight: style.weight) })
            .foregroundStyle(style.tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground))
            .frame(width: style.fillsWidth ? nil : style.hitSize?.width,
                   height: style.hitSize?.height)
            .frame(maxWidth: style.fillsWidth ? .infinity : nil)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
    }
}

extension ButtonStyle where Self == DMIconButtonStyle {
    static func dmIcon(
        size: CGFloat? = nil, weight: Font.Weight = .regular, tint: Color? = .dmMuted,
        hitSize: CGSize? = nil, fillsWidth: Bool = false
    ) -> DMIconButtonStyle {
        DMIconButtonStyle(
            size: size, weight: weight, tint: tint, hitSize: hitSize, fillsWidth: fillsWidth)
    }
}

struct DMIconButton: View {
    let systemImage: String
    var size: CGFloat?
    var weight: Font.Weight = .regular
    var tint: Color? = .dmMuted
    var hitSize: CGSize?
    var fillsWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.dmIcon(
            size: size, weight: weight, tint: tint, hitSize: hitSize, fillsWidth: fillsWidth))
    }
}

/// A small labelled button. Ghost shows its background only under the
/// pointer (the shortcut chips); prominent always does (a row's inline action).
struct DMChipButtonStyle: ButtonStyle {
    enum Kind { case ghost, prominent }

    var kind: Kind = .ghost

    func makeBody(configuration: Configuration) -> some View {
        DMChipButtonBody(kind: kind, configuration: configuration)
    }
}

private struct DMChipButtonBody: View {
    let kind: DMChipButtonStyle.Kind
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(kind == .prominent ? Color.white.opacity(0.9) : Color.dmRowText)
            .padding(.horizontal, kind == .prominent ? 7 : 8)
            .padding(.vertical, kind == .prominent ? 3 : 4)
            .background(fill, in: RoundedRectangle(cornerRadius: DMRadius.keyCap))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onHover { hovering = $0 }
    }

    private var fill: Color {
        switch kind {
        case .prominent: return Color.white.opacity(0.14)
        case .ghost: return hovering ? Color.dmHover : Color.clear
        }
    }
}

extension ButtonStyle where Self == DMChipButtonStyle {
    static var dmChip: DMChipButtonStyle { DMChipButtonStyle() }
    static var dmChipProminent: DMChipButtonStyle { DMChipButtonStyle(kind: .prominent) }
}

/// Plain text that acts as a secondary action, e.g. "Use remote fallback".
struct DMTextButtonStyle: ButtonStyle {
    var tint: Color = .dmMuted

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == DMTextButtonStyle {
    static func dmText(tint: Color = .dmMuted) -> DMTextButtonStyle {
        DMTextButtonStyle(tint: tint)
    }
}
