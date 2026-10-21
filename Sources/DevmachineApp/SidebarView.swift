import SwiftUI
import DevmachineCore

struct SidebarView: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject var model: AppModel
    @ObservedObject private var machines = MachinesStore.shared
    @ObservedObject private var stacks = StackBoardController.sidebar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            StackBoardView(controller: stacks, style: .sidebar, isVisible: !model.sidebarCollapsed)
            footerRow
        }
        .background(Color.dmSidebarBg)
        .task { await machines.load() }
        .onChange(of: selectedWorkspace, initial: true) { _, name in
            stacks.setContext(SidebarContext.values(selectedWorkspace: name))
        }
    }

    private var selectedWorkspace: String? {
        guard case let .session(alias, _) = model.selection else { return nil }
        return model.visibleWorkspaces.first { $0.alias == alias }?.name
    }

    private var footerRow: some View {
        HStack(spacing: 0) {
            footerButton("chart.bar") { model.showPage(.stats) }
                .help("Stats")
            if model.hasCaddyMachine {
                footerButton("globe") { model.showPage(.subdomains) }
                    .help("Publish")
                    .demoClickTarget("footer:published-apps")
            }
            footerButton("gearshape") { model.showPage(.setup) }
                .help("Settings (⌘,)")
        }
        .padding(.horizontal, m.space.lg)
        .padding(.vertical, m.space.md)
    }

    private func footerButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        DMIconButton(
            systemImage: systemImage, size: DMMetrics.baseFontSize, hitSize: DMHitSize.footer,
            fillsWidth: true,
            action: action)
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            SidebarModeHeader(refresh: { model.refreshAllNow() })
            SidebarNewRow(title: "New session", systemImage: "plus.rectangle", shortcut: "⌘N") {
                model.requestQuickSession()
            }
            .help("A new session, like the one in front of you, or pick where")
        }
        .padding(.bottom, m.pt(SidebarHeaderSpacing.blockGap))
        .modifier(SidebarHeaderTop())
    }
}

/// The workspace list before it is read: group headers and session rows in
/// the sidebar's own sizes, stretching with its width.
struct SidebarSkeleton: View {
    @Environment(\.dmMetrics) private var m
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(0..<3, id: \.self) { group in
                DMSkeleton {
                    DMSection(
                        padding: EdgeInsets(top: group > 0 ? 16 : 4, leading: 10, bottom: 4, trailing: 10),
                        label: { DMSkeletonText(size: 11, weight: .semibold, width: .fixed([54, 40, 66][group])) },
                        trailing: { Color.clear.frame(width: m.hit.header.width, height: m.hit.header.height) }
                    )
                }
                Self.sessionRows(count: [3, 2, 2][group], seed: group)
            }
        }
        .padding(.vertical, m.space.sm)
    }

    static func sessionRows(count: Int, seed: Int) -> some View {
        let m = DMMetrics.current
        return DMSkeleton {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(0..<count, id: \.self) { index in
                    HStack(spacing: m.space.md) {
                        DMSkeletonText(size: 13, width: .varied(seed * 2 + index, shares: [0.5, 0.34, 0.62, 0.42, 0.56]))
                        DMSkeletonText(size: 11, width: .fixed(7))
                    }
                    .padding(.horizontal, m.row.horizontal)
                    .padding(.vertical, m.row.vertical)
                    .padding(.horizontal, m.row.outer)
                }
            }
        }
    }
}
