import DevmachineCore
import SwiftUI

/// A program's output as it comes, like a terminal: monospaced, readable
/// on a dark surface, following the last line, with the whole log a click
/// from the clipboard. Short, it grows to a taller box on Expand; `fills`
/// takes all the height it is given (a run screen).
struct DMLogView: View {
    let lines: [String]
    var fills = false
    /// What the header names the log, e.g. "Output".
    var title = "Log"
    /// In points at 100%, for the box that does not fill.
    var collapsedHeight: CGFloat = 140
    var expandedHeight: CGFloat = 420
    @Environment(\.dmMetrics) private var m
    @State private var expanded = false

    private var shown: [String] { lines.map(LogText.plain) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: m.space.xxs) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { index, line in
                            Text(verbatim: line.isEmpty ? " " : line)
                                .font(.dm(11, design: .monospaced))
                                .foregroundStyle(line.hasPrefix("$ ") || line.hasPrefix("▸ ")
                                    ? Color.dmRowText : Color.dmRowText.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(m.space.md)
                }
                .defaultScrollAnchor(.bottom)
                .onAppear { scrollToEnd(proxy) }
                .onChange(of: lines.count) { _, _ in scrollToEnd(proxy) }
            }
            .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil)
            .frame(height: fills ? nil : m.pt(expanded ? expandedHeight : collapsedHeight))
        }
        .dmSurface(Color.black.opacity(0.55), radius: DMRadius.control)
    }

    private var header: some View {
        HStack(spacing: m.space.sm) {
            Text(verbatim: lines.isEmpty ? title : "\(title) · \(lines.count) lines")
                .font(.dm(10.5, weight: .semibold))
                .foregroundStyle(Color.dmMuted)
            Spacer(minLength: m.space.sm)
            if !fills {
                DMButton(expanded ? "Collapse" : "Expand",
                         systemImage: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                         variant: .ghost, size: .small) { expanded.toggle() }
            }
            DMCopyButton(text: shown.joined(separator: "\n"), title: "Copy log")
                .disabled(lines.isEmpty)
        }
        .padding(.horizontal, m.space.md)
        .padding(.vertical, m.space.xs)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard !lines.isEmpty else { return }
        proxy.scrollTo(lines.count - 1, anchor: .bottom)
    }
}
