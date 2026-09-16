import SwiftUI
import AppKit
import DevmachineCore

/// Find a file of the session's repository from anywhere, the way an editor
/// does. What "opening" means here is putting the path where the session is
/// waiting for input.
struct FileSearchPaletteView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var store: FileSearchStore
    let target: CommandTarget

    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            field
            Divider()
            content
            footer
        }
        .frame(width: 620)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(radius: 30, y: 12)
        .onAppear {
            focused = true
            index = 0
            store.open(target)
        }
        .onChange(of: store.query) { _, _ in index = 0 }
        .onKeyPress(.downArrow) {
            index = min(index + 1, max(store.hits.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
        .onKeyPress(.return) { typeSelected(); return .handled }
        .onKeyPress(.escape) { model.showFileSearch = false; return .handled }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find a file in this session…", text: $store.query)
                .textFieldStyle(.plain)
                .font(.dm(15))
                .focused($focused)
                .onSubmit(typeSelected)
            if store.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.errorText {
            note(error)
        } else if store.hits.isEmpty {
            note(store.isLoading ? "Listing files…" : "No file matches")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(store.hits.enumerated()), id: \.element.id) { i, hit in
                            row(i: i, hit: hit).id(hit.id)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
                .onChange(of: index) { _, new in
                    guard new < store.hits.count else { return }
                    withAnimation { proxy.scrollTo(store.hits[new].id) }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(verbatim: "Type in session  ⏎")
                .font(.dm(10))
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: "\(store.fileCount) files")
                .font(.dm(10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.08)), alignment: .top)
    }

    private func row(i: Int, hit: FileSearch.Hit) -> some View {
        let parts = FileSearchRow.split(path: hit.path, matches: hit.matches)
        return HStack(spacing: 8) {
            highlighted(parts.name, weight: .medium, base: .primary)
            highlighted(parts.folder, weight: .regular, base: .secondary)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(i == index ? Color.white.opacity(0.10) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { index = i; typeSelected() }
        .contextMenu {
            Button("Copy path") { copy(hit.path) }
        }
    }

    /// The matched letters are drawn in the accent color, the rest plain, so a
    /// long path still shows why it is in the list.
    private func highlighted(
        _ runs: [FileSearchRow.Run], weight: Font.Weight, base: HierarchicalShapeStyle
    ) -> some View {
        runs.reduce(Text(verbatim: "")) { text, run in
            text + Text(verbatim: run.text)
                .foregroundStyle(run.matched ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(base))
        }
        .font(.dm(weight == .medium ? 13 : 11, weight: weight))
        .lineLimit(1)
        .truncationMode(.head)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.dm(12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }

    private func typeSelected() {
        guard store.hits.indices.contains(index) else { return }
        let path = store.hits[index].path
        model.showFileSearch = false
        model.typeInSession(target, text: path)
    }

    private func copy(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(absolute(path), forType: .string)
        model.flashToast("Copied path")
        model.showFileSearch = false
    }

    private func absolute(_ path: String) -> String {
        path.hasPrefix("/") || store.root.isEmpty ? path : store.root + "/" + path
    }
}

/// Splits a path into the file's own name and the folder above it, each cut
/// into matched and unmatched runs.
enum FileSearchRow {
    struct Run: Equatable {
        let text: String
        let matched: Bool
    }

    static func split(path: String, matches: [Int]) -> (name: [Run], folder: [Run]) {
        let characters = Array(path)
        let slash = characters.lastIndex(of: "/")
        let nameStart = slash.map { $0 + 1 } ?? 0
        let matched = Set(matches)

        func runs(_ range: Range<Int>) -> [Run] {
            var result: [Run] = []
            for index in range {
                let isMatch = matched.contains(index)
                if var last = result.last, last.matched == isMatch {
                    last = Run(text: last.text + String(characters[index]), matched: isMatch)
                    result[result.count - 1] = last
                } else {
                    result.append(Run(text: String(characters[index]), matched: isMatch))
                }
            }
            return result
        }

        return (runs(nameStart..<characters.count), runs(0..<nameStart))
    }
}
