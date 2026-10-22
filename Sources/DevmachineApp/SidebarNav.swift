import SwiftUI
import DevmachineCore

/// One of the sidebar's three places: Workspaces, Chats, Schedule.
struct SidebarNavItem: Identifiable, Equatable {
    let mode: AppMode
    let title: String
    let systemImage: String
    let shortcut: String

    var id: AppMode { mode }
}

/// The sidebar's first block in every mode: the three places as rows, always
/// on screen, the current one lit. The same ⌘1, ⌘2 and ⌘3 the menu bar has.
enum SidebarNav {
    static let items = [
        SidebarNavItem(
            mode: .code, title: "Workspaces", systemImage: "chevron.left.forwardslash.chevron.right", shortcut: "⌘1"),
        SidebarNavItem(mode: .chats, title: "Chats", systemImage: "bubble.left.and.bubble.right", shortcut: "⌘2"),
        SidebarNavItem(mode: .schedule, title: "Schedule", systemImage: "clock", shortcut: "⌘3"),
    ]

    @MainActor
    static func select(_ mode: AppMode, model: AppModel) {
        switch mode {
        case .code: model.appMode = .code
        case .chats: model.showChats()
        case .schedule: model.showPage(.scheduled)
        }
    }

    static func sectionTitle(_ mode: AppMode) -> String {
        switch mode {
        case .code: return "WORKSPACES"
        case .chats: return "CHATS"
        case .schedule: return "SCHEDULE"
        }
    }

    static func name(_ mode: AppMode) -> String {
        switch mode {
        case .code: return "Code"
        case .chats: return "Chats"
        case .schedule: return "Schedule"
        }
    }

    static func accessibilityValue(_ mode: AppMode, codeWaits: Bool) -> String {
        let current = "current: " + name(mode)
        return mode != .code && codeWaits ? current + ", a session in Code is waiting" : current
    }

    /// The dot by Workspaces: a session there waits for the person while
    /// they are somewhere else.
    static func showsCodeWaits(item: SidebarNavItem, mode: AppMode, codeWaits: Bool) -> Bool {
        item.mode == .code && mode != .code && codeWaits
    }
}

struct SidebarNavView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dmMetrics) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(SidebarNav.items) { item in
                row(item)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Places")
        .accessibilityValue(SidebarNav.accessibilityValue(model.appMode, codeWaits: model.codeNeedsAttention))
    }

    private func row(_ item: SidebarNavItem) -> some View {
        let selected = model.appMode == item.mode
        let waits = SidebarNav.showsCodeWaits(item: item, mode: model.appMode, codeWaits: model.codeNeedsAttention)
        return DMRow(
            systemImage: item.systemImage,
            iconColor: selected ? Color.dmRowText : Color.dmMuted,
            iconSize: DMIconSize.navGlyph,
            title: item.title,
            selected: selected,
            trailing: waits ? AnyView(
                Circle()
                    .fill(Color(hex: 0x3B82F6))
                    .frame(width: m.pt(6), height: m.pt(6))
                    .dmHelp("A session in Code is waiting for you")
            ) : nil,
            tap: { SidebarNav.select(item.mode, model: model) }
        )
        .dmHelp("\(item.title) (\(item.shortcut))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityHint("Shortcut \(item.shortcut)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { SidebarNav.select(item.mode, model: model) }
        .demoClickTarget("nav:\(item.mode.rawValue)")
    }
}

/// A section's label with its icons at the right: refresh and +, where the
/// wide "New …" button used to be.
struct SidebarSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        DMSection(
            padding: EdgeInsets(top: 4, leading: 10, bottom: 0, trailing: 10),
            label: {
                Text(verbatim: title)
                    .font(.dm(11, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Color.dmMuted)
            },
            trailing: trailing
        )
    }
}

/// What the three sidebars put at the top: the places, then the section's
/// label with its icons, under the window buttons.
struct SidebarTopBlock<Trailing: View>: View {
    let title: String
    var bottomGap = true
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.dmMetrics) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: m.pt(10)) {
            SidebarNavView()
            SidebarSectionHeader(title: title, trailing: trailing)
        }
        .padding(.bottom, bottomGap ? m.pt(SidebarHeaderSpacing.blockGap) : 0)
        .modifier(SidebarHeaderTop())
    }
}

/// The refresh icon every section header starts with.
struct SidebarRefreshButton: View {
    let action: () -> Void

    var body: some View {
        DMIconButton(systemImage: "arrow.clockwise", size: 11, hitSize: DMHitSize.header, action: action)
            .dmHelp("Refresh")
            .accessibilityLabel("Refresh")
    }
}

/// The + at a section header's right.
struct SidebarPlusButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        DMIconButton(systemImage: "plus", size: 11, hitSize: DMHitSize.header, action: action)
            .dmHelp(help)
            .accessibilityLabel(help)
    }
}
