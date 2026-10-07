import Foundation
import Combine
import DevmachineCore

/// Runs the one thing the app does as a machine's admin, and says which
/// machine a workspace lives on.
protocol WorktreeAdmin: Sendable {
    func machine(forWorkspace workspace: String) -> WorktreeAdminRemoval.Machine?
    func run(machine: String, script: String) throws -> (stdout: String, stderr: String, exitCode: Int32)
}

/// Through the devmachine CLI: `run --machine` logs in as the admin with
/// the CLI's own key and host check.
struct CLIWorktreeAdmin: WorktreeAdmin {
    func machine(forWorkspace workspace: String) -> WorktreeAdminRemoval.Machine? {
        guard let cli = try? DevmachineCLI.resolve(),
              let name = try? cli.listWorkspaces().first(where: { $0.name == workspace })?.machine,
              let machine = try? cli.listConfigMachines().first(where: { $0.name == name })
        else { return nil }
        return WorktreeAdminRemoval.Machine(name: machine.name, isSelf: machine.isSelf, platform: machine.platform)
    }

    func run(machine: String, script: String) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let cli = try DevmachineCLI.resolve()
        return try cli.runner.runCapturing(
            executable: cli.executable, args: ["run", "--machine", machine, "--", script],
            environment: cli.environment())
    }
}

/// One worktree on its way out: the read-only check first, then the
/// confirmation, then the remove. A worktree whose folder is gone only needs
/// a prune; a folder git no longer knows is checked as a leftover.
struct WorktreeRemovalRequest: Identifiable, Equatable {
    enum Phase: Equatable {
        case checking, ready, removing
        case failed(DMErrorState)
        /// The worktree is gone; git refused to delete its branch.
        case removedKeepingBranch(DMErrorState)
    }

    enum Kind: Equatable {
        case worktree, prunable, leftover
    }

    var id: String { worktree.path }
    let worktree: GitSnapshot.Worktree
    var kind: Kind = .worktree
    var check: WorktreeCheck?
    var phase: Phase
    /// What is left after git gave up, or of a folder git no longer knows.
    var leftover: WorktreeLeftover?
    /// Who can delete what the user cannot; nil until it is known.
    var route: WorktreeAdminRemoval.Route?
    var isLocalSession = false
    var mainWorktree: String?

    var foreignFiles: ForeignFiles? { leftover?.foreignFiles ?? check?.foreignFiles }
    var sessionUser: String? { foreignFiles?.user }

    var error: DMErrorState? {
        if case let .failed(state) = phase { return state }
        return nil
    }
}

/// Every clean, merged worktree, removed together. After a run, `checks`
/// holds only what is still there to try again.
struct MergedRemovalRequest: Identifiable, Equatable {
    var id: String { "merged" }
    var checks: [WorktreeCheck]
    var isRemoving = false
    var results: [WorktreeRemovalResult]?

    var summary: String? { results.map(WorktreeRemoval.summary) }
}

@MainActor
final class GitStore: ObservableObject {
    typealias Result = (stdout: String, stderr: String, exitCode: Int32)

    @Published var snapshot: GitSnapshot?
    @Published var errorText: String?
    @Published var isLoading = false
    @Published var removal: WorktreeRemovalRequest?
    @Published var mergedRemoval: MergedRemovalRequest?
    @Published private(set) var mergedWorktrees: [WorktreeCheck] = []

    private let host: HostRunner
    private let admin: WorktreeAdmin
    private let demo: Bool
    private var timer: Timer?
    private var current: CommandTarget?
    private var workspace: String?
    private var inFlight: String?
    private var checkedPaths: [String]?

    init(host: HostRunner = HostRunner(), admin: WorktreeAdmin = CLIWorktreeAdmin(), demo: Bool = DemoMode.isActive) {
        self.host = host
        self.admin = admin
        self.demo = demo
    }

