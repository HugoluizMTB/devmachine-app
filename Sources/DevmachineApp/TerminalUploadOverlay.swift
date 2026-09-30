import SwiftUI
import DevmachineCore

extension View {
    /// Drop highlight, progress, the large-file question and errors for files
    /// sent to this pane. Everything sits over the terminal, so the session is
    /// never resized by it.
    func terminalUploads(for kind: TerminalKind) -> some View {
        modifier(TerminalUploadOverlay(kind: kind))
    }
}

private struct TerminalUploadOverlay: ViewModifier {
    @ObservedObject private var uploads = PaneUploadStore.shared
    let kind: TerminalKind

    func body(content: Content) -> some View {
        content
            .overlay {
                if uploads.dropTarget == kind {
                    dropHighlight
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if case let .uploading(label, done, total)? = uploads.phases[kind] {
                    UploadProgressCard(label: label, done: done, total: total)
                        .padding(14)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .overlay {
                switch uploads.phases[kind] {
                case let .confirming(names, totalBytes)?:
                    LargeUploadQuestion(
                        destination: destination, names: names, totalBytes: totalBytes,
                        cancel: { uploads.dismiss(kind) }, upload: { uploads.confirm(kind) })
                case let .failed(state)?:
                    UploadErrorCard(state: state) { uploads.dismiss(kind) }
                default:
                    EmptyView()
                }
            }
            .animation(.easeOut(duration: 0.12), value: uploads.dropTarget == kind)
    }

    private var destination: String {
        switch kind {
        case let .remote(alias, _): return alias
        case .local: return "this Mac"
        }
    }

    private var dropHighlight: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DMRadius.terminal, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
            Label {
                Text(verbatim: "Drop to upload to \(destination)")
            } icon: {
                Image(systemName: "arrow.down.doc")
            }
            .font(.dm(12.5, weight: .medium))
            .foregroundStyle(Color.dmRowText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .dmGlass(radius: DMRadius.pill)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TerminalRegistry.dropHint(for: kind)))
    }
}

private struct UploadProgressCard: View {
    let label: String
    let done: Int64
    let total: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(verbatim: label)
                    .font(.dm(12, weight: .semibold))
                    .foregroundStyle(Color.dmRowText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text(verbatim: "\(FileUpload.byteText(done)) of \(FileUpload.byteText(total))")
                    .font(.dm(11).monospacedDigit())
                    .foregroundStyle(Color.dmMuted)
            }
            DMProgressBar(
                done: Int(clamping: done), total: Int(clamping: max(total, 1)),
                fillColor: .accentColor)
        }
        .frame(width: 300)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .dmGlass(radius: DMRadius.toast)
        .accessibilityElement(children: .combine)
    }
}

private struct LargeUploadQuestion: View {
    let destination: String
    let names: [String]
    let totalBytes: Int64
    let cancel: () -> Void
    let upload: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 5) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.dm(20, weight: .light))
                    .foregroundStyle(Color.dmMuted)
                    .accessibilityHidden(true)
                Text(verbatim: "Upload \(FileUpload.byteText(totalBytes)) to \(destination)?")
                    .font(.dm(13, weight: .semibold))
                    .foregroundStyle(Color.dmRowText)
                Text(verbatim: names.count == 1 ? names[0] : "\(names.count) files")
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            HStack(spacing: 6) {
                DMButton("Cancel", variant: .outline, size: .small, action: cancel)
                DMButton("Upload", size: .small, action: upload)
            }
        }
        .frame(maxWidth: 360)
        .padding(18)
        .dmGlass(radius: DMRadius.panel)
    }
}

private struct UploadErrorCard: View {
    let state: DMErrorState
    let dismiss: () -> Void

    var body: some View {
        DMErrorStateView(state: state)
            .padding(18)
            .padding(.top, 4)
            .dmGlass(radius: DMRadius.panel)
            .overlay(alignment: .topTrailing) {
                DMButton(icon: "xmark", label: "Dismiss", size: .small, action: dismiss)
                    .padding(6)
            }
            .frame(maxWidth: 440)
            .padding(16)
    }
}
