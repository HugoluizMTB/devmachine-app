import Foundation

/// Files inside a worktree that the session's account does not own — what a
/// root container or a `sudo` build leaves behind, and what makes git fail
/// halfway through a remove.
public struct ForeignFiles: Equatable, Sendable {
    /// The account the check ran as.
    public let user: String
    /// The first few, never more than `WorktreeRemoval.foreignFilesShown`.
    public let paths: [String]
    public let count: Int

    public init(user: String, paths: [String], count: Int) {
        self.user = user
        self.paths = paths
        self.count = count
    }
}

/// A worktree folder after git gave up on it: still on disk or not, still
/// known to git or not.
public struct WorktreeLeftover: Equatable, Sendable {
    public let path: String
    public let exists: Bool
    public let isRegistered: Bool
    public let foreignFiles: ForeignFiles?

    public init(path: String, exists: Bool, isRegistered: Bool, foreignFiles: ForeignFiles?) {
        self.path = path
        self.exists = exists
        self.isRegistered = isRegistered
        self.foreignFiles = foreignFiles
    }
}

/// What a read-only look inside one worktree found, before anything is removed.
public struct WorktreeCheck: Equatable, Sendable {
    public let path: String
    public let branch: String?
    public let upstream: String?
    public let uncommittedChanges: Int
    /// Commits on HEAD that its upstream does not have; nil without an upstream.
    public let unpushedCommits: Int?
    /// Commits on HEAD that the main branch does not have; nil when unknown.
    public let unmergedCommits: Int?
    public let mainBranch: String?
    public let isLocked: Bool
    public let lockReason: String?
    /// nil when the check did not look (the merged sweep never does).
    public let foreignFiles: ForeignFiles?

    public init(
        path: String, branch: String?, upstream: String?, uncommittedChanges: Int,
        unpushedCommits: Int?, unmergedCommits: Int?, mainBranch: String?,
        isLocked: Bool, lockReason: String?, foreignFiles: ForeignFiles? = nil
    ) {
        self.path = path
        self.branch = branch
        self.upstream = upstream
        self.uncommittedChanges = uncommittedChanges
        self.unpushedCommits = unpushedCommits
        self.unmergedCommits = unmergedCommits
        self.mainBranch = mainBranch
        self.isLocked = isLocked
        self.lockReason = lockReason
        self.foreignFiles = foreignFiles
    }

    public var hasForeignFiles: Bool { (foreignFiles?.count ?? 0) > 0 }
    public var isDirty: Bool { uncommittedChanges > 0 }
    public var isMergedIntoMain: Bool { unmergedCommits == 0 }
    public var isCleanAndMerged: Bool { !isDirty && isMergedIntoMain && !isLocked }
}

/// Removing a worktree: who may be removed, what the person must confirm, and
/// the exact git commands. Every path and branch goes through
/// `shellSingleQuoted`, so no character of it reaches a shell as syntax.
public enum WorktreeRemoval {
    public enum Block: Equatable, Sendable {
        case mainWorktree, currentWorktree

        public var reason: String {
            switch self {
            case .mainWorktree: return "The repository's main checkout can't be removed"
            case .currentWorktree: return "This session is in this worktree"
            }
        }
    }

    public struct Options: Equatable, Sendable {
        public var discardChanges: Bool
        public var removeLocked: Bool
        public var deleteBranch: Bool
        /// The second, explicit checkbox before the machine's admin deletes
        /// what the user cannot.
        public var removeAsAdmin: Bool

        public init(
            discardChanges: Bool = false, removeLocked: Bool = false, deleteBranch: Bool = false,
            removeAsAdmin: Bool = false
        ) {
            self.discardChanges = discardChanges
            self.removeLocked = removeLocked
            self.deleteBranch = deleteBranch
            self.removeAsAdmin = removeAsAdmin
        }
    }

    public enum Force: Equatable, Sendable {
        case none, force, forceTwice

        var flags: String {
            switch self {
            case .none: return ""
            case .force: return " --force"
            case .forceTwice: return " --force --force"
            }
        }
    }