    func start(_ target: CommandTarget, workspace: String? = nil) {
        self.workspace = workspace
        if current == target, timer != nil || demo { return }
        current = target
        clear()
        if demo {
            snapshot = DemoData.gitSnapshot
            mergedWorktrees = DemoData.worktreeChecks.filter(\.isCleanAndMerged)
            return
        }
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isRemoving else { return }
                self.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        current = nil
        inFlight = nil
        clear()
    }

    func refresh() {
        guard let target = current, !demo else { return }
        // Skip the tick while the read for this same target is still running;
        // a switch to another session still reads right away.
        let key = target.key
        guard inFlight != key else { return }
        inFlight = key
        // Loading is only the empty state: flipping it on every tick would
        // re-render the panel twice per poll for data that did not change.
        setLoading(snapshot == nil)
        let host = self.host
        Task.detached {
            let result = try? host.runCapturing(target, RemoteCommands.gitSnapshotBody)
            await MainActor.run {
                self.apply(result, target: target, key: key)
            }
        }
    }

    // MARK: Removing worktrees

    /// The poll waits while git removes: a read inside a worktree being
    /// deleted only fails, and the list is read again right after.
    private var isRemoving: Bool {
        removal?.phase == .removing || mergedRemoval?.isRemoving == true
    }

    func requestRemoval(_ worktree: GitSnapshot.Worktree) {
        guard let target = current, let snapshot,
              WorktreeRemoval.block(worktree, currentRoot: snapshot.root) == nil
        else { return }
        let mainBranch = Self.mainBranch(snapshot)
        if demo {
            let check = DemoData.worktreeChecks.first { $0.path == worktree.path }
            removal = WorktreeRemovalRequest(worktree: worktree, check: check, phase: .ready)
            return
        }
        if worktree.isPrunable {
            removal = newRequest(worktree, kind: .prunable, phase: .ready, target: target)
            return
        }
        removal = newRequest(worktree, kind: .worktree, phase: .checking, target: target)
        let command = WorktreeRemoval.checkCommand(path: worktree.path, mainBranch: mainBranch)
        run(command, on: target) { store, result in
            guard store.removal?.id == worktree.path else { return }
            if let result, result.exitCode == 0,
               let check = WorktreeRemoval.parseCheck(result.stdout, path: worktree.path, mainBranch: mainBranch) {
                store.removal?.check = check
                store.removal?.phase = .ready
                store.resolveRoute(path: worktree.path, user: check.foreignFiles?.user)
            } else {
                store.removal?.phase = .failed(Self.errorState("Could not check the worktree", result))
            }
        }
    }

    /// A folder the snapshot found that git no longer lists.
    func requestLeftoverRemoval(_ path: String) {
        guard let target = current, let snapshot, snapshot.leftovers.contains(path), !demo else { return }
        let worktree = GitSnapshot.Worktree(path: path, head: "", branch: nil, isMain: false)
        removal = newRequest(worktree, kind: .leftover, phase: .checking, target: target)
        checkLeftover(path, then: .ready)
    }

    private func newRequest(
        _ worktree: GitSnapshot.Worktree, kind: WorktreeRemovalRequest.Kind,
        phase: WorktreeRemovalRequest.Phase, target: CommandTarget
    ) -> WorktreeRemovalRequest {
        var request = WorktreeRemovalRequest(worktree: worktree, kind: kind, check: nil, phase: phase)
        request.isLocalSession = target.isLocal
        request.mainWorktree = snapshot.flatMap(Self.mainWorktree)
        return request
    }

