import Foundation

public struct FileEntry: Equatable, Sendable {
    public let name: String
    public let isDir: Bool

    public init(name: String, isDir: Bool) {
        self.name = name
        self.isDir = isDir
    }
}

public enum FileListParser {
    public static func parse(_ output: String) -> [FileEntry] {
        let entries: [FileEntry] = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }
            .filter { $0 != "./" && $0 != "../" }
            .map { line in
                if line.hasSuffix("/") {
                    return FileEntry(name: String(line.dropLast()), isDir: true)
                }
                return FileEntry(name: line, isDir: false)
            }

        return entries.sorted { lhs, rhs in
            if lhs.isDir != rhs.isDir {
                return lhs.isDir && !rhs.isDir
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
