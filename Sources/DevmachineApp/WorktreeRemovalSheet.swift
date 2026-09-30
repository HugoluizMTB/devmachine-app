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

    static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}

/// Removing a worktree cannot be undone, so Return and Escape both cancel and
/// removing takes a click or ⌘⌫, like the end-session sheet.
struct WorktreeRemovalSheet: View {
    let request: WorktreeRemovalRequest
    let onRemove: (WorktreeRemoval.Options) -> Void
    let onCancel: () -> Void
    @State private var options = WorktreeRemoval.Options()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Remove worktree?")
                .font(.headline)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: request.worktree.path)
                    .font(.dm(11.5, design: .monospaced))
                    .foregroundStyle(Color.dmRowText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: request.worktree.branch.map { "on \($0)" } ?? "detached HEAD")
                    .font(.dm(11.5))
                    .foregroundStyle(Color.dmMuted)
            }
            phaseBody
            HStack {
                Spacer()
                DMButton("Cancel", variant: .outline, action: onCancel)
                    .keyboardShortcut(.defaultAction)
                    .disabled(request.phase == .removing)
                DMButton(
                    "Remove", variant: .danger, role: .destructive,
                    isLoading: request.phase == .removing
                ) { onRemove(options) }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(!canRemove)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onExitCommand(perform: onCancel)
        .interactiveDismissDisabled(request.phase == .removing)
    }

    private var canRemove: Bool {
        guard let check = request.check, request.phase == .ready else { return false }
        return WorktreeRemoval.canRemove(check, options: options)
    }

    @ViewBuilder
    private var phaseBody: some View {
        switch request.phase {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(verbatim: "Checking the worktree…")
                    .font(.dm(12))
                    .foregroundStyle(Color.dmMuted)
            }
        case let .failed(state):
            DMErrorStateView(state: state, startsExpanded: true)
                .frame(maxWidth: .infinity)
        case .ready, .removing:
            if let check = request.check {
                details(check)
            }
        }
    }

    private func details(_ check: WorktreeCheck) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let warnings = WorktreeRemovalText.warnings(check, deletingBranch: options.deleteBranch)
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
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
            VStack(alignment: .leading, spacing: 6) {
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
            .disabled(request.phase == .removing)
        }
    }
}

/// Every clean, fully merged worktree at once. Nothing here is forced: a
/// worktree that changed since the check makes git refuse it.
struct MergedWorktreesRemovalSheet: View {
    let request: MergedRemovalRequest
    let onRemove: (Bool) -> Void
    let onCancel: () -> Void
    @State private var deleteBranches = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Remove \(WorktreeRemovalText.plural(request.checks.count, "merged worktree"))?")
                .font(.headline)
            Text(verbatim: "Each one has no uncommitted changes and every commit is already in the main branch.")
                .font(.dm(12))
                .foregroundStyle(Color.dmMuted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(request.checks, id: \.path) { check in
                    HStack(spacing: 6) {
                        Text(verbatim: WorktreeRemovalText.shortPath(check.path))
                            .font(.dm(11.5, design: .monospaced))
                            .foregroundStyle(Color.dmRowText)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer(minLength: 4)
                        if let branch = check.branch {
                            Text(verbatim: branch)
                                .font(.dm(11))
                                .foregroundStyle(Color.dmMuted)
                                .lineLimit(1)
                        }
                    }
                    .help(check.path)
                }
            }
            .padding(10)
            .background(Color.dmBand, in: RoundedRectangle(cornerRadius: DMRadius.tile, style: .continuous))
            Toggle(isOn: $deleteBranches) {
                Text(verbatim: request.checks.count == 1 ? "Also delete its branch" : "Also delete their branches")
            }
            .toggleStyle(.checkbox)
            .font(.dm(12))
            .disabled(request.isRemoving)
            if let error = request.error {
                DMErrorStateView(state: error, startsExpanded: true)
                    .frame(maxWidth: .infinity)
            }
            HStack {
                Spacer()
                DMButton("Cancel", variant: .outline, action: onCancel)
                    .keyboardShortcut(.defaultAction)
                    .disabled(request.isRemoving)
                DMButton("Remove", variant: .danger, role: .destructive, isLoading: request.isRemoving) {
                    onRemove(deleteBranches)
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onExitCommand(perform: onCancel)
        .interactiveDismissDisabled(request.isRemoving)
    }
}