    /// Reads what is left of `path`. After a failed remove the error stays on
    /// screen and only the leftover is filled in; for a leftover row the
    /// sheet becomes ready.
    private func checkLeftover(_ path: String, then phase: WorktreeRemovalRequest.Phase?) {
        guard let target = current, let main = snapshot.flatMap(Self.mainWorktree) else { return }
        run(WorktreeRemoval.leftoverCommand(path: path, mainWorktree: main), on: target) { store, result in
            guard store.removal?.id == path else { return }
            let leftover = result.flatMap { $0.exitCode == 0 ? WorktreeRemoval.parseLeftover($0.stdout, path: path) : nil }
            store.removal?.leftover = leftover
            if let phase {
                store.removal?.phase = leftover == nil
                    ? .failed(Self.errorState("Could not check the folder", result))
                    : phase
            }
            store.resolveRoute(path: path, user: leftover?.foreignFiles?.user)
        }
    }

    /// Local sessions never go through an admin, so the CLI is asked only
    /// for a remote one with files another account owns, and off the main
    /// thread.
    private func resolveRoute(path: String, user: String?) {
        guard let request = removal, request.id == path else { return }
        let main = request.mainWorktree ?? ""
        let isLocal = request.isLocalSession
        guard !isLocal, let user, request.foreignFiles?.count ?? 0 > 0 else {
            removal?.route = WorktreeAdminRemoval.route(
                isLocalSession: isLocal, machine: nil, user: user ?? "", path: path, mainWorktree: main)
            return
        }
        let admin = self.admin
        let workspace = self.workspace
        let target = current
        Task.detached {
            let machine = workspace.flatMap { admin.machine(forWorkspace: $0) }
            await MainActor.run {
                guard self.current == target, self.removal?.id == path else { return }
                self.removal?.route = WorktreeAdminRemoval.route(
                    isLocalSession: false, machine: machine, user: user, path: path, mainWorktree: main)
            }
        }
    }

    func confirmRemoval(options: WorktreeRemoval.Options) {
        guard let request = removal, request.phase == .ready, request.kind == .worktree,
              let check = request.check else { return }
        if demo {
            removal = nil
            return
        }
        guard let target = current, let main = snapshot.flatMap(Self.mainWorktree),
              let step = WorktreeRemoval.step(check, options: options),
              let command = WorktreeRemoval.removeCommand([step], mainWorktree: main)
        else { return }
        removal?.phase = .removing
        run(command, on: target) { store, result in
            defer { store.reload() }
            guard store.removal?.id == request.id,
                  let outcome = WorktreeRemoval.parseRemoval(
                    result?.stdout ?? "", steps: [step], failure: Self.failureText(result)).first
            else { return }
            if let details = outcome.failureDetails {
                store.removal?.phase = .failed(Self.removeError(details, check: check))
                if FailureCause(message: details) == .fileAccessDenied {
                    store.checkLeftover(request.id, then: nil)
                }
            } else if case let .kept(reason, details) = outcome.branchOutcome, let branch = step.branch {
                store.removal?.phase = .removedKeepingBranch(DMErrorState(
                    systemImage: "arrow.triangle.branch",
                    title: "Worktree removed, branch \(branch) kept",
                    cause: reason.prefix(1).uppercased() + reason.dropFirst(),
                    details: details))
            } else {
                store.removal = nil
            }
        }
    }

    /// The machine's admin deletes the folder; then, as the user, git's
    /// record goes with a prune and the branch with `-d`.
    func confirmAdminRemoval(options: WorktreeRemoval.Options) {
        guard let request = removal, request.phase == .ready || request.error != nil,
              let route = request.route, case let .admin(machine) = route,
              options.removeAsAdmin, request.foreignFiles?.count ?? 0 > 0,
              let user = request.sessionUser, let main = request.mainWorktree,
              let target = current, !demo
        else { return }
        if request.kind == .worktree, request.leftover == nil {
            guard let check = request.check,
                  WorktreeAdminRemoval.canRemove(check, options: options, route: route) else { return }
        }
        guard let script = WorktreeAdminRemoval.script(path: request.id, mainWorktree: main, user: user) else { return }
        let branch = request.check.flatMap { check -> String? in
            guard options.deleteBranch, WorktreeRemoval.canDeleteBranch(check) else { return nil }
            return check.branch
        }
        let unlock = request.check?.isLocked == true && options.removeLocked
        let after = WorktreeAdminRemoval.afterAdminCommand(
            path: request.id, mainWorktree: main, unlock: unlock, branch: branch)
        removal?.phase = .removing
        let admin = self.admin
        Task.detached {
            let result = try? admin.run(machine: machine, script: script)
            await MainActor.run {
                guard self.current == target, self.removal?.id == request.id else { return }
                guard let result, result.exitCode == 0 else {
                    self.removal?.phase = .failed(Self.errorState("The machine admin did not remove it", result))
                    return
                }
                self.finish(after, request: request, title: "Removed, but git's record was not pruned")
            }
        }
    }

