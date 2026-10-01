import SwiftUI
import DevmachineCore

/// The words the removal sheets show, kept apart so they can be tested.
enum WorktreeRemovalText {
    static func shortPath(_ path: String) -> String {
        path.split(separator: "/").suffix(2).joined(separator: "/")
    }

    static func removeMergedTitle(_ count: Int) -> String {
        count == 1 ? "Remove 1 merged…" : "Remove \(count) merged…"
    }

    struct Warning: Equatable, Hashable {
        let systemImage: String
        let text: String
        let isSerious: Bool
    }

    static func warnings(_ check: WorktreeCheck, deletingBranch: Bool) -> [Warning] {
        var warnings: [Warning] = []
        if check.isDirty {
            warnings.append(Warning(
                systemImage: "pencil.circle",
                text: plural(check.uncommittedChanges, "uncommitted change") + " will be lost",
                isSerious: true))
        }
        if let unpushed = check.unpushedCommits, unpushed > 0, let upstream = check.upstream {
            warnings.append(Warning(
                systemImage: "arrow.up.circle",
                text: plural(unpushed, "commit") + " not pushed to \(upstream)",
                isSerious: true))
        }
        if let unmerged = check.unmergedCommits, unmerged > 0, let main = check.mainBranch {
            warnings.append(Warning(
                systemImage: "arrow.triangle.merge",
                text: plural(unmerged, "commit") + " not merged into \(main)",
                isSerious: true))
        }
        if check.isLocked {
            warnings.append(Warning(
                systemImage: "lock",
                text: "Locked" + (check.lockReason.map { ": \($0)" } ?? ""),
                isSerious: true))
        }
        if let branch = check.branch, !deletingBranch {
            warnings.append(Warning(
                systemImage: "arrow.triangle.branch",
                text: "Branch \(branch) will be kept",
                isSerious: false))
        }
        return warnings
    }

    static func foreignWarning(_ foreign: ForeignFiles) -> String {
        let files = foreign.count == 1 ? "1 file here belongs" : "\(foreign.count) files here belong"
        return "\(files) to another user (e.g. root) — git can't delete them"
    }

    static func permissionCause(user: String?, path: String?) -> String {
        let who = user.map { "by \($0)" } ?? "by this account"
        return "Some files in this worktree can't be deleted \(who)" + (path.map { ": \($0)" } ?? ".")
    }

    /// The path git or rm names in "failed to delete '…'" / "cannot remove '…'".
    static func deniedPath(_ stderr: String) -> String? {
        for line in stderr.split(separator: "\n") where line.localizedCaseInsensitiveContains("permission denied") {
            guard let open = line.firstIndex(of: "'"),
                  let close = line[line.index(after: open)...].firstIndex(of: "'") else { continue }
            return String(line[line.index(after: open)..<close])
        }
        return nil
    }

    static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}

