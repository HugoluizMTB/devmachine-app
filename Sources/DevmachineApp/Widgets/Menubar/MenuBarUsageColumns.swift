import SwiftUI
import DevmachineCore
import HarnessUsageKit

/// Today's Usage tab, moved out of `MenuBarPanel` as it was.
struct MenuBarUsageColumns: View {
    let panelWidth: CGFloat
    @Environment(\.dmMetrics) private var m
    @EnvironmentObject var usageStore: HarnessUsageStore
    @Environment(\.harnessSettingsFacade) private var harnessSettingsFacade

    var body: some View {
        if usageStore.states.isEmpty {
            Text(verbatim: "No coding agent with local usage available")
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
