import SwiftUI
import DevmachineCore

/// The sidebar's first row in both modes: "CODE WORKSPACES ▾" or "CHAT
/// WORKSPACES ▾", which opens the Code / Chats menu, then refresh and
/// close at the right. In Chats, a dot by the title says a session in Code
/// waits for the person.
struct SidebarModeHeader: View {
    let refresh: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.dmMetrics) private var m

    static func title(_ mode: AppMode) -> String {
        mode == .code ? "CODE WORKSPACES" : "CHAT WORKSPACES"
    }

    var body: some View {
        HStack(spacing: m.space.sm) {
            Button { model.showsModeMenu.toggle() } label: {
                HStack(spacing: m.pt(5)) {
                    Text(verbatim: Self.title(model.appMode))
                        .font(.dm(11, weight: .semibold))
                        .kerning(0.8)
                    Image(systemName: "chevron.down")
                        .font(.dm(8, weight: .bold))
                    if model.appMode == .chats, model.codeNeedsAttention {
                        Circle()
                            .fill(Color(hex: 0x3B82F6))
                            .frame(width: m.pt(6), height: m.pt(6))
                            .help("A session in Code is waiting for you")
                    }
                }
                .foregroundStyle(model.showsModeMenu ? Color.dmRowText : Color.dmMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .anchorPreference(key: SidebarModeMenuAnchor.self, value: .bounds) { $0 }
            .help("Code or Chats (⌘1, ⌘2)")
            .demoClickTarget("sidebar:mode")
            Spacer(minLength: m.space.sm)
            DMIconButton(systemImage: "arrow.clockwise", size: DMMetrics.baseFontSize, action: refresh)
                .help("Refresh")
            DMIconButton(systemImage: "sidebar.left", size: DMMetrics.baseFontSize) {
                withAnimation(.easeInOut(duration: 0.18)) { model.sidebarCollapsed = true }
            }
            .help("Close sidebar (⌘B)")
            .demoClickTarget("footer:close-sidebar")
        }
        .padding(.horizontal, m.pt(12))
    }
}

/// "New session" in Code and "New chat" in Chats, under the header.
struct SidebarNewRow: View {
    let title: String
    let systemImage: String
    var shortcut: String?
    var selected = false
    let action: () -> Void
    @Environment(\.dmMetrics) private var m

    var body: some View {
        HStack(spacing: m.pt(8)) {
            Image(systemName: systemImage).font(.dm(12, weight: .medium))
            Text(verbatim: title).font(.dm(13, weight: .medium))
            Spacer()
            if let shortcut {
                Text(verbatim: shortcut).font(.dm(11)).foregroundStyle(Color.dmMuted)
            }
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.horizontal, m.pt(10))
        .frame(height: m.pt(32))
        .dmSurface(selected ? Color.white.opacity(0.1) : Color.white.opacity(0.07), radius: DMRadius.control)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .padding(.horizontal, m.pt(10))
        .accessibilityAddTraits(.isButton)
    }
}

struct SidebarModeMenuAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// The menu under the header title, drawn in the window so a click
/// anywhere else closes it and a demo frame can show it open.
struct SidebarModeMenuOverlay: ViewModifier {
    @ObservedObject var model: AppModel
    @Environment(\.dmMetrics) private var m

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(SidebarModeMenuAnchor.self) { anchor in
            if model.showsModeMenu, let anchor {
                GeometryReader { proxy in
                    let rect = proxy[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.001)
                            .onTapGesture { model.showsModeMenu = false }
                        ChatMenuCard(items: items, width: 220, highlighted: highlighted)
                            .offset(x: rect.minX - m.pt(6), y: rect.maxY + m.pt(6))
                    }
                }
            }
        }
    }

    private var highlighted: String { model.appMode == .code ? "mode-code" : "mode-chats" }

    private var items: [ChatMenuItem] {
        var items = [
            ChatMenuItem(
                id: "mode-code", title: "Code", systemImage: "chevron.left.forwardslash.chevron.right",
                checked: model.appMode == .code, shortcut: "⌘1",
                action: { model.showsModeMenu = false; model.appMode = .code }),
            ChatMenuItem(
                id: "mode-chats", title: "Chats", systemImage: "bubble.left.and.bubble.right",
                checked: model.appMode == .chats, shortcut: "⌘2",
                action: { model.showsModeMenu = false; model.showChats() }),
        ]
        if model.appMode == .code {
            items += [
                .separator("mode-sep"),
                ChatMenuItem(
                    id: "new-workspace", title: "New workspace…", systemImage: "person.crop.square.badge.plus",
                    action: { model.showsModeMenu = false; model.requestNewWorkspace() }),
            ]
        }
        return items
    }
}