/// Removing a worktree cannot be undone, so Return and Escape both cancel and
/// removing takes a click or ⌘⌫, like the end-session sheet. Files another
/// account owns get their own section: the machine's admin can delete them,
/// behind a second checkbox, or the sheet shows the commands to run.
struct WorktreeRemovalSheet: View {
    @Environment(\.dmMetrics) private var m
    let request: WorktreeRemovalRequest
    let onRemove: (WorktreeRemoval.Options) -> Void
    let onRemoveAsAdmin: (WorktreeRemoval.Options) -> Void
    let onPrune: () -> Void
    let onDeleteLeftover: () -> Void
    let onCancel: () -> Void
    @State private var options = WorktreeRemoval.Options()

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            Text(verbatim: WorktreeRemovalText.sheetTitle(request.kind))
                .font(.headline)
            VStack(alignment: .leading, spacing: m.pt(3)) {
                Text(verbatim: request.worktree.path)
                    .font(.dm(11.5, design: .monospaced))
                    .foregroundStyle(Color.dmRowText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if request.kind != .leftover {
                    Text(verbatim: request.worktree.branch.map { "on \($0)" } ?? "detached HEAD")
                        .font(.dm(11.5))
                        .foregroundStyle(Color.dmMuted)
                }
            }
            phaseBody
            HStack {
                Spacer()
                DMButton(isFinished ? "Done" : "Cancel", variant: .outline, action: onCancel)
                    .keyboardShortcut(.defaultAction)
                    .disabled(request.phase == .removing)
                primaryButton
            }
        }
        .padding(m.pt(20))
        .frame(width: m.card.sheetLarge)
        .onExitCommand(perform: onCancel)
        .interactiveDismissDisabled(request.phase == .removing)
    }

    private var isRemoving: Bool { request.phase == .removing }

    private var isFinished: Bool {
        if case .removedKeepingBranch = request.phase { return true }
        return false
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch WorktreeRemovalText.primaryAction(request) {
        case .remove:
            DMButton("Remove", variant: .danger, role: .destructive, isLoading: isRemoving) { onRemove(options) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!canRemove)
        case .prune:
            DMButton("Prune", variant: .primary, isLoading: isRemoving, action: onPrune)
                .disabled(isRemoving || request.phase == .checking)
        case .deleteFolder:
            DMButton("Delete folder", variant: .danger, role: .destructive, isLoading: isRemoving, action: onDeleteLeftover)
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(isRemoving)
        case nil:
            EmptyView()
        }
    }

    private var canRemove: Bool {
        guard let check = request.check, request.phase == .ready else { return false }
        return WorktreeRemoval.canRemove(check, options: options)
    }

    @ViewBuilder
    private var phaseBody: some View {
        switch request.phase {
        case .checking:
            HStack(spacing: m.space.md) {
                ProgressView().controlSize(.small)
                Text(verbatim: request.kind == .leftover ? "Checking the folder…" : "Checking the worktree…")
                    .font(.dm(12))
                    .foregroundStyle(Color.dmMuted)
            }
        case let .removedKeepingBranch(state):
            DMErrorStateView(state: state)
                .frame(maxWidth: .infinity)
        case let .failed(state):
            DMErrorStateView(state: state, startsExpanded: true)
                .frame(maxWidth: .infinity)
            if let leftover = request.leftover {
                leftoverBody(leftover)
            }
        case .ready, .removing:
            switch request.kind {
            case .worktree:
                if let check = request.check {
                    details(check)
                }
            case .prunable:
                note("Its folder is already gone. Prune removes git's record of it.")
            case .leftover:
                if let leftover = request.leftover {
                    leftoverBody(leftover)
                }
            }
        }
    }

    @ViewBuilder
    private func leftoverBody(_ leftover: WorktreeLeftover) -> some View {
        if !leftover.exists {
            note("The folder is gone now. Prune removes what git still remembers of it.")
        } else if let foreign = leftover.foreignFiles, foreign.count > 0 {
            note("Git no longer lists this worktree, but its folder is still here.")
            ownership(foreign)
        } else {
            note("Git no longer lists this worktree, but its folder is still here. Every file in it is yours, so it can be deleted without an admin.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dm(12))
            .foregroundStyle(Color.dmMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func details(_ check: WorktreeCheck) -> some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            let warnings = WorktreeRemovalText.warnings(check, deletingBranch: options.deleteBranch)
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: m.pt(5)) {
                    ForEach(warnings, id: \.self) { warning in
                        Label {
                            Text(verbatim: warning.text)
                        } icon: {
                            Image(systemName: warning.systemImage)
                        }
                        .font(.dm(12))
                        .foregroundStyle(warning.isSerious ? Color.yellow : Color.dmMuted)
                    }
                }
            }
            VStack(alignment: .leading, spacing: m.space.sm) {
                if WorktreeRemoval.canDeleteBranch(check), let branch = check.branch {
                    Toggle(isOn: $options.deleteBranch) {
                        Text(verbatim: "Also delete branch \(branch)")
                    }
                }
                if check.isDirty {
                    Toggle(isOn: $options.discardChanges) {
                        Text(verbatim: "Discard uncommitted changes")
                    }
                }
                if check.isLocked {
                    Toggle(isOn: $options.removeLocked) {
                        Text(verbatim: "Remove even though it's locked")
                    }
                }
            }
            .toggleStyle(.checkbox)
            .font(.dm(12))
            .disabled(isRemoving)
            if let foreign = check.foreignFiles, foreign.count > 0 {
                ownership(foreign)
            }
        }
    }

    private func ownership(_ foreign: ForeignFiles) -> some View {
        VStack(alignment: .leading, spacing: m.space.md) {
            Label {
                Text(verbatim: WorktreeRemovalText.foreignWarning(foreign))
            } icon: {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
            }
            .font(.dm(12))
            .foregroundStyle(Color.yellow)
            VStack(alignment: .leading, spacing: m.space.xxs) {
                ForEach(foreign.paths, id: \.self) { path in
                    Text(verbatim: path)
                        .font(.dm(11, design: .monospaced))
                        .foregroundStyle(Color.dmRowText)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(path)
                }
                if let more = WorktreeRemovalText.moreForeign(foreign) {
                    Text(verbatim: more)
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                }
            }
            .textSelection(.enabled)
            .padding(m.pt(10))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dmBand, in: RoundedRectangle(cornerRadius: m.radius.tile, style: .continuous))
            routeBody
        }
    }

    @ViewBuilder
    private var routeBody: some View {
        switch request.route {
        case nil:
            HStack(spacing: m.space.md) {
                ProgressView().controlSize(.small)
                note("Looking up the machine…")
            }
        case let .admin(machine):
            VStack(alignment: .leading, spacing: m.space.md) {
                Toggle(isOn: $options.removeAsAdmin) {
                    Text(verbatim: WorktreeRemovalText.adminConsent(machine: machine))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.checkbox)
                .font(.dm(12))
                .disabled(isRemoving)
                HStack {
                    Spacer()
                    DMButton(
                        "Remove as machine admin…", systemImage: "exclamationmark.shield",
                        variant: .danger, role: .destructive, isLoading: isRemoving
                    ) { onRemoveAsAdmin(options) }
                        .disabled(!canRemoveAsAdmin)
                        .help(WorktreeRemovalText.adminHelp(machine: machine))
                }
            }
        case let .manual(reason):
            let steps = WorktreeAdminRemoval.manualSteps(
                path: request.id, mainWorktree: request.mainWorktree ?? "", isLocalSession: request.isLocalSession)
            VStack(alignment: .leading, spacing: m.space.sm) {
                note(reason.text + " To remove it by hand:")
                Text(verbatim: request.isLocalSession ? "In a terminal on this Mac:" : "On the machine, as its admin:")
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                DMCommandBlock(steps.asAdmin)
                Text(verbatim: "Then, as \(request.sessionUser ?? "the session's user"):")
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
                DMCommandBlock(steps.asUser)
            }
        }
    }

    private var canRemoveAsAdmin: Bool {
        guard let route = request.route, !isRemoving, options.removeAsAdmin else { return false }
        if request.kind == .worktree, request.leftover == nil {
            guard let check = request.check, request.phase == .ready else { return false }
            return WorktreeAdminRemoval.canRemove(check, options: options, route: route)
        }
        if case .admin = route { return true }
        return false
    }
}

