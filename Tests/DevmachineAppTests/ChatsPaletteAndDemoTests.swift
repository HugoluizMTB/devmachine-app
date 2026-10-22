import XCTest
import SwiftUI
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class ChatsPaletteAndDemoTests: XCTestCase {
    private func chat(_ id: String, workspace: String, harness: HarnessID, minutesAgo: Double, kind: String = "chat")
        -> ChatRecord {
        let date = Date().addingTimeInterval(-minutesAgo * 60)
        return ChatRecord(
            id: id, title: "Chat \(id)", harness: harness, workspace: workspace, createdAt: date, updatedAt: date,
            kind: kind)
    }

    private func context() -> PaletteContext {
        var context = PaletteContext()
        context.chatWorkspaces = ["main", "acme-api"]
        context.chatConfig = ChatCLIConfig(defaultWorkspace: "main")
        context.chats = [
            chat("a", workspace: "acme-api", harness: .codex, minutesAgo: 5),
            chat("b", workspace: "main", harness: .claude, minutesAgo: 1),
        ]
        return context
    }

    func testNewChatEverywhereAndEveryChatByTitle() {
        let commands = CommandRegistry.commands(in: context())
        let newChat = commands.first { $0.id == "action.new-chat" }
        XCTAssertEqual(newChat?.subtitle, "main")
        XCTAssertEqual(newChat?.shortcut, "⌃⌥Space")
        let acme = commands.first { $0.id == "action.new-chat.acme-api" }
        XCTAssertEqual(acme?.title, "New chat in acme-api")
        XCTAssertEqual(acme?.subtitle, "Codex")
        XCTAssertEqual(acme?.action, .newChat(place: .workspace("acme-api"), harness: .codex))
        XCTAssertEqual(commands.first { $0.id == "action.new-chat.local" }?.title, "New chat on This Mac")
        XCTAssertNil(commands.first { $0.id == "action.new-chat.main" })
        XCTAssertEqual(commands.filter { $0.category == .chats }.map(\.id), ["chat.b", "chat.a"])
        XCTAssertEqual(commands.first { $0.id == "go.chats" }?.action, .showChats)
    }

    func testCodeAndChatsShowTheirShortcutsAndAreFoundByName() {
        let commands = CommandRegistry.commands(in: context())
        XCTAssertEqual(commands.first { $0.id == "go.code" }?.shortcut, "⌘1")
        XCTAssertEqual(commands.first { $0.id == "go.chats" }?.shortcut, "⌘2")
        func ids(_ query: String) -> [String] {
            PaletteRanker.sections(commands, query: query, mru: CommandMRU(ids: [])).flatMap(\.commands).map(\.id)
        }
        XCTAssertTrue(ids("code").contains("go.code"))
        XCTAssertTrue(ids("chats").contains("go.chats"))
        XCTAssertTrue(ids("switch").contains("go.code"))
        XCTAssertTrue(ids("switch").contains("go.chats"))
    }

    func testAccessibilityWords() {
        let chat = ChatRecord(
            id: "c", title: "Caddy reload", harness: .claude, workspace: "main", createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(ChatAccessibility.rowLabel(chat, answering: false), "Caddy reload, Claude on main")
        XCTAssertEqual(ChatAccessibility.rowLabel(chat, answering: true), "Caddy reload, Claude on main, answering")
        XCTAssertEqual(SidebarNav.accessibilityValue(.code, codeWaits: true), "current: Code")
        XCTAssertEqual(
            SidebarNav.accessibilityValue(.chats, codeWaits: true), "current: Chats, a session in Code is waiting")
        XCTAssertEqual(ChatMenuItem(id: "x", title: "main", detail: "(default)").accessibilityTitle, "main, (default)")
        XCTAssertEqual(ChatMenuShortcut.keys("⌘1")?.0, KeyEquivalent("1"))
        XCTAssertNil(ChatMenuShortcut.keys("⌃⌥Space"))
    }

    func testTheNavRowsOfferWorkspacesChatsAndScheduleWithTheirShortcuts() {
        let model = AppModel(services: fixtureServices())
        XCTAssertEqual(SidebarNav.items.map(\.title), ["Workspaces", "Chats", "Schedule"])
        XCTAssertEqual(SidebarNav.items.map(\.shortcut), ["⌘1", "⌘2", "⌘3"])
        XCTAssertEqual(SidebarNav.items.map(\.systemImage),
                       ["chevron.left.forwardslash.chevron.right", "bubble.left.and.bubble.right", "clock"])
        SidebarNav.select(.chats, model: model)
        XCTAssertEqual(model.appMode, .chats)
        XCTAssertTrue(SidebarNav.showsCodeWaits(item: SidebarNav.items[0], mode: .chats, codeWaits: true))
        XCTAssertFalse(SidebarNav.showsCodeWaits(item: SidebarNav.items[0], mode: .code, codeWaits: true))
        XCTAssertFalse(SidebarNav.showsCodeWaits(item: SidebarNav.items[1], mode: .code, codeWaits: true))
    }

    func testInChatsModeTheChatCommandsLead() {
        let commands = CommandRegistry.commands(in: context())
        let sections = PaletteRanker.sections(commands, query: "chat", mru: CommandMRU(ids: []), inChats: true)
        XCTAssertEqual(sections.prefix(2).map(\.category), [.action, .chats])
        XCTAssertEqual(sections.first?.commands.first?.id, "action.new-chat")
        let codeSections = PaletteRanker.sections(commands, query: "chat", mru: CommandMRU(ids: []), inChats: false)
        XCTAssertEqual(codeSections.first?.category, .goTo)
    }

    func testTheChatsWalkKeepsItsScreensAndShowsTheSidebarNav() {
        let walk = DemoSnapshots.walk(environment: ["DEVMACHINE_DEMO_WALK": "chats"])
        XCTAssertEqual(walk.map(\.fileName), [
            "01-chat-main.png", "02-chat-new.png", "03-chat-picker-harness.png", "04-chat-picker-workspace.png",
            "05-code-toggle.png", "06-quick-panel.png", "07-quick-panel-answer.png", "08-quick-panel-continue.png",
            "09-menubar-chats.png", "10-palette-chats.png", "11-context-ask-claude.png", "12-context-ask-codex.png",
            "13-chat-error-logged-out.png", "14-settings-chats.png", "15-sidebar-nav.png",
            "16-schedule-mode.png", "17-sidebar-collapsed.png", "18-chats-collapsed.png",
            "19-schedule-collapsed.png", "20-home-open.png", "21-home-collapsed.png",
            "22-chat-connecting.png",
        ])
    }

    func testTheDemoSeedsInventedChats() {
        let store = ChatStore(runner: FakeChatRunner())
        DemoChats.seed(store)
        XCTAssertEqual(store.visibleChats.count, 8)
        XCTAssertEqual(store.defaultPlace, .workspace("main"))
        XCTAssertTrue(store.isAnswering(DemoChats.selectedID))
        XCTAssertEqual(store.records.filter(\.isAsk).count, 2)
    }
}
