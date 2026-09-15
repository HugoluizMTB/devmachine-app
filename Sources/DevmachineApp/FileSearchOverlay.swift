import SwiftUI
import AppKit
import DevmachineCore

/// Search over every file of the session's repository. Enter copies the path,
/// Command+Enter types it into the session's prompt without sending it, which
/// is how a path reaches an agent waiting for one.
struct FileSearchOverlay: View {
    @ObservedObject var store: FileSearchStore
    let root: String
    let onCopy: (String) -> Void
    let onType: (String) -> Void
    let onClose: () -> Void

    @State private var selection = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            if let error = store.errorText {
                message(error)
            } else if store.isLoading && store.hits.isEmpty {
                message("Listing files…")
            } else if store.hits.isEmpty && !store.query.isEmpty {
                message("No file matches")
            } else {
                results
            }
        }
        .background(Color.dmSidebarBg)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.dmDivider), alignment: .bottom)
        .onAppear { focused = true }
        .onChange(of: store.query) { _, _ in selection = 0 }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.dm(11))
                .foregroundStyle(Color.dmMuted)
            TextField("Find a file", text: $store.query)
                .textFieldStyle(.plain)
                .font(.dm(12))
                .focused($focused)
                .onSubmit { copySelected() }
            Text(verbatim: "\(store.fileCount)")
                .font(.dm(10))
                .foregroundStyle(Color.dmMuted)
                .help("Files in this repository")
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.dm(10))
                    .foregroundStyle(Color.dmMuted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.hits.enumerated()), id: \.element.id) { index, hit in
                        row(hit, index: index)
                            .id(index)
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 220)
            .onChange(of: selection) { _, value in
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(value) }
            }
        }
    }

    private func row(_ hit: FileSearch.Hit, index: Int) -> some View {
        let name = (hit.path as NSString).lastPathComponent
        let folder = (hit.path as NSString).deletingLastPathComponent
        return HStack(spacing: 6) {
            Text(name)
                .font(.dm(12))
                .foregroundStyle(.white.opacity(0.9))
            Text(folder)
                .font(.dm(10))
                .foregroundStyle(Color.dmMuted)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(index == selection ? Color.white.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { selection = index; copySelected() }
        .contextMenu {
            Button("Copy path") { onCopy(absolute(hit.path)) }
            Button("Type in session") { onType(hit.path) }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.dm(11))
            .foregroundStyle(Color.dmMuted)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
    }

    private func copySelected() {
        guard store.hits.indices.contains(selection) else { return }
        onCopy(absolute(store.hits[selection].path))
    }

    /// The listing is relative to the repository root; what leaves the app is a
    /// path that means something on its own.
    private func absolute(_ path: String) -> String {
        path.hasPrefix("/") ? path : root + "/" + path
    }
}
