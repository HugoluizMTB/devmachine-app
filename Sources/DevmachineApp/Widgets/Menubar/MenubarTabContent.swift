import SwiftUI
import AppKit
import DevmachineCore

/// One tab's widget, filling the popover. Today's two tabs draw their old
/// views; any other widget draws as it does on a board.
struct MenubarTabContent: View {
    let entry: StackEntry
    let title: String
    let panelWidth: CGFloat
    @ObservedObject var panel: StackBoardController
    @EnvironmentObject private var prStore: PRStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let resolution = panel.resolution(of: entry)
        switch resolution {
        case let .ready(resolved)?:
            if let source = resolved.source {
                GeometryReader { proxy in
                    SourceWidgetCard(
                        id: entry.id, title: title, source: source, controller: panel.sources, size: proxy.size,
                        onOpenSession: openSession)
                }
            } else {
                switch resolved.viewKind {
                case "app.pull-requests-panel":
                    PRsView().environmentObject(prStore)
                case "app.usage-panel":
                    MenuBarUsageColumns(panelWidth: panelWidth)
                default:
                    GeometryReader { proxy in AppWidgetView(resolved: resolved, size: proxy.size) }
                }
            }
        case let .some(placeholder):
            WidgetPlaceholderView(
                icon: "puzzlepiece.extension", title: WidgetResolutionCopy.title(placeholder),
                detail: WidgetResolutionCopy.detail(placeholder, release: panel.catalog.catalog?.packagesRelease ?? ""))
        case nil:
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func openSession(_ target: WidgetTarget, _ session: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
        model.openWidgetSession(target, session)
    }
}

/// The title's widgets that wait for approval, or were denied, each as its
/// card: Allow here and the widget starts drawing in the menu bar.
struct MenubarApprovalsView: View {
    let approvals: [MenubarApproval]
    let panelWidth: CGFloat
    @ObservedObject var sources: WidgetSourceController
    @Environment(\.dmMetrics) private var m

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: m.space.md) {
                ForEach(approvals) { approval in
                    SourceWidgetCard(
                        id: approval.id, title: approval.title, source: approval.source, controller: sources,
                        size: CGSize(
                            width: panelWidth - 2 * m.space.lg,
                            height: m.pt(CGFloat(StackLayout.approvalRows * WidgetContract.current.stackRow))),
                        onOpenSession: { _, _ in })
                        .frame(height: m.pt(CGFloat(StackLayout.approvalRows * WidgetContract.current.stackRow)))
                }
            }
            .padding(m.space.lg)
        }
    }
}
