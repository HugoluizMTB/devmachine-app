import SwiftUI
import AppKit
import HarnessUsageKit
import DevmachineCore

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

enum MenuBarSizing {
    static func width(
        for _: MenuBarTab, usageColumns _: Int, available: CGFloat
    ) -> CGFloat {
        min(776, max(320, available - 32))
    }

    static func height(for _: MenuBarTab) -> CGFloat {
        640
    }

    static func columnWidth(panelWidth: CGFloat, usageColumns: Int) -> CGFloat {
        let columns = max(1, usageColumns)
        if columns == 1 { return panelWidth }
        let dividers = CGFloat(max(0, columns - 1))
        return min(UsagePanelMetrics.columnWidth, (panelWidth - dividers) / CGFloat(columns))
    }
}

struct MenuBarPanel: View {
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject var prStore: PRStore
    @EnvironmentObject var usageStore: HarnessUsageStore
    @EnvironmentObject var model: AppModel
    @Environment(\.harnessSettingsFacade) private var harnessSettingsFacade
    @Environment(\.openWindow) private var openWindow
    @State private var tab: MenuBarTab
    private let height: CGFloat?

    init(initialTab: MenuBarTab = .pullRequests, height: CGFloat? = nil) {
        _tab = State(initialValue: initialTab)
        self.height = height
    }

    private var panelWidth: CGFloat {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return MenuBarSizing.width(
            for: tab,
            usageColumns: usageStore.states.count,
            available: screen?.visibleFrame.width ?? 1_200)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            body(for: tab)
            footer
                .background(Color.dmBand)
        }
        .frame(width: panelWidth)
        .frame(height: height ?? MenuBarSizing.height(for: tab))
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
            .padding(m.space.md)
        } else if let onlyTab = MenuBarTab.allCases.first {
            Text(onlyTab.title)
                .font(.dm(13, weight: .semibold))
                .foregroundStyle(Color.dmRowText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(m.pt(10))
        }
    }

    @ViewBuilder
    private func body(for tab: MenuBarTab) -> some View {
        switch tab {
        case .pullRequests:
            PRsView().environmentObject(prStore)
        case .usage:
            if usageStore.states.isEmpty {
                Text(verbatim: "No local usage harnesses available")
                    .foregroundStyle(Color.dmMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(usageStore.states.enumerated()), id: \.element.id) { index, state in
                        if let descriptor = harnessSettingsFacade.descriptor(
                            for: HarnessID(rawValue: state.harnessID)) {
                            HarnessUsagePanel(
                                store: usageStore,
                                harnessID: state.harnessID,
                                title: "\(descriptor.shortTitle) Usage",
                                systemImage: descriptor.systemImage,
                                accent: descriptor.color)
                            .harnessUsageErrorView { error, retry in
                                DMErrorStateView(state: DMErrorState(error), retry: retry)
                                    .padding(.vertical, m.space.lg)
                            }
                            .frame(width: MenuBarSizing.columnWidth(
                                panelWidth: panelWidth, usageColumns: usageStore.states.count))
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: m.pt(14)) {
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
            DMButton(icon: "eyedropper", label: "Pick a color", size: .small) {
                ScreenColorPicker.pick(onCopy: model.announceCopiedColor)
            }
            Spacer()
            footerButton("power", help: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(m.pt(10))
        .background(Color.dmSidebarBg)
    }

    private func footerButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        DMButton(icon: systemImage, label: help, size: .small) {
            NSApp.activate(ignoringOtherApps: true)
            action()
        }
    }
}
