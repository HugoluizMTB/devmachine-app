import Foundation
import Combine
import DevmachineCore

struct FileTreeRow: Identifiable, Equatable {
    let path: String
    let name: String
    let depth: Int
    let kind: FileTreeEntry.Kind
    let isPlaceholder: Bool

    // A placeholder sits one level below the directory it stands for, so the
    // depth is what keeps its id apart from that directory's own row.
    var id: String { "\(depth)|\(path)" }

    var isDirectory: Bool { !isPlaceholder && kind == .directory }
}

@MainActor
final class FileTreeStore: ObservableObject {
    @Published var root: String?
    @Published var children: [String: [FileTreeEntry]] = [:]
    @Published var expanded: Set<String> = []
    @Published var loading: Set<String> = []
    @Published var errorText: String?
    @Published var isLoading = false
    /// The row the tree points at, so revealing a file can move it.
    @Published var selected: String?

    private static let rootKey = "\u{1}root"

    private let host: HostRunner
    private var current: CommandTarget?
    private var inFlight: Set<String> = []

    init(host: HostRunner = HostRunner()) {
        self.host = host
    }

    func start(_ target: CommandTarget) {
        if current == target { return }
        current = target
        clear()
        resolveRoot(keepingExpanded: false)
    }

    func stop() {
        current = nil
        inFlight = []
        clear()
    }

    func refresh() {
        resolveRoot(keepingExpanded: true)
    }

    /// Opens every folder from the root down to `path` and marks it, so a file
    /// opened somewhere else shows up in the tree where it lives.
    func reveal(_ path: String) {
        selected = path
        guard let root, path.hasPrefix(root) else { return }
        var directory = parentPath(of: path)
        var chain: [String] = []
        while directory.hasPrefix(root), directory != root {
            chain.append(directory)
            directory = parentPath(of: directory)
        }
        for folder in chain.reversed() where !expanded.contains(folder) {
            expanded.insert(folder)
        }
        for folder in chain where children[folder] == nil {
            list(folder)
        }
    }

    /// True while any folder is open, which is what the button in the header
    /// switches on.
    var hasExpandedFolders: Bool { !expanded.isEmpty }

    /// Closes everything, or opens every folder already read. Opening cannot
    /// reach what was never listed: a tree is read one folder at a time, and
    /// walking a whole repository would be one command per directory.
    func toggleAll() {
        if hasExpandedFolders {
            expanded = []
            return
        }
        expanded = Set(
            children.flatMap { directory, entries in
                entries.filter(\.isDirectory).map { Self.join(directory, $0.name) }
            }
        )
        for folder in expanded where children[folder] == nil { list(folder) }
    }

    func toggle(_ path: String) {
        if expanded.contains(path) {
            expanded.remove(path)
            return
        }
        expanded.insert(path)
        if children[path] == nil {
            list(path)
        }
    }

    var visibleRows: [FileTreeRow] {
        guard let root else { return [] }
        var rows: [FileTreeRow] = []
        appendRows(of: root, depth: 0, into: &rows)
        return rows
    }

    func relativePath(of path: String) -> String {
        guard let root, path != root else { return path }
        guard path.hasPrefix(root) else { return path }
        let tail = path.dropFirst(root.count)
        return tail.hasPrefix("/") ? String(tail.dropFirst()) : String(tail)
    }

    func parentPath(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/"), slash != path.startIndex else { return "/" }
        return String(path[path.startIndex..<slash])
    }

    private func appendRows(of directory: String, depth: Int, into rows: inout [FileTreeRow]) {
        guard let entries = children[directory] else { return }
        guard !entries.isEmpty else {
            rows.append(
                FileTreeRow(
                    path: directory,
                    name: "empty",
                    depth: depth,
                    kind: .other,
                    isPlaceholder: true
                )
            )
            return
        }
        for entry in entries {
            let path = Self.join(directory, entry.name)
            rows.append(
                FileTreeRow(
                    path: path,
                    name: entry.name,
                    depth: depth,
                    kind: entry.kind,
                    isPlaceholder: false
                )
            )
            if entry.isDirectory, expanded.contains(path) {
                appendRows(of: path, depth: depth + 1, into: &rows)
            }
        }
    }

    private func resolveRoot(keepingExpanded: Bool) {
        guard let target = current else { return }
        guard !inFlight.contains(Self.rootKey) else { return }
        inFlight.insert(Self.rootKey)
        setLoading(root == nil)
        let host = self.host

        Task.detached {
            let result = try? host.runCapturing(target, RemoteCommands.fileTreeRootBody)
            await MainActor.run {
                self.applyRoot(result, target: target, keepingExpanded: keepingExpanded)
            }
        }
    }

    private func applyRoot(
        _ result: (stdout: String, stderr: String, exitCode: Int32)?,
        target: CommandTarget,
        keepingExpanded: Bool
    ) {
        inFlight.remove(Self.rootKey)
        guard current == target else { return }
        setLoading(false)

        guard let path = Self.firstLine(result?.stdout) else {
            if root != nil { root = nil }
            setError(Self.failure(result))
            return
        }
        setError(nil)

        let moved = root != path
        if moved { root = path }
        if moved || !keepingExpanded {
            if !children.isEmpty { children = [:] }
            if !expanded.isEmpty { expanded = [] }
        }
        for directory in [path] + expanded.sorted() {
            list(directory)
        }
    }

    private func list(_ path: String) {
        guard let target = current else { return }
        guard !inFlight.contains(path) else { return }
        inFlight.insert(path)
        loading.insert(path)
        let host = self.host
        let command = target.listsPortably()
            ? RemoteCommands.listDirectoryPortable(path: path)
            : RemoteCommands.listDirectory(path: path)
        Task.detached {
            let result = try? host.runCapturingAnywhere(target, command)
            await MainActor.run {
                self.applyListing(result, target: target, path: path)
            }
        }
    }

    private func applyListing(
        _ result: (stdout: String, stderr: String, exitCode: Int32)?,
        target: CommandTarget,
        path: String
    ) {
        inFlight.remove(path)
        if loading.contains(path) { loading.remove(path) }
        guard current == target else { return }
        guard let root, path == root || path.hasPrefix(root + "/") else { return }

        guard let result else {
            setError("Could not read the folder")
            return
        }
        let entries = target.listsPortably()
            ? FileTreeParser.parseNames(result.stdout)
            : FileTreeParser.parse(result.stdout)
        if children[path] != entries { children[path] = entries }
        // An unreadable directory lists nothing, so its message is the only
        // sign the listing is empty for a reason.
        if entries.isEmpty, result.exitCode != 0 {
            setError(Self.failure(result))
        } else {
            setError(nil)
        }
    }

    private static func firstLine(_ output: String?) -> String? {
        output?
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    // No output and no message means the session has no path, which the view words itself.
    private static func failure(_ result: (stdout: String, stderr: String, exitCode: Int32)?) -> String? {
        guard let result else { return "Could not reach the host" }
        return firstLine(result.stderr)
    }

    private static func join(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    private func setLoading(_ value: Bool) {
        if isLoading != value { isLoading = value }
    }

    private func setError(_ value: String?) {
        if errorText != value { errorText = value }
    }

    private func clear() {
        if root != nil { root = nil }
        if !children.isEmpty { children = [:] }
        if !expanded.isEmpty { expanded = [] }
        if !loading.isEmpty { loading = [] }
        if errorText != nil { errorText = nil }
        setLoading(false)
    }
}
