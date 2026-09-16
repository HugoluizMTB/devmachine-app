import SwiftUI
import AppKit
import HighlightSwift
import MarkdownUI
import DevmachineCore

/// Reads a file. It never writes one: there is no editing here on purpose, so
/// a file opened from a running session cannot be changed by accident.
struct FileViewerView: View {
    @EnvironmentObject var store: FileViewerStore
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color.dmSidebarBg)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.dm(12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x5AA9E6))
            VStack(alignment: .leading, spacing: 1) {
                Text(store.preview?.name ?? (store.path as NSString?)?.lastPathComponent ?? "Viewer")
                    .font(.dm(13, weight: .semibold))
                    .foregroundStyle(.white)
                if let path = store.path {
                    Text(path)
                        .font(.dm(10))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer()
            if store.preview?.kind == .markdown {
                Toggle(isOn: $store.showsSource) {
                    Text(verbatim: "Source").font(.dm(11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .foregroundStyle(.white.opacity(0.7))
            }
            if let preview = store.preview {
                Text(Self.size(preview.byteCount))
                    .font(.dm(10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Button { store.reload() } label: {
                Image(systemName: "arrow.clockwise").font(.dm(11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
            .help("Read the file again")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.errorText {
            message(error)
        } else if let preview = store.preview {
            body(of: preview)
        } else if store.isLoading {
            message("Reading…")
        } else {
            message("No file")
        }
    }

    @ViewBuilder
    private func body(of preview: FilePreview) -> some View {
        switch preview.kind {
        case let .code(language):
            scroll { code(preview.text ?? "", language: language) }
        case .markdown:
            if store.showsSource {
                scroll { code(preview.text ?? "", language: "markdown") }
            } else {
                ScrollView {
                    Markdown(preview.text ?? "")
                        .markdownTheme(.gitHub)
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .text:
            scroll {
                Text(preview.text ?? "")
                    .font(.dm(12, design: .monospaced))
                    .foregroundStyle(Color.dmRowText)
                    .textSelection(.enabled)
            }
        case .image:
            imageBody(preview)
        case .binary:
            message("Binary file — nothing to show")
        case let .tooLarge(bytes):
            message("Too large to open here (\(Self.size(bytes)))")
        }
    }

    @ViewBuilder
    private func imageBody(_ preview: FilePreview) -> some View {
        if let data = preview.data, let image = NSImage(data: data) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(16)
            }
        } else {
            message("This image could not be read")
        }
    }

    private func code(_ text: String, language: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CodeText(text)
                .highlightLanguage(language.flatMap(HighlightLanguage.init(rawValue:)) ?? .plaintext)
                .codeTextColors(.theme(.atomOne))
                .font(.dm(12, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func scroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView([.horizontal, .vertical]) {
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func message(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.dm(12))
                .foregroundStyle(Color.dmMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var icon: String {
        switch store.preview?.kind {
        case .markdown: return "doc.richtext"
        case .image: return "photo"
        case .binary: return "shippingbox"
        case .tooLarge: return "exclamationmark.triangle"
        default: return "doc.text"
        }
    }

    static func size(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
