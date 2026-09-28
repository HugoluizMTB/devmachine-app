import SwiftUI

/// What a panel shows in place of its content: still loading, nothing to
/// show, or a read that failed (with Retry).
struct DMStatusView: View {
    enum Kind {
        case loading(String)
        case empty(systemImage: String, text: String)
        case failed(title: String? = nil, message: String, retry: (() -> Void)?)
    }

    let kind: Kind
    /// Pages center the state in all the room they have; a list that sits
    /// under a header keeps it near the top.
    var fillsHeight = true

    var body: some View {
        content
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .loading(let text):
            VStack(spacing: 8) {
                ProgressView()
                caption(text)
            }
        case .empty(let systemImage, let text):
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(.secondary)
                caption(text)
            }
        case .failed(let title, let message, let retry):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.orange)
                if let title {
                    Text(title)
                        .font(.dm(12, weight: .semibold))
                        .foregroundStyle(Color.dmRowText)
                }
                // A CLI's stderr can run to a traceback; the cap keeps Retry
                // inside a narrow panel, and the tooltip holds the rest.
                caption(message)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(message)
                if let retry {
                    Button("Retry", action: retry)
                }
            }
            .multilineTextAlignment(.center)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.dm(12))
            .foregroundStyle(.secondary)
    }
}

/// A strip above content that stays usable: a failed action, stale data.
struct DMBanner<Trailing: View>: View {
    let message: String
    var systemImage = "exclamationmark.triangle"
    var tint: Color = .orange
    var lineLimit: Int?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(message)
                .font(.dm(12))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .help(message)
            Spacer()
            trailing()
        }
        .padding(10)
        .background(tint.opacity(0.12))
    }
}
