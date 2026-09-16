import Foundation

public struct FileTreeEntry: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case directory
        case file
        case symlink
        case other
    }

    public let name: String
    public let kind: Kind

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }

    public var isDirectory: Bool { kind == .directory }
}

public enum FileTreeParser {
    public static let hiddenNames: Set<String> = [".git"]

    public static func parse(_ output: String) -> [FileTreeEntry] {
        let entries = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap(entry)
            .filter { !hiddenNames.contains($0.name) }

        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// `ls -Ap1` output: one name per line, a trailing slash on a directory.
    /// A local listing arrives in this shape, because macOS `find` has no
    /// `-printf`; a symlink reads as a file, which is what the tree shows for
    /// anything it cannot open as a folder.
    public static func parseNames(_ output: String) -> [FileTreeEntry] {
        let entries = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "./" && $0 != "../" }
            .map { line -> FileTreeEntry in
                line.hasSuffix("/")
                    ? FileTreeEntry(name: String(line.dropLast()), kind: .directory)
                    : FileTreeEntry(name: line, kind: .file)
            }
            .filter { !hiddenNames.contains($0.name) }

        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // A file name may hold a tab, so only the first one separates find's `%y`
    // from `%f` — everything after it is the name.
    private static func entry(_ line: Substring) -> FileTreeEntry? {
        guard let tab = line.firstIndex(of: "\t") else { return nil }
        let type = line[line.startIndex..<tab]
        let name = String(line[line.index(after: tab)...])
        guard type.count == 1, !name.isEmpty else { return nil }
        return FileTreeEntry(name: name, kind: kind(type.first!))
    }

    private static func kind(_ type: Character) -> FileTreeEntry.Kind {
        switch type {
        case "d": return .directory
        case "f": return .file
        case "l": return .symlink
        default: return .other
        }
    }
}
