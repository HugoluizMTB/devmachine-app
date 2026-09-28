import SwiftUI

extension View {
    /// A filled shape with a hairline edge: the look of every card, field and
    /// floating bar in the app.
    func dmSurface<Fill: ShapeStyle, S: Shape>(
        _ fill: Fill, in shape: S, stroke: Color = .dmStroke, lineWidth: CGFloat = 0.5
    ) -> some View {
        background(fill, in: shape)
            .overlay(shape.stroke(stroke, lineWidth: lineWidth))
    }

    func dmSurface<Fill: ShapeStyle>(
        _ fill: Fill, radius: CGFloat, style: RoundedCornerStyle = .circular,
        stroke: Color = .dmStroke, lineWidth: CGFloat = 0.5
    ) -> some View {
        dmSurface(
            fill, in: RoundedRectangle(cornerRadius: radius, style: style),
            stroke: stroke, lineWidth: lineWidth)
    }

    /// Frosted glass over the wallpaper: palettes, cards, toasts.
    func dmGlass<S: Shape>(in shape: S, stroke: Color = .dmStroke) -> some View {
        dmSurface(.ultraThinMaterial, in: shape, stroke: stroke)
    }

    func dmGlass(
        radius: CGFloat, style: RoundedCornerStyle = .circular, stroke: Color = .dmStroke
    ) -> some View {
        dmGlass(in: RoundedRectangle(cornerRadius: radius, style: style), stroke: stroke)
    }
}

/// One key of a shortcut, e.g. ⌘ or K.
struct DMKeyCap: View {
    let key: String

    var body: some View {
        Text(verbatim: key)
            .font(.dm(11, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.dmRowText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .dmSurface(Color.dmFill, radius: DMRadius.keyCap)
    }
}

/// A capsule that picks one value out of a few, e.g. a wallpaper theme.
struct DMChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Text(verbatim: title)
            .font(.dm(11, weight: .medium))
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .dmSurface(
                selected ? Color.white.opacity(0.18) : Color.white.opacity(0.07),
                in: Capsule(),
                stroke: selected ? Color.accentColor : Color.dmStroke,
                lineWidth: selected ? 1 : 0.5)
            .contentShape(Capsule())
            .onTapGesture(perform: action)
    }
}