    public static func block(_ worktree: GitSnapshot.Worktree, currentRoot: String) -> Block? {
        if worktree.isMain { return .mainWorktree }
        if worktree.path == currentRoot { return .currentWorktree }
        return nil
    }

    public static func canRemove(_ check: WorktreeCheck, options: Options) -> Bool {
        (!check.isDirty || options.discardChanges) && (!check.isLocked || options.removeLocked)
    }

    public static func canDeleteBranch(_ check: WorktreeCheck) -> Bool {
        guard let branch = check.branch else { return false }
        return check.isMergedIntoMain && branch != check.mainBranch
    }

    public static func force(for check: WorktreeCheck, options: Options) -> Force {
        if check.isLocked && options.removeLocked { return .forceTwice }
        if check.isDirty && options.discardChanges { return .force }
        return .none
    }

    // MARK: Commands

    private static let recordSeparator: Character = "\u{1e}"
    private static let groupSeparator: Character = "\u{1d}"

    public static let foreignFilesShown = 10

    /// Prints the account, the first few paths it does not own, then how many
    /// there are. A folder it cannot read is skipped, not fatal.
    public static func ownershipProbe(path: String) -> String {
        "{ u=$(id -un) && printf '%s\\n' \"$u\" && find \(quote(path)) ! -user \"$u\" -print 2>/dev/null"
            + " | awk 'NR<=\(foreignFilesShown) {print} END {print NR}'; }"
    }

    /// Reads, never writes. Each probe that may fail on its own (no upstream,
    /// no main branch) prints nothing instead of stopping the rest. The
    /// ownership walk costs a pass over every file, so only the check for
    /// one worktree makes it.
    public static func checkCommand(path: String, mainBranch: String?, includeOwnership: Bool = true) -> String {
        let separator = " && printf '\\036' && "
        let upstream = "{ git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true; }"
        let unpushed = "{ git rev-list --count '@{upstream}..HEAD' 2>/dev/null || true; }"
        let unmerged = mainBranch.map {
            "{ git rev-list --count \(quote("refs/heads/\($0)..HEAD")) 2>/dev/null || true; }"
        } ?? "true"
        return "cd \(quote(path)) && git status --porcelain"
            + separator + upstream
            + separator + unpushed
            + separator + unmerged
            + separator + "git worktree list --porcelain"
            + (includeOwnership ? separator + ownershipProbe(path: path) : "")
    }

    /// One round trip for every worktree; a path that fails leaves an empty
    /// group, not a wrong answer.
    public static func checkAllCommand(paths: [String], mainBranch: String?) -> String {
        paths
            .map { "( \(checkCommand(path: $0, mainBranch: mainBranch, includeOwnership: false)) ); printf '\\035'" }
            .joined(separator: "; ")
    }

    public static func parseCheck(_ output: String, path: String, mainBranch: String?) -> WorktreeCheck? {
        let sections = output
            .split(separator: recordSeparator, omittingEmptySubsequences: false)
            .map(String.init)
        guard sections.count >= 5 else { return nil }
        let entry = GitSnapshotParser.parseWorktreeList(sections[4]).first { $0.path == path }
        guard let entry else { return nil }
        let upstream = trimmed(sections[1])
        return WorktreeCheck(
            path: path,
            branch: entry.branch,
            upstream: upstream,
            uncommittedChanges: sections[0].split(separator: "\n").filter { !$0.isEmpty }.count,
            unpushedCommits: upstream == nil ? nil : trimmed(sections[2]).flatMap { Int($0) },
            unmergedCommits: mainBranch == nil ? nil : trimmed(sections[3]).flatMap { Int($0) },
            mainBranch: mainBranch,
            isLocked: entry.isLocked,
            lockReason: entry.lockReason,
            foreignFiles: sections.count > 5 ? parseForeignFiles(sections[5]) : nil)
    }

    public static func parseForeignFiles(_ section: String) -> ForeignFiles? {
        let lines = section.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        guard lines.count >= 2, let count = Int(lines[lines.count - 1]) else { return nil }
        return ForeignFiles(user: lines[0], paths: Array(lines[1..<(lines.count - 1)]), count: count)
    }

