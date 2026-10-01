import SwiftUI

/// Shows the last file transfer's result beside the task toasts.
struct TransferNoticeOverlay: View {
    @ObservedObject var transfers: FileTransferStore = .shared

    var body: some View {
        if let notice = transfers.notice {
            TransferNoticeCard(
                notice: notice,
                reveal: notice.reveal.map { url in { transfers.reveal(url) } },
                close: { transfers.dismiss() }
            )
            .id(notice.id)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

struct TransferNoticeCard: View {
    let notice: TransferNotice
    let reveal: (() -> Void)?
    let close: () -> Void

    @Environment(\.dmMetrics) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: m.space.sm) {
                Image(systemName: notice.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.dm(12))
                    .foregroundStyle(notice.failed ? Color.orange : Color.green)
                Text(notice.title)
                    .font(.dm(12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: m.space.xs)
                DMIconButton(systemImage: "xmark", size: 9, hitSize: DMHitSize.compact, action: close)
                    .help("Close")
            }
            if let detail = notice.detail {
                Text(detail)
                    .font(.dm(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reveal {
                Button("Reveal in Finder", action: reveal)
                    .buttonStyle(.dm(.outline, size: .small))
            }
        }
        .frame(width: m.card.toast, alignment: .leading)
        .padding(m.space.lg)
        .dmGlass(radius: DMRadius.toast)
        .shadow(radius: m.pt(10), y: m.pt(3))
    }
}
