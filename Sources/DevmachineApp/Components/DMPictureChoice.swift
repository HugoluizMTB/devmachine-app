import SwiftUI

/// A choice shown as a picture: a wallpaper, a kind of background. The
/// picture fills its frame and is cropped, never stretched; the title and
/// detail sit under it, the detail always two lines tall so a row of
/// choices lines up. The chosen one gets an accent ring and a check.
struct DMPictureChoice<Picture: View>: View {
    var title: String?
    var detail: String?
    let selected: Bool
    /// In points at 100%; the component scales it with the text size.
    var pictureHeight: CGFloat = 150
    let action: () -> Void
    @ViewBuilder var picture: () -> Picture
    @Environment(\.dmMetrics) private var m
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: m.radius.tile, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: m.pt(pictureHeight))
                    // A filled picture overflows its frame, and clipping does
                    // not clip hit-testing: the overflow would take the clicks
                    // of the next choice.
                    .overlay { picture().allowsHitTesting(false) }
                    .clipped()
                if title != nil || detail != nil {
                    caption
                }
            }
            .clipShape(shape)
            .background(selected ? Color.dmSelection : (hovering ? Color.dmHover : Color.dmBand), in: shape)
            .overlay(shape.strokeBorder(selected ? Color.accentColor : Color.dmStroke, lineWidth: selected ? 2 : 0.5))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.dm(DMIconSize.lg))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(m.space.md)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [title, detail].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: m.space.xxs) {
            if let title {
                Text(verbatim: title)
                    .font(.dm(12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(Color.dmRowText)
                    .lineLimit(1)
            }
            if let detail {
                Text(verbatim: detail)
                    .font(.dm(10.5))
                    .foregroundStyle(Color.dmMuted)
                    .lineLimit(2, reservesSpace: true)
            }
        }
        .padding(.horizontal, m.space.md)
        .padding(.vertical, m.space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