    /// A worktree whose folder is already gone, or one the admin just deleted.
    func prune() {
        guard let request = removal, request.phase != .removing, let main = request.mainWorktree, !demo else { return }
        removal?.phase = .removing
        finish(WorktreeRemoval.pruneCommand(mainWorktree: main), request: request, title: "Could not prune the worktree")
    }

    /// A leftover folder with nothing in it that belongs to someone else.
    func deleteLeftover() {
        guard let request = removal, request.phase != .removing, request.leftover?.exists == true,
              request.foreignFiles?.count == 0, let main = request.mainWorktree, !demo,
              let command = WorktreeRemoval.deleteLeftoverCommand(path: request.id, mainWorktree: main)
        else { return }
        removal?.phase = .removing
        finish(command, request: request, title: "Could not delete the folder")
    }

    private func finish(_ command: String, request: WorktreeRemovalRequest, title: String) {
        guard let target = current else { return }
        run(command, on: target) { store, result in
            if store.removal?.id == request.id {
                if let result, result.exitCode == 0 {
                    store.removal = nil
                } else {
                    store.removal?.phase = .failed(Self.errorState(title, result))
                }
            }
            store.reload()
        }
    }

    func cancelRemoval() {
        guard removal?.phase != .removing else { return }
        removal = nil
    }

    func requestMergedRemoval() {
        guard !mergedWorktrees.isEmpty else { return }
        mergedRemoval = MergedRemovalRequest(checks: mergedWorktrees)
    }

    func confirmMergedRemoval(deleteBranches: Bool) {
        guard let request = mergedRemoval, !request.isRemoving else { return }
        if demo {
            mergedRemoval = nil
            return
        }
        let steps = WorktreeRemoval.mergedSteps(request.checks, deleteBranches: deleteBranches)
        guard let target = current, let main = snapshot.flatMap(Self.mainWorktree),
              let command = WorktreeRemoval.removeCommand(steps, mainWorktree: main)
        else { return }
        mergedRemoval?.isRemoving = true
        run(command, on: target) { store, result in
            defer { store.reload() }
            guard store.mergedRemoval != nil else { return }
            let results = WorktreeRemoval.parseRemoval(
                result?.stdout ?? "", steps: steps, failure: Self.failureText(result))
            if results.allSatisfy({ $0.isGone && $0.keptBranchReason == nil }) {
                store.mergedRemoval = nil
                return
            }
            let failed = Set(results.filter { !$0.isGone }.map(\.path))
            store.mergedRemoval?.results = results
            store.mergedRemoval?.checks = request.checks.filter { failed.contains($0.path) }
            store.mergedRemoval?.isRemoving = false
        }
    }

    func cancelMergedRemoval() {
        guard mergedRemoval?.isRemoving != true else { return }
        mergedRemoval = nil
    }

    // MARK: Private

    private func run(
        _ command: String, on target: CommandTarget,
        then finish: @escaping @MainActor (GitStore, Result?) -> Void
    ) {
        let host = self.host
        Task.detached {
            let result = try? host.runCapturingAnywhere(target, command)
            await MainActor.run {
                guard self.current == target else { return }
                finish(self, result)
            }
        }
    }

    /// A read right after a change, even when a poll is still running.
    private func reload() {
        inFlight = nil
        checkedPaths = nil
        refresh()
    }

