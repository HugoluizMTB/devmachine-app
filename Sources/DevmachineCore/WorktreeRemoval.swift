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

/// What happened to one worktree, and to its branch, in a removal.
public struct WorktreeRemovalResult: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case removed
        /// The folder was gone before git got to it; its record is pruned.
        case alreadyGone
        case failed(details: String)
    }

    public enum BranchOutcome: Equatable, Sendable {
        case notRequested, deleted, alreadyGone
        case kept(reason: String, details: String)
    }

    public let path: String
    public let branch: String?
    public let outcome: Outcome
    public let branchOutcome: BranchOutcome

    public init(path: String, branch: String?, outcome: Outcome, branchOutcome: BranchOutcome) {
        self.path = path
        self.branch = branch
        self.outcome = outcome
        self.branchOutcome = branchOutcome
    }

    public var isGone: Bool {
        if case .failed = outcome { return false }
        return true
    }

    public var keptBranchReason: String? {
        if case let .kept(reason, _) = branchOutcome { return reason }
        return nil
    }

    public var failureDetails: String? {
        if case let .failed(details) = outcome { return details }
        return nil
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

        public var flags: String {
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
    private static let unitSeparator: Character = "\u{1f}"

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

    /// One worktree to remove, and the branch to delete after it, if any.
    public struct RemovalStep: Equatable, Sendable {
        public let path: String
        public let branch: String?
        public let force: Force

        public init(path: String, branch: String?, force: Force) {
            self.path = path
            self.branch = branch
            self.force = force
        }
    }

    public static func step(_ check: WorktreeCheck, options: Options) -> RemovalStep? {
        guard canRemove(check, options: options) else { return nil }
        let branch = options.deleteBranch && canDeleteBranch(check) ? check.branch : nil
        return RemovalStep(path: check.path, branch: branch, force: force(for: check, options: options))
    }

    /// Only clean, merged, unlocked worktrees, never forced.
    public static func mergedSteps(_ checks: [WorktreeCheck], deleteBranches: Bool) -> [RemovalStep] {
        checks.filter(\.isCleanAndMerged).compactMap { step($0, options: Options(deleteBranch: deleteBranches)) }
    }

    /// Runs from the main checkout, since a worktree cannot remove itself,
    /// one worktree after the other in a single shell. Each step prints its
    /// own record, so one failure neither stops the rest nor hides what they
    /// did. A folder that is gone counts whoever removed it: the record is
    /// pruned and the branch step still runs. `git worktree remove` never
    /// deletes the branch; `-d` (never `-D`) does, and git refuses it when
    /// the branch is not merged into its upstream, or HEAD without one.
    public static func removeCommand(_ steps: [RemovalStep], mainWorktree: String) -> String? {
        guard !steps.isEmpty else { return nil }
        let body = steps.map { step -> String in
            let path = quote(step.path)
            let branch = step.branch.map {
                "; o=$(git branch -d -- \(quote($0)) 2>&1); printf '\\037%s\\037%s' \"$?\" \"$o\""
            } ?? ""
            return "o=$(git worktree remove\(step.force.flags) -- \(path) 2>&1); printf '%s\\037%s\\037' \"$?\" \"$o\""
                + "; if [ -e \(path) ]; then printf present"
                + "; else printf gone; git worktree prune >/dev/null 2>&1\(branch); fi"
                + "; printf '\\035'"
        }
        return "cd \(quote(mainWorktree)) || exit 1; "
            + body.joined(separator: "; ")
            + "; git worktree prune"
    }

    /// One result per step, in order. A step the output never reached (the
    /// shell or the connection died) failed with `failure`.
    public static func parseRemoval(_ output: String, steps: [RemovalStep], failure: String) -> [WorktreeRemovalResult] {
        let records = output.split(separator: groupSeparator, omittingEmptySubsequences: false).map(String.init)
        return steps.enumerated().map { index, step in
            let fields = index < records.count
                ? records[index].split(separator: unitSeparator, omittingEmptySubsequences: false).map(String.init)
                : []
            guard fields.count >= 3, let code = Int32(fields[0].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return WorktreeRemovalResult(
                    path: step.path, branch: step.branch,
                    outcome: .failed(details: failure.isEmpty ? "No answer for this worktree" : failure),
                    branchOutcome: .notRequested)
            }
            let message = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let isGone = fields[2] == "gone"
            let outcome: WorktreeRemovalResult.Outcome = code == 0 ? .removed
                : isGone ? .alreadyGone
                : .failed(details: message.isEmpty ? "git exited with status \(code)" : message)
            var branchOutcome = WorktreeRemovalResult.BranchOutcome.notRequested
            if step.branch != nil, isGone {
                branchOutcome = fields.count >= 5
                    ? parseBranch(code: fields[3], message: fields[4].trimmingCharacters(in: .whitespacesAndNewlines))
                    : .kept(reason: "not deleted", details: failure)
            }
            return WorktreeRemovalResult(path: step.path, branch: step.branch, outcome: outcome, branchOutcome: branchOutcome)
        }
    }

    private static func parseBranch(code: String, message: String) -> WorktreeRemovalResult.BranchOutcome {
        if code.trimmingCharacters(in: .whitespacesAndNewlines) == "0" { return .deleted }
        if message.contains("not found") { return .alreadyGone }
        return .kept(reason: keptBranchReason(message), details: message)
    }

    /// git's words for why `-d` refused, made short enough for one line.
    static func keptBranchReason(_ message: String) -> String {
        if let marker = message.range(of: "not yet merged to") {
            let rest = message[marker.upperBound...]
            if let open = rest.firstIndex(of: "'"),
               let close = rest[rest.index(after: open)...].firstIndex(of: "'") {
                var ref = String(rest[rest.index(after: open)..<close])
                for prefix in ["refs/remotes/", "refs/heads/"] where ref.hasPrefix(prefix) {
                    ref = String(ref.dropFirst(prefix.count))
                }
                return "not merged into \(ref)"
            }
        }
        if message.contains("used by worktree") || message.contains("checked out at") {
            return "checked out in another worktree"
        }
        if message.contains("not fully merged") { return "not fully merged" }
        let line = message.split(separator: "\n").first.map(String.init) ?? message
        return line.replacingOccurrences(of: "error: ", with: "")
    }

    /// "3 removed, 1 branch kept: not merged into main". The reason shows
    /// only when every kept branch has the same one.
    public static func summary(_ results: [WorktreeRemovalResult]) -> String {
        var parts: [String] = []
        let removed = results.filter(\.isGone).count
        let failed = results.count - removed
        if removed > 0 { parts.append("\(removed) removed") }
        if failed > 0 { parts.append("\(failed) failed") }
        let reasons = results.compactMap(\.keptBranchReason)
        if !reasons.isEmpty {
            let kept = reasons.count == 1 ? "1 branch kept" : "\(reasons.count) branches kept"
            parts.append(Set(reasons).count == 1 ? "\(kept): \(reasons[0])" : kept)
        }
        return parts.joined(separator: ", ")
    }

    private static func quote(_ value: String) -> String {
        RemoteCommands.shellSingleQuoted(value)
    }

    private static func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