    /// After git gave up: is the folder still there, does git still know it,
    /// and who owns what is left. Reads only.
    public static func leftoverCommand(path: String, mainWorktree: String) -> String {
        "cd \(quote(mainWorktree))"
            + " && { [ -e \(quote(path)) ] && echo present || echo gone; }"
            + " && printf '\\036' && git worktree list --porcelain"
            + " && printf '\\036' && { [ ! -e \(quote(path)) ] || \(ownershipProbe(path: path)); }"
    }

    public static func parseLeftover(_ output: String, path: String) -> WorktreeLeftover? {
        let sections = output
            .split(separator: recordSeparator, omittingEmptySubsequences: false)
            .map(String.init)
        guard sections.count >= 3 else { return nil }
        let state = sections[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard state == "present" || state == "gone" else { return nil }
        return WorktreeLeftover(
            path: path,
            exists: state == "present",
            isRegistered: GitSnapshotParser.parseWorktreeList(sections[1]).contains { $0.path == path },
            foreignFiles: parseForeignFiles(sections[2]))
    }

    /// git's record of a worktree whose folder is already gone.
    public static func pruneCommand(mainWorktree: String) -> String {
        "cd \(quote(mainWorktree)) && git worktree prune"
    }

    /// A folder git no longer knows and the user owns entirely: a read-only
    /// subfolder is what stops `rm`, so it is made writable first. Never the
    /// main checkout or anything holding it. BSD `chmod` reads `--` after the
    /// mode as a file name; the path is absolute, so it can't pass for a flag.
    public static func deleteLeftoverCommand(path: String, mainWorktree: String) -> String? {
        guard isRemovablePath(path, mainWorktree: mainWorktree) else { return nil }
        return "cd \(quote(mainWorktree)) && chmod -R u+w \(quote(path))"
            + " && rm -rf -- \(quote(path)) && git worktree prune"
    }

    static func isRemovablePath(_ path: String, mainWorktree: String) -> Bool {
        guard path.hasPrefix("/"), path.count > 1, !path.hasSuffix("/") else { return false }
        return path != mainWorktree && !mainWorktree.hasPrefix(path + "/")
    }

    public static func parseCheckAll(_ output: String, paths: [String], mainBranch: String?) -> [WorktreeCheck] {
        let groups = output.split(separator: groupSeparator, omittingEmptySubsequences: false).map(String.init)
        return zip(paths, groups).compactMap { path, group in
            parseCheck(group, path: path, mainBranch: mainBranch)
        }
    }

    /// Runs from the main checkout, since a worktree cannot remove itself.
    /// `git worktree remove` never deletes the branch; `-d` (never `-D`)
    /// does, and git itself refuses it when the branch is not merged.
    public static func removeCommand(_ check: WorktreeCheck, options: Options, mainWorktree: String) -> String? {
        guard canRemove(check, options: options) else { return nil }
        var command = "cd \(quote(mainWorktree))"
            + " && git worktree remove\(force(for: check, options: options).flags) -- \(quote(check.path))"
            + " && git worktree prune"
        if options.deleteBranch, canDeleteBranch(check), let branch = check.branch {
            command += " && git branch -d -- \(quote(branch))"
        }
        return command
    }

    /// Only clean, merged, unlocked worktrees, never forced. One failure does
    /// not stop the others, and the exit status still reports it.
    public static func removeMergedCommand(
        _ checks: [WorktreeCheck], deleteBranches: Bool, mainWorktree: String
    ) -> String? {
        let removable = checks.filter(\.isCleanAndMerged)
        guard !removable.isEmpty else { return nil }
        let steps = removable.map { check -> String in
            var step = "git worktree remove -- \(quote(check.path))"
            if deleteBranches, canDeleteBranch(check), let branch = check.branch {
                step += " && git branch -d -- \(quote(branch))"
            }
            return "{ \(step); } || rc=1"
        }
        return "cd \(quote(mainWorktree)) || exit 1; rc=0; "
            + steps.joined(separator: "; ")
            + "; git worktree prune; exit $rc"
    }

    private static func quote(_ value: String) -> String {
        RemoteCommands.shellSingleQuoted(value)
    }

    private static func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
