import SwiftUI

/// A bare SF Symbol that acts as a button: refresh, close, add, the sidebar
/// footer. `size` nil keeps the font the button inherits, `tint` nil keeps the
/// inherited colour. `hitSize` is in points at 100% (`DMHitSize`). `fillsWidth` takes every point across and only the
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
    @Environment(\.dmMetrics) private var m

    var body: some View {
        let hitSize = style.hitSize.map(m.size)
        configuration.label
            .modifier(DMInheritableFont(size: style.size, weight: style.weight))
            .modifier(DMInheritableTint(tint: style.tint))
            .frame(width: style.fillsWidth ? nil : hitSize?.width,
                   height: hitSize?.height)
            .frame(maxWidth: style.fillsWidth ? .infinity : nil)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
    }
}

/// Nil leaves the environment alone, so the value set by a parent still applies.
struct DMInheritableFont: ViewModifier {
    let size: CGFloat?
    var weight: Font.Weight = .regular

    func body(content: Content) -> some View {
        if let size {
            content.font(.dm(size, weight: weight))
        } else {
            content
        }
    }
}

struct DMInheritableTint: ViewModifier {
    let tint: Color?

    func body(content: Content) -> some View {
        if let tint {
            content.foregroundStyle(tint)
        } else {
            content
        }
    }
}

struct DMIconButton: View {
    let systemImage: String
    let style: DMIconButtonStyle
    let action: () -> Void

    init(
        systemImage: String, size: CGFloat? = nil, weight: Font.Weight = .regular,
        tint: Color? = .dmMuted, hitSize: CGSize? = nil, fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.style = DMIconButtonStyle(
            size: size, weight: weight, tint: tint, hitSize: hitSize, fillsWidth: fillsWidth)
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(style)
    }
}

/// A small labelled chip whose background shows only under the pointer:
/// the shortcut chips, the suggested ports.
struct DMChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DMChipButtonBody(configuration: configuration)
    }
}

private struct DMChipButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.dmMetrics) private var m
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(Color.dmRowText)
            .padding(.horizontal, m.space.md)
            .padding(.vertical, m.space.xs)
            .background(hovering ? Color.dmHover : Color.clear, in: RoundedRectangle(cornerRadius: m.radius.keyCap))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == DMChipButtonStyle {
    static var dmChip: DMChipButtonStyle { DMChipButtonStyle() }
}
