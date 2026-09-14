import SwiftUI
import AppKit
import DevmachineCore

// Model + pure logic live in DevmachineCore. Colors/glyphs are UI-only, so
// they live here rather than in Core.

extension CIState {
    var glyph: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .pending: return "circle.dotted"
        case .none: return "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .success: return .green
        case .failure: return .red
        case .pending: return Color(red: 0.98, green: 0.75, blue: 0.18)
        case .none: return .secondary
        }
    }

    var help: String {
        switch self {
        case .success: return "Checks passing"
        case .failure: return "Checks failing"
        case .pending: return "Checks running"
        case .none: return "No checks"
        }
    }
}

extension RowState {
    var color: Color {
        switch self {
        case .draft: return .secondary
        case .changesRequested: return Color(red: 0.90, green: 0.29, blue: 0.36)
        case .approved: return .green
        case .open: return Color(red: 0.39, green: 0.40, blue: 0.95)
        }
    }
}

struct PRRowView: View {
    let pr: PullRequest
    let depth: Int

    var body: some View {
        HStack(spacing: 0) {
            if depth > 0 { indent }
            DMRow(
                systemImage: "circle.fill",
                iconColor: pr.rowState.color,
                iconSize: 8,
                title: pr.title,
                trailing: AnyView(trailing),
                tap: open
            )
            .help(pr.rowState.label)
        }
    }

    private var trailing: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: "#\(pr.number)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(pr.ci.color.opacity(0.9))
                    Text(pr.repo)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Image(systemName: pr.ci.glyph)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(pr.ci.color)
                .frame(width: 24, height: 24)
                .background(pr.ci.color.opacity(0.12))
                .clipShape(Circle())
                .help(pr.ci.help)
        }
    }

    private var indent: some View {
        HStack(spacing: 0) {
            ForEach(0..<depth, id: \.self) { _ in
                Rectangle().fill(Color.secondary.opacity(0.25))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
                    .frame(width: 13, alignment: .center)
            }
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func open() {
        guard let url = URL(string: pr.url) else { return }
        NSWorkspace.shared.open(url)
    }
}
