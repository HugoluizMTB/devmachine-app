import SwiftUI
import AppKit
import ClaudeUsageKit

enum MenuBarTab: String, CaseIterable, Identifiable {
    case pullRequests
    case usage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pullRequests: return "Pull Requests"
        case .usage: return "Usage"
        }
    }

    var systemImage: String {
        switch self {
        case .pullRequests: return "arrow.triangle.pull"
        case .usage: return "gauge.with.dots.needle.bottom.50percent"
        }
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject var prStore: PRStore
    @EnvironmentObject var usageStore: ClaudeUsageStore
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var tab: MenuBarTab = .pullRequests

    private var panelWidth: CGFloat {
        switch tab {
        case .pullRequests: return 420
        case .usage: return 380
        }
    }

    private var panelHeight: CGFloat? {
        switch tab {
        case .pullRequests: return nil
        case .usage: return 640
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Rectangle().fill(Color.dmDivider).frame(height: 1)
            body(for: tab)
            Rectangle().fill(Color.dmDivider).frame(height: 1)
            footer
        }
        .frame(width: panelWidth)
        .frame(height: panelHeight)
        .background(Color.dmContentBg)
        .animation(.easeInOut(duration: 0.15), value: tab)
    }

    @ViewBuilder
    private var tabBar: some View {
        if MenuBarTab.allCases.count > 1 {
            DMTabStrip(
                tabs: MenuBarTab.allCases,
                selection: $tab,
                title: { $0.title },
                systemImage: { $0.systemImage }
            )
            .padding(8)
        } else if let onlyTab = MenuBarTab.allCases.first {
            Text(onlyTab.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
    }

    @ViewBuilder
    private func body(for tab: MenuBarTab) -> some View {
        switch tab {
        case .pullRequests:
            PRsView().environmentObject(prStore)
        case .usage:
            ClaudeUsagePanel(store: usageStore)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            footerButton("macwindow", help: "Open") {
                openWindow(id: "main")
            }
            footerButton("chart.bar", help: "Stats") {
                openWindow(id: "main")
                model.showPage(.stats)
            }
            footerButton("globe", help: "Subdomains") {
                openWindow(id: "main")
                model.showPage(.subdomains)
            }
            Spacer()
            footerButton("power", help: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(10)
        .background(Color.dmSidebarBg)
    }

    private func footerButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(Color.dmMuted)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
