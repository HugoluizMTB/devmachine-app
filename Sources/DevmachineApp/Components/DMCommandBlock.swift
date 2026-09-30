import AppKit
import SwiftUI

/// Shell commands to select or copy, one per line, with a single Copy button
/// that takes them all.
struct DMCommandBlock: View {
    let lines: [String]

    init(_ lines: [String]) {
        self.lines = lines
    }

    init(_ command: String) {
        self.lines = [command]
    }

    var body: some View {
        HStack(alignment: lines.count > 1 ? .top : .center) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .font(.dm(11.5, design: .monospaced))
                        .foregroundStyle(Color.dmRowText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .textSelection(.enabled)
            Spacer(minLength: 12)
            DMCopyButton(text: lines.joined(separator: "\n"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
