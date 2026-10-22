import SwiftUI
import AppKit
import DevmachineCore

/// The strip over the terminal: one tab per session opened this run, with
/// its harness's icon, and one per file looked at from a session, then +.
/// Closing a tab takes it off the strip and nothing else; the session goes
/// on running and stays in the sidebar.
struct CenterTabStrip: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dmMetrics) private var m
    @Environment(\.collapsedSidebarButtonFrame) private var toggleFrame
    @Environment(\.titleLine) private var titleLine

    /// Points at 100%.
    static let height: CGFloat = 34
    static let gapAfterToggle: CGFloat = 8

    static func shows(enabled: Bool, mode: AppMode) -> Bool {
        enabled && mode == .code
    }

    /// With the sidebar closed the window buttons and the sidebar toggle sit
    /// over the strip's corner, so its tabs start after the toggle and its
    /// row centres on the buttons' line.
    static func leadingInset(toggle: CGRect?, gap: CGFloat) -> CGFloat {
        guard let toggle else { return 0 }
        return toggle.maxX + gap
    }

    static func topInset(toggle: CGRect?, titleLine: CGFloat, height: CGFloat) -> CGFloat {
        guard toggle != nil else { return 0 }
        return max(0, titleLine - height / 2)
    }

    static func fileIcon(path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "md", "markdown": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic": return "photo"
        default: return "doc.text"
        }
    }

    var body: some View {
        HStack(spacing: m.space.xxs) {
            ForEach(model.openTabs.items, id: \.self) { tab in
                chip(tab)
            }
            DMIconButton(systemImage: "plus", size: 11, hitSize: DMHitSize.compact) { model.requestQuickSession() }
                .dmHelp("New session (⌘N)")
                .accessibilityLabel("New session")
                .padding(.leading, m.space.xs)
            Spacer(minLength: 0)
        }
        .frame(height: m.pt(Self.height))
        .padding(.leading, Self.leadingInset(toggle: toggleFrame, gap: m.pt(Self.gapAfterToggle)))
        .padding(.top, Self.topInset(toggle: toggleFrame, titleLine: titleLine, height: m.pt(Self.height)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dmSidebarBg)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open tabs")
    }

    @ViewBuilder
    private func chip(_ tab: CenterTab) -> some View {
        let selected = model.isSelected(tab: tab)
        switch tab {
        case let .session(item):
            let icon = harnessIcon(for: item)
            DocumentTabChip(
                systemImage: "apple.terminal",
                title: model.title(for: tab),
                selected: selected,
                closeHelp: "Close the tab (the session keeps running)",
                select: { model.select(tab: tab) },
                close: { model.close(tab: tab) },
                image: icon?.image,
                imageIsTemplate: icon?.isTemplate ?? false,
                iconColor: Color.dmRowText.opacity(0.8))
                .demoClickTarget("tab:session:\(model.title(for: tab))")
        case let .file(_, path):
            DocumentTabChip(
                systemImage: Self.fileIcon(path: path),
                title: model.title(for: tab),
                selected: selected,
                closeHelp: "Close the file tab",
                select: { model.select(tab: tab) },
                close: { model.close(tab: tab) })
                .dmHelp(path)
        }
    }

    private func harnessIcon(for item: SidebarItem) -> HarnessIcon? {
        guard let id = model.harnessBadges(for: item).first?.id else { return nil }
        return HarnessIconLibrary.bundled.icon(for: id, style: settingsStore.settings?.harnessIconStyle ?? .color)
    }
}
