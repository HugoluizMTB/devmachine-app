import AppKit
import SwiftUI

/// Shell commands to select or copy, one per line, with a single Copy button
/// that takes them all.
struct DMCommandBlock: View {
    let lines: [String]
    /// A narrow place (the sidebar) wraps a long command instead of cutting
    /// its middle out, which would hide the part that matters.
    var wraps = false
    @Environment(\.dmMetrics) private var m

    init(_ lines: [String], wraps: Bool = false) {
        self.lines = lines
        self.wraps = wraps
    }

    init(_ command: String, wraps: Bool = false) {
        self.lines = [command]
        self.wraps = wraps
    }

    var body: some View {
        HStack(alignment: lines.count > 1 ? .top : .center) {
            VStack(alignment: .leading, spacing: m.space.xs) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .font(.dm(11.5, design: .monospaced))
                        .foregroundStyle(Color.dmRowText)
                        .lineLimit(wraps ? nil : 1)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: wraps)
                }
            }
            .textSelection(.enabled)
            Spacer(minLength: m.space.lg)
            DMCopyButton(text: lines.joined(separator: "\n"))
        }
        .padding(.horizontal, m.space.lg)
        .padding(.vertical, m.space.md)
        .dmSurface(Color.dmSelection, radius: DMRadius.control)
    }
}

struct DMCopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        DMButton(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc",
                 variant: .ghost, size: .small) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        }
    }
}
