import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class ChatsModeTests: XCTestCase {
    func testTestsStartInCode() {
        XCTAssertEqual(AppModel(services: fixtureServices()).appMode, .code)
    }

    func testShowChatsSelectsTheChatAndOpensTheSidebar() {
        let model = AppModel(services: fixtureServices())
        let store = ChatStore(runner: FakeChatRunner())
        let collapsed = model.sidebarCollapsed
        defer { model.sidebarCollapsed = collapsed }
        model.sidebarCollapsed = true
        model.showChats(select: "c1", store: store)
        XCTAssertEqual(model.appMode, .chats)
        XCTAssertEqual(store.selectedID, "c1")
        XCTAssertFalse(model.sidebarCollapsed)
    }

    func testPicksASessionOrAPageGoesBackToCode() {
        let model = AppModel(services: fixtureServices())
        model.appMode = .chats
        model.selection = .localSession(name: "beta", path: "/Users/alice/dev/beta")
        XCTAssertEqual(model.appMode, .code)
        model.appMode = .chats
        model.showPage(.stats)
        XCTAssertEqual(model.appMode, .code)
        model.appMode = .chats
        model.openSettings(.chats)
        XCTAssertEqual(model.appMode, .code)
        XCTAssertEqual(model.activePage, .setup)
        model.appMode = .chats
        model.goHome()
        XCTAssertEqual(model.appMode, .code)
    }

    func testNewChatClearsTheSelectionAndKeepsThePlace() {
        let model = AppModel(services: fixtureServices())
        let store = ChatStore(runner: FakeChatRunner())
        store.select("c1")
        model.showNewChat(place: .workspace("acme"), store: store)
        XCTAssertNil(store.selectedID)
        XCTAssertEqual(store.draftPlace, .workspace("acme"))
        XCTAssertEqual(model.appMode, .chats)
    }

    func testTheCodeDotFollowsSessionsWaitingForThePerson() {
        let model = AppModel(services: fixtureServices())
        model.sessionsByAlias["acme-devmachine"] = [TmuxSession(name: "dash", windows: 1, harnesses: [.claude])]
        XCTAssertFalse(model.codeNeedsAttention)
        model.sessionsByAlias["acme-devmachine"] = [TmuxSession(
            name: "dash", windows: 1, harnesses: [.claude], indicators: SessionIndicators(attention: true))]
        XCTAssertTrue(model.codeNeedsAttention)
        var settings = AppSettings.empty
        settings.showsAttention = false
        model.settings = settings
        XCTAssertFalse(model.codeNeedsAttention)
    }
}

@MainActor
final class SidebarModeHeaderTests: XCTestCase {
    func testTheTitleNamesTheMode() {
        XCTAssertEqual(SidebarModeHeader.title(.code), "CODE WORKSPACES")
        XCTAssertEqual(SidebarModeHeader.title(.chats), "CHAT WORKSPACES")
    }

    func testChangingModeClosesTheMenu() {
        let model = AppModel(services: fixtureServices())
        model.showsModeMenu = true
        model.appMode = .chats
        XCTAssertFalse(model.showsModeMenu)
    }
}