    private func apply(_ result: Result?, target: CommandTarget, key: String) {
        if inFlight == key { inFlight = nil }
        guard current == target else { return }
        setLoading(false)
        let parsed = result.flatMap { GitSnapshotParser.parse($0.stdout) }
        if snapshot != parsed {
            snapshot = parsed
        }
        let failure = parsed == nil ? Self.failure(result) : nil
        if errorText != failure {
            errorText = failure
        }
        checkMerged(parsed, target: target)
    }

    /// Only when the list of worktrees changes, not on every poll.
    private func checkMerged(_ snapshot: GitSnapshot?, target: CommandTarget) {
        guard let snapshot else { return }
        let paths = snapshot.worktrees
            .filter { WorktreeRemoval.block($0, currentRoot: snapshot.root) == nil && !$0.isPrunable }
            .map(\.path)
        guard paths != checkedPaths else { return }
        checkedPaths = paths
        guard !paths.isEmpty else {
            if !mergedWorktrees.isEmpty { mergedWorktrees = [] }
            return
        }
        let mainBranch = Self.mainBranch(snapshot)
        let command = WorktreeRemoval.checkAllCommand(paths: paths, mainBranch: mainBranch)
        run(command, on: target) { store, result in
            guard store.checkedPaths == paths else { return }
            let checks = result.map {
                WorktreeRemoval.parseCheckAll($0.stdout, paths: paths, mainBranch: mainBranch)
            } ?? []
            let merged = checks.filter(\.isCleanAndMerged)
            if store.mergedWorktrees != merged { store.mergedWorktrees = merged }
        }
    }

    private static func mainBranch(_ snapshot: GitSnapshot) -> String? {
        snapshot.worktrees.first(where: \.isMain)?.branch
    }

    private static func mainWorktree(_ snapshot: GitSnapshot) -> String? {
        snapshot.worktrees.first(where: \.isMain)?.path
    }

    /// What a removal says about a worktree its output never reached.
    private static func failureText(_ result: Result?) -> String {
        guard let result else { return "The command could not start" }
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return stderr.isEmpty ? "git exited with status \(result.exitCode)" : stderr
    }

    /// git's "Permission denied" names a file the account cannot delete, not
    /// a login the machine refused, so it says whose account and where.
    private static func removeError(_ details: String, check: WorktreeCheck) -> DMErrorState {
        let state = DMErrorState(title: "Could not remove the worktree", message: details)
        guard FailureCause(message: details) == .fileAccessDenied else { return state }
        let deniedAt = check.foreignFiles?.paths.first ?? WorktreeRemovalText.deniedPath(details)
        return DMErrorState(
            title: state.title,
            cause: WorktreeRemovalText.permissionCause(user: check.foreignFiles?.user, path: deniedAt),
            details: state.details)
    }

    private static func errorState(_ title: String, _ result: Result?) -> DMErrorState {
        guard let result else { return DMErrorState(title: title, message: "The command could not start") }
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = !stderr.isEmpty ? stderr
            : !stdout.isEmpty ? stdout
            : "git exited with status \(result.exitCode)"
        return DMErrorState(title: title, message: message)
    }

    // No snapshot and no message means "not a git repository", which the view words itself.
    private static func failure(_ result: Result?) -> String? {
        guard let result else { return "Could not read the folder" }
        let line = result.stderr
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line, !line.localizedCaseInsensitiveContains("not a git repository") else { return nil }
        return line
    }

    private func setLoading(_ value: Bool) {
        if isLoading != value {
            isLoading = value
        }
    }

    private func clear() {
        if snapshot != nil { snapshot = nil }
        if errorText != nil { errorText = nil }
        if removal != nil { removal = nil }
        if mergedRemoval != nil { mergedRemoval = nil }
        if !mergedWorktrees.isEmpty { mergedWorktrees = [] }
        checkedPaths = nil
    }
}
