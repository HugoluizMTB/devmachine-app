import SwiftUI
import AppKit
import MarkdownUI
import DevmachineCore

enum ANSIPalette {
    struct RGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }

    private static let base: [RGB] = [
        RGB(red: 0, green: 0, blue: 0), RGB(red: 0.80, green: 0.19, blue: 0.19), RGB(red: 0.05, green: 0.74, blue: 0.47),
        RGB(red: 0.90, green: 0.90, blue: 0.06), RGB(red: 0.14, green: 0.45, blue: 0.78), RGB(red: 0.74, green: 0.25, blue: 0.74),
        RGB(red: 0.07, green: 0.66, blue: 0.80), RGB(red: 0.90, green: 0.90, blue: 0.90),
        RGB(red: 0.40, green: 0.40, blue: 0.40), RGB(red: 0.95, green: 0.30, blue: 0.30), RGB(red: 0.14, green: 0.82, blue: 0.55),
        RGB(red: 0.96, green: 0.96, blue: 0.26), RGB(red: 0.23, green: 0.56, blue: 0.92), RGB(red: 0.84, green: 0.44, blue: 0.84),
        RGB(red: 0.16, green: 0.72, blue: 0.86), RGB(red: 1, green: 1, blue: 1),
    ]

    static func rgb(_ color: ANSIColor) -> RGB {
        switch color {
        case let .rgb(red, green, blue):
            return RGB(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
        case let .palette(index) where (0..<16).contains(index):
            return base[index]
        case let .palette(index) where (16..<232).contains(index):
            let cube = index - 16
            let level = { (step: Int) in step == 0 ? 0 : Double(55 + step * 40) / 255 }
            return RGB(red: level(cube / 36), green: level((cube / 6) % 6), blue: level(cube % 6))
        case let .palette(index):
            let gray = Double(8 + 10 * (min(max(index, 232), 255) - 232)) / 255
            return RGB(red: gray, green: gray, blue: gray)
        }
    }

    static func color(_ color: ANSIColor) -> Color {
        let value = rgb(color)
        return Color(.sRGB, red: value.red, green: value.green, blue: value.blue)
    }

    static func attributed(_ lines: [[ANSIRun]]) -> AttributedString {
        var result = AttributedString()
        for (index, runs) in lines.enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            for run in runs {
                var piece = AttributedString(run.text)
                if let foreground = run.foreground { piece.foregroundColor = color(foreground) }
                if let background = run.background { piece.backgroundColor = color(background) }
                if run.bold { piece.inlinePresentationIntent = .stronglyEmphasized }
                if run.underline { piece.underlineStyle = .single }
                result.append(piece)
            }
        }
        return result
    }
}

/// Text and stream lines, following the newest line.
struct TextLinesView: View {
    let lines: [String]
    let wrap: Bool
    let keepsColor: Bool

    var body: some View {
        ScrollView(wrap ? .vertical : [.vertical, .horizontal]) {
            Group {
                if keepsColor {
                    Text(ANSIPalette.attributed(ANSIText.lines(lines.joined(separator: "\n"))))
                } else {
                    Text(verbatim: lines.map(LogText.plain).joined(separator: "\n"))
                }
            }
            .font(.dm(11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .fixedSize(horizontal: !wrap, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: wrap ? .infinity : nil, alignment: .leading)
        }
        .defaultScrollAnchor(.bottomLeading)
    }
}

/// A read-only session screen. A click opens the session itself.
struct TerminalWidgetView: View {
    let text: String
    let tail: Int?
    let onOpen: (() -> Void)?

    var body: some View {
        TextLinesView(lines: TextTail.lines(of: text, tail: tail), wrap: false, keepsColor: true)
            .contentShape(Rectangle())
            .onTapGesture { onOpen?() }
            .help(Text(verbatim: onOpen == nil ? "A machine's admin sessions open from a terminal" : "Open this session"))
    }
}

/// The GitHub theme paints its own opaque page, which would cover the glass
/// card, so the text keeps the default theme in the card's colours.
struct MarkdownWidgetView: View {
    let text: String

    var body: some View {
        ScrollView(.vertical) {
            Markdown(text)
                .markdownTextStyle {
                    ForegroundColor(.white.opacity(0.9))
                    FontSize(DMFont.size(12))
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .environment(\.openURL, OpenURLAction { url in PreviewURLPolicy.isWeb(url) ? .systemAction : .discarded })
    }
}

struct ListWidgetView: View {
    static let rowHeight: CGFloat = 30

    let template: ListItemTemplate
    let output: SourceOutput
    let density: WidgetDensity
    @Environment(\.dmMetrics) private var m

    var body: some View {
        switch Result(catching: { try ListModel.items(output: output, template: template) }) {
        case let .success(items):
            GeometryReader { proxy in
                let fit = SourceWidgetLayout.listRows(height: proxy.size.height, rowHeight: m.pt(Self.rowHeight))
                let shown = items.count > fit ? max(1, fit - 1) : items.count
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items.prefix(shown)) { item in row(item) }
                    if items.count > shown {
                        Text(verbatim: "+\(items.count - shown) more")
                            .font(.dm(10))
                            .foregroundStyle(Color.dmMuted)
                    }
                }
            }
        case let .failure(error):
            SourceErrorView(state: DMErrorState(title: "This list cannot be shown", message: "\(error)"), density: density)
        }
    }

    private func row(_ item: DevmachineCore.ListItem) -> some View {
        HStack(spacing: m.space.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: item.title).font(.dm(11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(verbatim: subtitle).font(.dm(10)).foregroundStyle(Color.dmMuted).lineLimit(1)
                }
            }
            Spacer(minLength: m.space.xs)
            if let status = item.status { DMPill(text: status, color: .white.opacity(0.8)) }
        }
        .frame(height: m.pt(Self.rowHeight))
        .contentShape(Rectangle())
        .onTapGesture { if let link = item.link { NSWorkspace.shared.open(link) } }
        .help(Text(verbatim: item.link?.absoluteString ?? item.title))
    }
}
