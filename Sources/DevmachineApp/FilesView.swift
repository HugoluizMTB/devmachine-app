import SwiftUI
import DevmachineCore

struct FilesView: View {
    @EnvironmentObject var store: FilesStore
    @EnvironmentObject var viewerStore: FileViewerStore
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            pathBar
            DMHairline()
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dmContentBg)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(store.target.map { "\($0.label) — \(store.path)" } ?? "Files")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(1)

            Spacer()

            if store.isLoading {
                ProgressView().controlSize(.small)
            }

            DMIconButton(systemImage: "arrow.up.doc", tint: nil) { store.uploadFiles() }
            .help("Upload…")
        }
        .padding(10)
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            DMIconButton(systemImage: "arrow.up", tint: nil) { store.up() }
            .disabled(!store.canGoUp)
            .help("Up")

            Text(store.path)
                .font(.dm(11, design: .monospaced))
                .foregroundStyle(Color.dmMuted)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer()

            DMIconButton(systemImage: "arrow.clockwise", tint: nil) { store.refresh() }
                .help("Refresh")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        if let err = store.errorText {
            DMStatusView(
                kind: .failed(
                    title: "Couldn't list this folder", message: err, retry: { store.refresh() }),
                fillsHeight: false)
        } else if store.entries.isEmpty {
            DMStatusView(
                kind: .empty(systemImage: "folder", text: store.isLoading ? "Loading…" : "Empty"),
                fillsHeight: false)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(store.entries, id: \.name) { entry in
                        row(for: entry)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func open(_ entry: FileEntry) {
        guard let target = store.target else { return }
        let path = store.absolutePath(of: entry)
        viewerStore.open(target, path: path)
        model.openedFile(at: path)
        // The pane lives in the main window, so that is the one to raise.
        openWindow(id: "main")
    }

    private func row(for entry: FileEntry) -> some View {
        DMRow(
            systemImage: entry.isDir ? "folder" : "doc",
            iconColor: entry.isDir ? .blue : .dmMuted,
            title: entry.name,
            trailing: entry.isDir ? nil : AnyView(
                DMIconButton(systemImage: "arrow.down.circle", tint: nil) {
                    store.download(entry)
                }
                .help("Download")
            ),
            tap: entry.isDir ? { store.cd(entry) } : { open(entry) }
        )
        .contextMenu {
            if !entry.isDir {
                Button("Open") { open(entry) }
                Divider()
                Button(store.target?.isLocal == true ? "Reveal in Finder" : "Download") {
                    store.download(entry)
                }
            }
        }
    }
}
