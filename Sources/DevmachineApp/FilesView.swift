import SwiftUI
import DevmachineCore

struct FilesView: View {
    @EnvironmentObject var store: FilesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.dmDivider).frame(height: 1)
            pathBar
            Rectangle().fill(Color.dmDivider).frame(height: 1)
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dmContentBg)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(store.alias.map { "\($0) — \(store.path)" } ?? "Files")
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(1)

            Spacer()

            if store.isLoading {
                ProgressView().controlSize(.small)
            }

            Button {
                store.uploadFiles()
            } label: {
                Image(systemName: "arrow.up.doc")
            }
            .buttonStyle(.plain)
            .help("Upload…")
        }
        .padding(10)
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Button {
                store.up()
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.plain)
            .disabled(!store.canGoUp)
            .help("Up")

            Text(store.path)
                .font(.dm(11, design: .monospaced))
                .foregroundStyle(Color.dmMuted)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer()

            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        if let err = store.errorText {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text(err)
                    .font(.dm(12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry") { store.refresh() }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        } else if store.entries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(store.isLoading ? "Loading…" : "Empty")
                    .font(.dm(12))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
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

    private func row(for entry: FileEntry) -> some View {
        DMRow(
            systemImage: entry.isDir ? "folder" : "doc",
            iconColor: entry.isDir ? .blue : .dmMuted,
            title: entry.name,
            trailing: entry.isDir ? nil : AnyView(
                Button {
                    store.download(entry)
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.plain)
                .help("Download")
            ),
            tap: entry.isDir ? { store.cd(entry) } : nil
        )
        .contextMenu {
            if !entry.isDir {
                Button("Download") { store.download(entry) }
            }
        }
    }
}
