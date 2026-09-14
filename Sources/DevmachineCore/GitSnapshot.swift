import Foundation

public struct GitSnapshot: Equatable, Sendable {
    public struct Worktree: Equatable, Sendable {
        public let path: String
        public let head: String
        public let branch: String?
        public let isMain: Bool

        public init(path: String, head: String, branch: String?, isMain: Bool) {
            self.path = path
            self.head = head
            self.branch = branch
            self.isMain = isMain
        }
    }

    public struct Commit: Equatable, Sendable {
        public let sha: String
        public let subject: String
        public let author: String
        public let age: String
        public let refs: [String]

        public init(sha: String, subject: String, author: String, age: String, refs: [String]) {
            self.sha = sha
            self.subject = subject
            self.author = author
            self.age = age
            self.refs = refs
        }
    }

    public let root: String
    public let branch: String?
    public let upstream: String?
    public let ahead: Int
    public let behind: Int
    public let dirtyFiles: Int
    public let detachedHead: String?
    public let worktrees: [Worktree]
    public let commits: [Commit]

    public init(
        root: String,
        branch: String? = nil,
        upstream: String? = nil,
        ahead: Int = 0,
        behind: Int = 0,
        dirtyFiles: Int = 0,
        detachedHead: String? = nil,
        worktrees: [Worktree] = [],
        commits: [Commit] = []
    ) {
        self.root = root
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.dirtyFiles = dirtyFiles
        self.detachedHead = detachedHead
        self.worktrees = worktrees
        self.commits = commits
    }

    public var isDirty: Bool { dirtyFiles > 0 }
}

public enum GitSnapshotParser {
    private static let recordSeparator: Character = "\u{1e}"
    private static let fieldSeparator: Character = "\u{1f}"

    public static func parse(_ output: String) -> GitSnapshot? {
        let sections = output
            .split(separator: recordSeparator, omittingEmptySubsequences: false)
            .map(String.init)
        guard let statusSection = sections.first else { return nil }

        let statusLines = lines(statusSection)
        guard let rootIndex = statusLines.firstIndex(where: { $0.hasPrefix("/") }) else { return nil }
        let root = statusLines[rootIndex]
        let status = parseStatus(Array(statusLines[(rootIndex + 1)...]))

        return GitSnapshot(
            root: root,
            branch: status.branch,
            upstream: status.upstream,
            ahead: status.ahead,
            behind: status.behind,
            dirtyFiles: status.dirtyFiles,
            detachedHead: status.detachedHead,
            worktrees: parseWorktrees(sections.count > 1 ? sections[1] : ""),
            commits: parseCommits(sections.count > 2 ? sections[2] : "")
        )
    }

    private struct Status {
        var branch: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var dirtyFiles = 0
        var detachedHead: String?
    }

    private static func parseStatus(_ statusLines: [String]) -> Status {
        var status = Status()
        var oid: String?
        var detached = false

        for line in statusLines {
            guard line.hasPrefix("#") else {
                status.dirtyFiles += 1
                continue
            }
            let header = line.dropFirst().trimmingCharacters(in: .whitespaces)
            if let value = value(of: "branch.oid", in: header) {
                oid = value
            } else if let value = value(of: "branch.head", in: header) {
                if value == "(detached)" {
                    detached = true
                } else {
                    status.branch = value
                }
            } else if let value = value(of: "branch.upstream", in: header) {
                status.upstream = value
            } else if let value = value(of: "branch.ab", in: header) {
                for token in value.split(separator: " ") {
                    let number = Int(token.dropFirst()) ?? 0
                    if token.hasPrefix("+") { status.ahead = number }
                    if token.hasPrefix("-") { status.behind = number }
                }
            }
        }

        if detached, let oid, oid != "(initial)" {
            status.detachedHead = oid
        }
        return status
    }

    private static func parseWorktrees(_ section: String) -> [GitSnapshot.Worktree] {
        var worktrees: [GitSnapshot.Worktree] = []
        var path: String?
        var head = ""
        var branch: String?

        func flush() {
            guard let path else { return }
            worktrees.append(
                GitSnapshot.Worktree(path: path, head: head, branch: branch, isMain: worktrees.isEmpty)
            )
        }

        for line in lines(section) {
            if let value = value(of: "worktree", in: line) {
                flush()
                path = value
                head = ""
                branch = nil
            } else if let value = value(of: "HEAD", in: line) {
                head = value
            } else if let value = value(of: "branch", in: line) {
                branch = value.hasPrefix("refs/heads/")
                    ? String(value.dropFirst("refs/heads/".count))
                    : value
            }
        }
        flush()
        return worktrees
    }

    private static func parseCommits(_ section: String) -> [GitSnapshot.Commit] {
        lines(section).compactMap { line in
            let fields = line
                .split(separator: fieldSeparator, omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count >= 4, !fields[0].isEmpty else { return nil }
            return GitSnapshot.Commit(
                sha: fields[0],
                subject: fields[1],
                author: fields[2],
                age: fields[3],
                refs: fields.count > 4 ? parseRefs(fields[4]) : []
            )
        }
    }

    private static func parseRefs(_ field: String) -> [String] {
        field
            .components(separatedBy: ", ")
            .map { ref -> String in
                let trimmed = ref.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("HEAD -> ")
                    ? String(trimmed.dropFirst("HEAD -> ".count))
                    : trimmed
            }
            .filter { !$0.isEmpty }
    }

    private static func value(of key: String, in line: String) -> String? {
        guard line.hasPrefix(key + " ") else { return nil }
        return String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
    }

    private static func lines(_ text: String) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
