import SwiftUI
import AppKit
import DevmachineCore

enum FileTreeIcon {
    private static let code: Set<String> = ["swift", "rb", "py", "js", "ts", "go", "rs", "sh"]
    private static let text: Set<String> = ["md", "txt"]
    private static let data: Set<String> = ["json", "yml", "yaml", "toml", "lock"]
    private static let images: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "tiff", "ico"]
    private static let dimmedNames: Set<String> = ["node_modules", ".build", "vendor"]

    static func name(for row: FileTreeRow, expanded: Bool) -> String {
        if row.isDirectory { return expanded ? "folder.fill" : "folder" }
        let ext = (row.name as NSString).pathExtension.lowercased()
        if code.contains(ext) { return "chevron.left.forwardslash.chevron.right" }
        if text.contains(ext) { return "doc.text" }
        if data.contains(ext) { return "curlybraces" }
        if images.contains(ext) { return "photo" }
        return "doc"
    }

    static func isDimmed(_ name: String) -> Bool {
        name.hasPrefix(".") || dimmedNames.contains(name)
    }
}

struct FilesTab: View {
    @ObservedObject var store: FileTreeStore
    let target: CommandTarget
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var filesStore: FilesStore
    @EnvironmentObject var viewerStore: FileViewerStore
    @EnvironmentObject var search: FileSearchStore
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let root = store.root {
                header(root)
                searchField
                if let error = store.errorText {
                    message(error)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                }
                if query.isEmpty {
                    tree
                } else {
                    results
                }
            } else {
                stateMessage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            store.start(target)
            search.open(target)
        }
        .onDisappear { store.stop() }
        .onChange(of: target.key) { _, _ in
            store.start(target)
            search.open(target)
        }
        .onChange(of: query) { _, value in search.query = value }
        .onChange(of: model.revealInTree) { _, path in
            guard let path else { return }
            store.reveal(path)
            model.revealInTree = nil
        }
    }

    private func header(_ root: String) -> some View {
        DMSection(
            headerSpacing: 6,
            padding: EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14),
            label: {
                Text(Self.shortPath(root))
                    .font(.dm(11, design: .monospaced))
                    .foregroundStyle(Color.dmMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(root)
            },
            trailing: {
                DMIconButton(systemImage: "arrow.clockwise", size: 11, hitSize: DMHitSize.compact) {
                    store.refresh()
                }
                .help("Refresh")
            }
        )
    }

    /// The same engine as ⌘P, in the panel: a field that finds a file anywhere
    /// in the repository, without opening the tree folder by folder.
    private var searchField: some View {
        DMSearchField(
            prompt: "Find a file", text: $query, fontSize: 11.5, iconSize: 10, spacing: 6,
            textColor: .dmRowText
        ) {
            if !query.isEmpty {
                DMIconButton(systemImage: "xmark.circle.fill", size: 10) { query = "" }
            }
            DMIconButton(
                systemImage: store.hasExpandedFolders
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                size: 10, hitSize: DMHitSize.compact
            ) { store.toggleAll() }
            .help(store.hasExpandedFolders ? "Collapse every folder" : "Expand the folders read so far")
        }
        .onSubmit { openFirstHit() }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.dmHover, in: RoundedRectangle(cornerRadius: DMRadius.control, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    /// What the field found. Opening a hit also points the tree at it, so the
    /// file's place in the repository is not lost.
    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if search.hits.isEmpty {
                    message(search.isLoading ? "Listing files…" : "No file matches")
                        .padding(.top, 12)
                } else {
                    ForEach(search.hits, id: \.id) { hit in
                        Button { open(hit.path) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text((hit.path as NSString).lastPathComponent)
                                    .font(.dm(12))
                                    .foregroundStyle(Color.dmRowText)
                                    .lineLimit(1)
                                Text(hit.path)
                                    .font(.dm(10))
                                    .foregroundStyle(Color.dmMuted)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func openFirstHit() {
        guard let hit = search.hits.first else { return }
        open(hit.path)
    }

    private func open(_ path: String) {
        let full = path.hasPrefix("/") || search.root.isEmpty
            ? path : search.root + "/" + path
        viewerStore.open(target, path: full)
        store.reveal(full)
    }

    private var tree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(store.visibleRows) { row in
                    if row.isPlaceholder {
                        placeholder(row)
                    } else {
                        FileTreeRowView(
                            row: row,
                            expanded: store.expanded.contains(row.path),
                            loading: store.loading.contains(row.path),
                            selected: store.selected == row.path,
                            tap: { tapped(row) },
                            copyPath: { copy(row.path, label: "Copied path") },
                            copyRelativePath: {
                                copy(store.relativePath(of: row.path), label: "Copied path")
                            },
                            openInFilesWindow: row.isDirectory ? nil : { openInFilesWindow(row) },
                            openInViewer: row.isDirectory ? nil : { openInViewer(row) }
                        )
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func placeholder(_ row: FileTreeRow) -> some View {
        Text("empty")
            .font(.dm(12))
            .foregroundStyle(Color.dmMuted)
            .padding(.leading, Self.indent(row.depth) + 21)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
    }

    @ViewBuilder
    private var stateMessage: some View {
        VStack(spacing: 0) {
            Spacer()
            if store.isLoading {
                ProgressView().controlSize(.small)
            } else {
                message(store.errorText ?? "No path")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.dm(12))
            .foregroundStyle(Color.dmMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func tapped(_ row: FileTreeRow) {
        if row.isDirectory {
            store.toggle(row.path)
        } else {
            store.selected = row.path
        }
    }

    /// The Files window reads a host over ssh, so it has nothing to open for a
    /// session that runs on this Mac — Finder does that job here.
    /// Reading a file is a window of its own, beside the session it came from.
    private func openInViewer(_ row: FileTreeRow) {
        store.selected = row.path
        viewerStore.open(target, path: row.path)
    }

    private func openInFilesWindow(_ row: FileTreeRow) {
        filesStore.open(target, path: store.parentPath(of: row.path))
        openWindow(id: "files")
    }

    private func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.flashToast(label)
    }

    static let rowHeight: CGFloat = 22

    static func indent(_ depth: Int) -> CGFloat {
        CGFloat(depth) * 14
    }

    static func shortPath(_ path: String) -> String {
        let parts = path.split(separator: "/").suffix(2)
        return parts.isEmpty ? path : parts.joined(separator: "/")
    }
}

private struct FileTreeRowView: View {
    let row: FileTreeRow
    let expanded: Bool
    let loading: Bool
    let selected: Bool
    let tap: () -> Void
    let copyPath: () -> Void
    let copyRelativePath: () -> Void
    let openInFilesWindow: (() -> Void)?
    let openInViewer: (() -> Void)?
    @State private var hovering = false

    private static let accent = Color(hex: 0x5AA9E6)

    var body: some View {
        HStack(spacing: 5) {
            chevron
            Image(systemName: FileTreeIcon.name(for: row, expanded: expanded))
                .font(.dm(10))
                .foregroundStyle(iconColor)
                .frame(width: 12, alignment: .center)
            Text(row.name)
                .font(.dm(12))
                .foregroundStyle(dimmed ? Color.dmMuted : Color.dmRowText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if loading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.leading, FilesTab.indent(row.depth) + 8)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, minHeight: FilesTab.rowHeight, alignment: .leading)
        .background(background)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { (openInViewer ?? tap)() }
        .onTapGesture { tap() }
        .contextMenu {
            if let openInViewer {
                Button("Open") { openInViewer() }
                Divider()
            }
            Button("Copy path") { copyPath() }
            Button("Copy relative path") { copyRelativePath() }
            if let openInFilesWindow {
                Button("Open in Files window") { openInFilesWindow() }
            }
        }
        .help(row.path)
    }

    @ViewBuilder
    private var chevron: some View {
        if row.isDirectory {
            Image(systemName: "chevron.right")
                .font(.dm(10, weight: .semibold))
                .foregroundStyle(Color.dmMuted)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 10, alignment: .center)
        } else {
            Color.clear.frame(width: 10, height: 10)
        }
    }

    private var background: some View {
        DMRowBackground(
            selected: selected, hovering: hovering, selectedColor: Self.accent.opacity(0.22))
    }

    private var dimmed: Bool {
        FileTreeIcon.isDimmed(row.name)
    }

    private var iconColor: Color {
        if dimmed { return Color.dmMuted }
        return row.isDirectory ? Self.accent : Color.dmMuted
    }
}
