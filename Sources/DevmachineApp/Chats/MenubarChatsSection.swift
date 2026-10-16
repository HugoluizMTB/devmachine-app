import AppKit
import SwiftUI
import DevmachineCore

/// "New chat" and the three latest chats, above the menu bar panel's tabs.
struct MenubarChatsSection: View {
    @ObservedObject var store: ChatStore
    var newChat: () -> Void = { QuickChatPanelController.shared.show() }
    var open: (String) -> Void = { id in
        NSApp.activate(ignoringOtherApps: true)
        MainWindowOpener.open()
        AppModel.shared?.showChats(select: id)
    }
    @Environment(\.dmMetrics) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: m.pt(2)) {
            HStack(spacing: m.pt(10)) {
                Image(systemName: "square.and.pencil").font(.dm(12, weight: .medium))
                    .foregroundStyle(Color.accentColor).frame(width: m.pt(18))
                Text(verbatim: "New chat").font(.dm(13, weight: .medium)).foregroundStyle(.white)
                Spacer()
                if let hotkey = store.settings.hotkey {
                    HStack(spacing: m.pt(3)) {
                        ForEach(Array(hotkey.keyCaps.enumerated()), id: \.offset) { _, key in DMKeyCap(key: key) }
                    }
                }
            }
            .padding(.horizontal, m.pt(10))
            .padding(.vertical, m.pt(7))
            .background(DMRowBackground(selected: true, cornerRadius: DMRadius.control, selectedColor: .dmActive))
            .contentShape(Rectangle())
            .onTapGesture { newChat() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("New chat")
            .accessibilityHint(store.settings.hotkey.map { "Shortcut \($0.display)" } ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { newChat() }
            let recent = Array(store.visibleChats.prefix(3))
            if !recent.isEmpty {
                DMSectionLabel(text: "RECENT CHATS")
                    .padding(.horizontal, m.pt(10))
                    .padding(.top, m.pt(8))
                    .padding(.bottom, m.pt(2))
                ForEach(recent) { chat in
                    HStack(spacing: m.pt(10)) {
                        ChatHarnessGlyph(harness: chat.harness, size: 13).frame(width: m.pt(18))
                        Text(verbatim: chat.title).font(.dm(12.5)).foregroundStyle(Color.dmRowText).lineLimit(1)
                        Text(verbatim: ChatPlaceLabel.title(chat.place)).font(.dm(11)).foregroundStyle(Color.dmMuted)
                            .lineLimit(1)
                        Spacer()
                        if store.isAnswering(chat.id) {
                            ChatSpinner(size: 10)
                        } else {
                            Text(verbatim: ChatGrouping.age(of: chat.updatedAt, now: Date()))
                                .font(.dm(11)).foregroundStyle(Color.dmMuted)
                        }
                    }
                    .padding(.horizontal, m.pt(10))
                    .padding(.vertical, m.pt(6))
                    .background(DMRowBackground(selected: false))
                    .contentShape(Rectangle())
                    .onTapGesture { open(chat.id) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ChatAccessibility.rowLabel(chat, answering: store.isAnswering(chat.id)))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { open(chat.id) }
                }
            }
        }
        .padding(m.space.md)
        .background(Color.dmSidebarBg)
        .task { await store.refresh() }
    }
}
