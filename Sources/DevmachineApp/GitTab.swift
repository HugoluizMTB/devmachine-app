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
            showBottomDivider: true,
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
                Button {
                    store.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.dm(11))
                        .foregroundStyle(Color.dmMuted)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
            showBottomDivider: true,
            label: { DMSectionLabel(text: "WORKTREES") },
            trailing: { DMSectionValue(text: "\(worktrees.count)") }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(worktrees, id: \.path) { worktree in
                    worktreeRow(worktree, isCurrent: worktree.path == root)
                }
            }
        }
    }

    private func worktreeRow(_ worktree: GitSnapshot.Worktree, isCurrent: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isCurrent ? Color.green : Color.dmDivider)
                .frame(width: 5, height: 5)
            Text(shortPath(worktree.path))
                .font(.dm(11, design: .monospaced))
                .foregroundStyle(isCurrent ? Color.dmRowText : Color.dmMuted)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
            if let branch = worktree.branch {
                DMPill(
                    text: branch,
                    color: Self.accent,
                    font: .dm(9, weight: .semibold),
                    backgroundOpacity: 0.18
                )
            }
        }
        .padding(.vertical, 4)
        .help(worktree.path)
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

    private func shortPath(_ path: String) -> String {
        path.split(separator: "/").suffix(2).joined(separator: "/")
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
