import Foundation

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

    public init(
        path: String, branch: String?, upstream: String?, uncommittedChanges: Int,
        unpushedCommits: Int?, unmergedCommits: Int?, mainBranch: String?,
        isLocked: Bool, lockReason: String?
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
    }

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

        public init(discardChanges: Bool = false, removeLocked: Bool = false, deleteBranch: Bool = false) {
            self.discardChanges = discardChanges
            self.removeLocked = removeLocked
            self.deleteBranch = deleteBranch
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

    /// Reads, never writes. Each probe that may fail on its own (no upstream,
    /// no main branch) prints nothing instead of stopping the rest.
    public static func checkCommand(path: String, mainBranch: String?) -> String {
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
    }

    /// One round trip for every worktree; a path that fails leaves an empty
    /// group, not a wrong answer.
    public static func checkAllCommand(paths: [String], mainBranch: String?) -> String {
        paths
            .map { "( \(checkCommand(path: $0, mainBranch: mainBranch)) ); printf '\\035'" }
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
            lockReason: entry.lockReason)
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
