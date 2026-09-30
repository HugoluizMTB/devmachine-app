import Foundation
import Combine
import DevmachineCore

/// One worktree on its way out: the read-only check first, then the
/// confirmation, then the remove.
struct WorktreeRemovalRequest: Identifiable, Equatable {
    enum Phase: Equatable {
        case checking, ready, removing
        case failed(DMErrorState)
    }

    var id: String { worktree.path }
    let worktree: GitSnapshot.Worktree
    var check: WorktreeCheck?
    var phase: Phase

    var error: DMErrorState? {
        if case let .failed(state) = phase { return state }
        return nil
    }
}

/// Every clean, merged worktree, removed together.
struct MergedRemovalRequest: Identifiable, Equatable {
    var id: String { "merged" }
    let checks: [WorktreeCheck]
    var isRemoving = false
    var error: DMErrorState?
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
    private let demo: Bool
    private var timer: Timer?
    private var current: CommandTarget?
    private var inFlight: String?
    private var checkedPaths: [String]?

    init(host: HostRunner = HostRunner(), demo: Bool = DemoMode.isActive) {
        self.host = host
        self.demo = demo
    }

    func start(_ target: CommandTarget) {
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
            Task { @MainActor in self?.refresh() }
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
        removal = WorktreeRemovalRequest(worktree: worktree, check: nil, phase: .checking)
        let command = WorktreeRemoval.checkCommand(path: worktree.path, mainBranch: mainBranch)
        run(command, on: target) { store, result in
            guard store.removal?.id == worktree.path else { return }
            if let result, result.exitCode == 0,
               let check = WorktreeRemoval.parseCheck(result.stdout, path: worktree.path, mainBranch: mainBranch) {
                store.removal?.check = check
                store.removal?.phase = .ready
            } else {
                store.removal?.phase = .failed(Self.errorState("Could not check the worktree", result))
            }
        }
    }

    func confirmRemoval(options: WorktreeRemoval.Options) {
        guard let request = removal, request.phase == .ready, let check = request.check else { return }
        if demo {
            removal = nil
            return
        }
        guard let target = current, let main = snapshot.flatMap(Self.mainWorktree),
              let command = WorktreeRemoval.removeCommand(check, options: options, mainWorktree: main)
        else { return }
        removal?.phase = .removing
        run(command, on: target) { store, result in
            if let result, result.exitCode == 0 {
                if store.removal?.id == request.id { store.removal = nil }
            } else if store.removal?.id == request.id {
                store.removal?.phase = .failed(Self.errorState("Could not remove the worktree", result))
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
        guard let target = current, let main = snapshot.flatMap(Self.mainWorktree),
              let command = WorktreeRemoval.removeMergedCommand(
                request.checks, deleteBranches: deleteBranches, mainWorktree: main)
        else { return }
        mergedRemoval?.isRemoving = true
        mergedRemoval?.error = nil
        run(command, on: target) { store, result in
            if let result, result.exitCode == 0 {
                store.mergedRemoval = nil
            } else {
                store.mergedRemoval?.isRemoving = false
                store.mergedRemoval?.error = Self.errorState("Some worktrees were not removed", result)
            }
            store.reload()
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
            .filter { WorktreeRemoval.block($0, currentRoot: snapshot.root) == nil }
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
