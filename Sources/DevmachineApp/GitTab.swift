import SwiftUI
import AppKit
import DevmachineCore

struct GitTab: View {
    @ObservedObject var store: GitStore
    let target: CommandTarget
    @EnvironmentObject var model: AppModel

    private static let sectionPadding = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
    private static let rowHeight: CGFloat = 26
    private static let dotSize: CGFloat = 6
    private static let accent = Color(hex: 0x5AA9E6)

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                content(snapshot)
            } else {
                stateMessage
            }
        }
        .onAppear { store.start(target) }
        .onDisappear { store.stop() }
        .onChange(of: target.key) { _, _ in store.start(target) }
        .sheet(item: $store.removal) { request in
            WorktreeRemovalSheet(
                request: request,
                onRemove: { store.confirmRemoval(options: $0) },
                onCancel: { store.cancelRemoval() })
        }
        .sheet(item: $store.mergedRemoval) { request in
            MergedWorktreesRemovalSheet(
                request: request,
                onRemove: { store.confirmMergedRemoval(deleteBranches: $0) },
                onCancel: { store.cancelMergedRemoval() })
        }
    }

    private func content(_ snapshot: GitSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headBlock(snapshot)
                if snapshot.worktrees.count > 1 {
                    worktreesSection(snapshot.worktrees, root: snapshot.root)
                }
                historySection(snapshot)
            }
        }
    }

    @ViewBuilder
    private var stateMessage: some View {
        VStack(spacing: 0) {
            Spacer()
            if store.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text(store.errorText ?? "Not a git repository")
                    .font(.dm(12))
                    .foregroundStyle(Color.dmMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func headBlock(_ snapshot: GitSnapshot) -> some View {
        DMSection(
            headerSpacing: 6,
            contentSpacing: 8,
            padding: Self.sectionPadding,
            label: {
                Image(systemName: "arrow.triangle.branch")
                    .font(.dm(11))
                    .foregroundStyle(Color.dmMuted)
                Text(headName(snapshot))
                    .font(.dm(13, weight: .semibold))
                    .foregroundStyle(Color.dmRowText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            },
            trailing: {
                DMIconButton(systemImage: "arrow.clockwise", size: 11, hitSize: DMHitSize.compact) {
                    store.refresh()
                }
                .help("Refresh")
            }
        ) {
            HStack(spacing: 5) {
                if let upstream = snapshot.upstream {
                    Text(upstream)
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if snapshot.ahead > 0 {
                    DMPill(text: "↑\(snapshot.ahead)", color: Self.accent)
                }
                if snapshot.behind > 0 {
                    DMPill(text: "↓\(snapshot.behind)", color: Self.accent)
                }
                if snapshot.isDirty {
                    DMPill(text: changesLabel(snapshot.dirtyFiles), color: .yellow)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func worktreesSection(_ worktrees: [GitSnapshot.Worktree], root: String) -> some View {
        DMSection(
            contentSpacing: 6,
            padding: Self.sectionPadding,
            label: {
                DMSectionLabel(text: "WORKTREES")
                    .help(WorktreeDot.legend)
            },
            trailing: {
                if !store.mergedWorktrees.isEmpty {
                    DMButton(
                        WorktreeRemovalText.removeMergedTitle(store.mergedWorktrees.count),
                        variant: .ghost, size: .small
                    ) { store.requestMergedRemoval() }
                    .help("Remove the worktrees that are clean and fully merged into the main branch")
                }
                DMSectionValue(text: "\(worktrees.count)")
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                legend
                ForEach(worktrees, id: \.path) { worktree in
                    WorktreeRow(
                        worktree: worktree,
                        isCurrent: worktree.path == root,
                        block: WorktreeRemoval.block(worktree, currentRoot: root),
                        accent: Self.accent,
                        onRemove: { store.requestRemoval(worktree) })
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(WorktreeDot.current, "this session")
            legendItem(WorktreeDot.other, "other worktree")
        }
        .font(.dm(10))
        .foregroundStyle(Color.dmMuted)
        .padding(.bottom, 2)
        .help(WorktreeDot.legend)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(verbatim: text)
        }
    }

    private func historySection(_ snapshot: GitSnapshot) -> some View {
        DMSection(
            contentSpacing: 8,
            padding: Self.sectionPadding,
            label: { DMSectionLabel(text: "HISTORY") },
            trailing: { DMSectionValue(text: "\(snapshot.commits.count)") }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if snapshot.isDirty {
                    timelineRow(isFirst: true, isLast: snapshot.commits.isEmpty, hollow: true) {
                        workingTreeRow(snapshot.dirtyFiles)
                    }
                }
                ForEach(Array(snapshot.commits.enumerated()), id: \.offset) { index, commit in
                    timelineRow(
                        isFirst: !snapshot.isDirty && index == 0,
                        isLast: index == snapshot.commits.count - 1,
                        hollow: false
                    ) {
                        CommitRow(commit: commit, rowHeight: Self.rowHeight, copy: copy)
                    }
                }
            }
        }
    }

    private func timelineRow<Content: View>(
        isFirst: Bool,
        isLast: Bool,
        hollow: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            rail(isFirst: isFirst, isLast: isLast, hollow: hollow)
            content()
        }
        .frame(height: Self.rowHeight)
    }

    private func rail(isFirst: Bool, isLast: Bool, hollow: Bool) -> some View {
        let segment = (Self.rowHeight - Self.dotSize) / 2
        return VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : Color.dmDivider)
                .frame(width: 1, height: segment)
            dot(hollow: hollow)
            Rectangle()
                .fill(isLast ? Color.clear : Color.dmDivider)
                .frame(width: 1, height: segment)
        }
        .frame(width: 8)
    }

    @ViewBuilder
    private func dot(hollow: Bool) -> some View {
        if hollow {
            Circle()
                .strokeBorder(Self.accent, lineWidth: 1.5)
                .frame(width: Self.dotSize, height: Self.dotSize)
        } else {
            Circle()
                .fill(Self.accent)
                .frame(width: Self.dotSize, height: Self.dotSize)
        }
    }

    private func workingTreeRow(_ dirtyFiles: Int) -> some View {
        HStack(spacing: 6) {
            Text("Working tree")
                .font(.dm(12))
                .foregroundStyle(Color.dmMuted)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(changesLabel(dirtyFiles))
                .font(.dm(11))
                .foregroundStyle(.yellow)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.flashToast(label)
    }

    private func headName(_ snapshot: GitSnapshot) -> String {
        if let branch = snapshot.branch { return branch }
        if let detached = snapshot.detachedHead { return "detached at \(detached.prefix(7))" }
        return "no branch"
    }

    private func changesLabel(_ count: Int) -> String {
        count == 1 ? "1 change" : "\(count) changes"
    }
}

/// What the small dot in front of a worktree means.
enum WorktreeDot {
    static let current = Color.green
    static let other = Color.dmDivider
    static let currentHelp = "This session is in this worktree"
    static let otherHelp = "Another worktree of this repository"
    static let legend = "Green: \(currentHelp.lowercased()). Dim: \(otherHelp.lowercased())."
}

private struct WorktreeRow: View {
    let worktree: GitSnapshot.Worktree
    let isCurrent: Bool
    let block: WorktreeRemoval.Block?
    let accent: Color
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isCurrent ? WorktreeDot.current : WorktreeDot.other)
                .frame(width: 5, height: 5)
                .help(isCurrent ? WorktreeDot.currentHelp : WorktreeDot.otherHelp)
            Text(verbatim: WorktreeRemovalText.shortPath(worktree.path))
                .font(.dm(11, design: .monospaced))
                .foregroundStyle(isCurrent ? Color.dmRowText : Color.dmMuted)
                .lineLimit(1)
                .truncationMode(.head)
            if worktree.isLocked {
                Image(systemName: "lock.fill")
                    .font(.dm(8))
                    .foregroundStyle(Color.dmMuted)
            }
            Spacer(minLength: 4)
            if let branch = worktree.branch {
                DMPill(
                    text: branch,
                    color: accent,
                    font: .dm(9, weight: .semibold),
                    backgroundOpacity: 0.18
                )
            }
            removeButton
        }
        .padding(.leading, 0)
        .frame(minHeight: 24)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Remove Worktree…", action: onRemove)
                .disabled(block != nil)
            if let block {
                Text(verbatim: block.reason)
            }
        }
        .help(tooltip)
    }

    private var removeButton: some View {
        DMButton(icon: "trash", label: "Remove Worktree…", variant: .ghostDanger, size: .small, action: onRemove)
            .disabled(block != nil)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .help(block?.reason ?? "Remove Worktree…")
    }

    private var tooltip: String {
        var lines = [worktree.path, isCurrent ? WorktreeDot.currentHelp : WorktreeDot.otherHelp]
        if worktree.isLocked {
            lines.append("Locked" + (worktree.lockReason.map { ": \($0)" } ?? ""))
        }
        if let block, block != .currentWorktree {
            lines.append(block.reason)
        }
        return lines.joined(separator: "\n")
    }
}

private struct CommitRow: View {
    let commit: GitSnapshot.Commit
    let rowHeight: CGFloat
    let copy: (String, String) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(commit.subject)
                .font(.dm(12))
                .foregroundStyle(Color.dmRowText)
                .lineLimit(1)
                .truncationMode(.tail)
            if let badge = commit.primaryRef {
                DMPill(
                    text: Self.shortRef(badge),
                    color: Self.refColor(badge),
                    font: .dm(9, weight: .semibold),
                    backgroundOpacity: 0.18
                )
                .fixedSize()
            }
            Spacer(minLength: 4)
            Text(commit.sha)
                .font(.dm(11, design: .monospaced))
                .foregroundStyle(Color.dmMuted)
                .fixedSize()
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
        .background(DMRowBackground(selected: false, hovering: hovering))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { copy(commit.sha, "Copied SHA") }
        .contextMenu {
            Button("Copy SHA") { copy(commit.sha, "Copied SHA") }
            Button("Copy subject") { copy(commit.subject, "Copied subject") }
        }
        .help(tooltip)
    }

    private var tooltip: String {
        let head = "\(commit.subject)\n\(commit.author) · \(commit.age)"
        return commit.refs.isEmpty ? head : head + "\n" + commit.refs.joined(separator: ", ")
    }

    private static func shortRef(_ ref: String) -> String {
        ref.count <= 16 ? ref : String(ref.prefix(15)) + "…"
    }

    private static func refColor(_ ref: String) -> Color {
        if ref.hasPrefix("tag: ") { return Color(hex: 0xD9A23B) }
        if ref.contains("/") { return Color.dmMuted }
        return Color(hex: 0x5AA9E6)
    }
}