extension WorktreeRemovalText {
    enum PrimaryAction: Equatable {
        case remove, prune, deleteFolder
    }

    static func sheetTitle(_ kind: WorktreeRemovalRequest.Kind) -> String {
        switch kind {
        case .worktree: return "Remove worktree?"
        case .prunable: return "Prune worktree?"
        case .leftover: return "Remove leftover folder?"
        }
    }

    /// The button beside Cancel. Removing as the admin is never here: it
    /// lives under the files it deletes, behind its own checkbox.
    static func primaryAction(_ request: WorktreeRemovalRequest) -> PrimaryAction? {
        if case .removedKeepingBranch = request.phase { return nil }
        if let leftover = request.leftover {
            if !leftover.exists { return .prune }
            return leftover.foreignFiles?.count == 0 ? .deleteFolder : nil
        }
        switch request.kind {
        case .worktree: return request.error == nil ? .remove : nil
        case .prunable: return .prune
        case .leftover: return nil
        }
    }

    static func moreForeign(_ foreign: ForeignFiles) -> String? {
        let more = foreign.count - foreign.paths.count
        return more > 0 ? "and \(more) more" : nil
    }

    static func adminConsent(machine: String) -> String {
        "Delete this folder as \(machine)'s admin, other users' files included. This can't be undone."
    }

    static func adminHelp(machine: String) -> String {
        "Runs on \(machine) as its admin through the devmachine CLI, after checking again that this is a worktree inside the account's home"
    }
}

/// Every clean, fully merged worktree at once. Nothing here is forced: a
/// worktree that changed since the check makes git refuse it, and only that
/// one. After a run the sheet shows what happened to each worktree, and
/// "Try again" offers only the ones still there.
struct MergedWorktreesRemovalSheet: View {
    @Environment(\.dmMetrics) private var m
    let request: MergedRemovalRequest
    let onRemove: (Bool) -> Void
    let onCancel: () -> Void
    @State private var deleteBranches = false

    private var canRemove: Bool { !request.checks.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: m.space.lg) {
            Text(verbatim: WorktreeRemovalText.mergedTitle(request))
                .font(.headline)
            if request.results == nil {
                Text(verbatim: "Each one has no uncommitted changes and every commit is already in the main branch.")
                    .font(.dm(12))
                    .foregroundStyle(Color.dmMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: m.space.sm) {
                if let results = request.results {
                    ForEach(results, id: \.path) { resultRow($0) }
                } else {
                    ForEach(request.checks, id: \.path) { checkRow($0) }
                }
            }
            .padding(m.pt(10))
            .background(Color.dmBand, in: RoundedRectangle(cornerRadius: m.radius.tile, style: .continuous))
            if canRemove {
                Toggle(isOn: $deleteBranches) {
                    Text(verbatim: request.checks.count == 1 ? "Also delete its branch" : "Also delete their branches")
                }
                .toggleStyle(.checkbox)
                .font(.dm(12))
                .disabled(request.isRemoving)
            }
            HStack {
                Spacer()
                DMButton(request.results == nil ? "Cancel" : "Done", variant: .outline, action: onCancel)
                    .keyboardShortcut(.defaultAction)
                    .disabled(request.isRemoving)
                if canRemove {
                    DMButton(
                        request.results == nil ? "Remove" : "Try again", variant: .danger, role: .destructive,
                        isLoading: request.isRemoving
                    ) {
                        onRemove(deleteBranches)
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            }
        }
        .padding(m.pt(20))
        .frame(width: m.card.sheet)
        .onExitCommand(perform: onCancel)
        .interactiveDismissDisabled(request.isRemoving)
    }

    private func checkRow(_ check: WorktreeCheck) -> some View {
        HStack(spacing: m.space.sm) {
            pathText(check.path)
            Spacer(minLength: m.space.xs)
            if let branch = check.branch {
                Text(verbatim: branch)
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .lineLimit(1)
            }
        }
        .help(check.path)
    }

    private func resultRow(_ result: WorktreeRemovalResult) -> some View {
        let status = WorktreeRemovalText.status(result)
        return VStack(alignment: .leading, spacing: m.pt(3)) {
            HStack(spacing: m.space.sm) {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status.isSerious ? Color.red : status.isWarning ? Color.yellow : Color.green)
                    .font(.dm(11))
                pathText(result.path)
                Spacer(minLength: m.space.xs)
                Text(verbatim: status.text)
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                    .lineLimit(1)
            }
            if let details = result.failureDetails {
                Text(verbatim: details)
                    .font(.dm(10.5, design: .monospaced))
                    .foregroundStyle(Color.dmMuted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(result.path)
    }

    private func pathText(_ path: String) -> some View {
        Text(verbatim: WorktreeRemovalText.shortPath(path))
            .font(.dm(11.5, design: .monospaced))
            .foregroundStyle(Color.dmRowText)
            .lineLimit(1)
            .truncationMode(.head)
    }
}

extension WorktreeRemovalText {
    static func mergedTitle(_ request: MergedRemovalRequest) -> String {
        request.summary ?? "Remove \(plural(request.checks.count, "merged worktree"))?"
    }

    struct Status: Equatable {
        let systemImage: String
        let text: String
        let isWarning: Bool
        let isSerious: Bool
    }

    /// One line per worktree after a removal: what happened to the folder,
    /// then to the branch.
    static func status(_ result: WorktreeRemovalResult) -> Status {
        if result.failureDetails != nil {
            return Status(systemImage: "xmark.circle.fill", text: "Not removed", isWarning: false, isSerious: true)
        }
        if let reason = result.keptBranchReason {
            return Status(
                systemImage: "exclamationmark.triangle.fill",
                text: "Removed, branch kept: \(reason)", isWarning: true, isSerious: false)
        }
        let removed = result.outcome == .alreadyGone ? "Already gone" : "Removed"
        switch result.branchOutcome {
        case .deleted, .alreadyGone:
            return Status(systemImage: "checkmark.circle.fill", text: removed + ", branch deleted", isWarning: false, isSerious: false)
        case .notRequested, .kept:
            return Status(systemImage: "checkmark.circle.fill", text: removed, isWarning: false, isSerious: false)
        }
    }
}
