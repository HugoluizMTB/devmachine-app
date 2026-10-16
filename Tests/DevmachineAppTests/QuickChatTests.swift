import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class FakeHotkeyRegistrar: HotkeyRegistering {
    var registered: [ChatHotkey] = []
    var unregisterCount = 0
    var refuses = false
    var action: (@MainActor () -> Void)?

    func register(_ hotkey: ChatHotkey, action: @escaping @MainActor () -> Void) -> Bool {
        guard !refuses else { return false }
        registered.append(hotkey)
        self.action = action
        return true
    }

    func unregister() {
        unregisterCount += 1
        action = nil
    }
}

@MainActor
final class QuickChatHotkeyControllerTests: XCTestCase {
    func testRegistersTheDefaultAndFiresTheAction() {
        let registrar = FakeHotkeyRegistrar()
        var presses = 0
        let controller = QuickChatHotkeyController(registrar: registrar) { presses += 1 }
        controller.apply(.default)
        XCTAssertEqual(registrar.registered, [.defaultValue])
        registrar.action?()
        XCTAssertEqual(presses, 1)
    }

    func testTheSameSettingsDoNotRegisterTwice() {
        let registrar = FakeHotkeyRegistrar()
        let controller = QuickChatHotkeyController(registrar: registrar) {}
        controller.apply(.default)
        controller.apply(.default)
        XCTAssertEqual(registrar.registered.count, 1)
    }

    func testANewShortcutReplacesTheOld() {
        let registrar = FakeHotkeyRegistrar()
        let controller = QuickChatHotkeyController(registrar: registrar) {}
        controller.apply(.default)
        let other = ChatHotkey(keyCode: 40, modifiers: [.command, .shift], key: "K")
        controller.apply(ChatSettings(hotkey: other))
        XCTAssertEqual(registrar.registered, [.defaultValue, other])
        XCTAssertEqual(controller.registered, other)
    }

    func testAClearedOrInvalidShortcutRegistersNothing() {
        let registrar = FakeHotkeyRegistrar()
        let controller = QuickChatHotkeyController(registrar: registrar) {}
        controller.apply(.default)
        controller.apply(ChatSettings(hotkey: nil))
        XCTAssertNil(controller.registered)
        controller.apply(ChatSettings(hotkey: ChatHotkey(keyCode: 40, modifiers: [.shift], key: "K")))
        XCTAssertEqual(registrar.registered.count, 1)
    }

    func testARefusedShortcutIsTriedAgain() {
        let registrar = FakeHotkeyRegistrar()
        registrar.refuses = true
        let controller = QuickChatHotkeyController(registrar: registrar) {}
        controller.apply(.default)
        XCTAssertEqual(controller.failed, .defaultValue)
        registrar.refuses = false
        controller.apply(.default)
        XCTAssertEqual(controller.registered, .defaultValue)
    }
}

@MainActor
final class QuickChatModelTests: XCTestCase {
    func testSendStartsANewChatWithoutTouchingTheMainSelection() async {
        let runner = FakeChatRunner(streams: [.init(lines: [
            ChatFixtures.started("q1"), ChatFixtures.text("Pass -L"), ChatFixtures.done("q1"),
        ])])
        let store = ChatStore(runner: runner)
        store.workspaces = ["main"]
        store.select("other")
        let model = QuickChatModel(store: store)
        model.text = "how do I list tmux sessions on another socket?"
        model.send()
        XCTAssertEqual(model.question, "how do I list tmux sessions on another socket?")
        XCTAssertEqual(model.text, "")
        XCTAssertTrue(model.isContinuing)
        await waitForChat { model.chatID == "q1" && !model.isStreaming }
        XCTAssertEqual(store.selectedID, "other")
        XCTAssertEqual(model.conversation?.messages.last?.text, "Pass -L")
        XCTAssertEqual(
            runner.arguments.first { $0.prefix(2) == ["chat", "send"] }?.prefix(4), ["chat", "send", "--workspace", "main"])
    }

    func testAFollowUpContinuesTheSameChat() async {
        let runner = FakeChatRunner(streams: [
            .init(lines: [ChatFixtures.started("q1"), ChatFixtures.done("q1")]),
            .init(lines: [ChatFixtures.started("q1"), ChatFixtures.done("q1")]),
        ])
        let model = QuickChatModel(store: ChatStore(runner: runner))
        model.text = "one"
        model.send()
        await waitForChat { model.chatID == "q1" && !model.isStreaming }
        model.text = "two"
        model.send()
        await waitForChat { runner.arguments.count == 2 }
        XCTAssertEqual(runner.arguments[1], ["chat", "send", "--chat", "q1", "--", "two"])
    }

    func testContinuingARecentChat() async {
        let runner = FakeChatRunner(
            streams: [.init(lines: [ChatFixtures.started("c1"), ChatFixtures.done("c1")])],
            outputs: ["chat list": ChatCommandOutput(stdout: "[\(ChatFixtures.record("c1"))]", stderr: "", exitCode: 0)])
        let store = ChatStore(runner: runner)
        await store.refresh()
        let model = QuickChatModel(store: store)
        XCTAssertEqual(model.recentChats.map(\.id), ["c1"])
        model.showsChooser = true
        model.continueChat("c1")
        XCTAssertFalse(model.showsChooser)
        XCTAssertTrue(model.isContinuing)
        model.text = "more?"
        model.send()
        await waitForChat { !runner.arguments.filter { $0.first == "chat" && $0[1] == "send" }.isEmpty }
        XCTAssertTrue(runner.arguments.contains(["chat", "send", "--chat", "c1", "--", "more?"]))
    }

    func testOpenInAppHandsOverTheChat() async {
        let runner = FakeChatRunner(streams: [.init(lines: [ChatFixtures.started("q1"), ChatFixtures.done("q1")])])
        let model = QuickChatModel(store: ChatStore(runner: runner))
        var opened: [String?] = []
        model.openInApp = { opened.append($0) }
        model.openCurrentInApp()
        model.text = "hi"
        model.send()
        await waitForChat { model.chatID == "q1" }
        model.openCurrentInApp()
        XCTAssertEqual(opened, [nil, "q1"])
    }

    func testShowingAgainStartsFreshUnlessAnAnswerIsComing() async {
        let runner = FakeChatRunner(streams: [.init(lines: [ChatFixtures.started("q1")], waitsForCancel: true)])
        let store = ChatStore(runner: runner)
        let model = QuickChatModel(store: store)
        model.text = "hi"
        model.send()
        await waitForChat { model.chatID == "q1" }
        model.prepareForShow()
        XCTAssertEqual(model.question, "hi")
        model.stop()
        model.prepareForShow()
        XCTAssertNil(model.question)
        XCTAssertFalse(model.isContinuing)
    }

    func testEachOpenAsksTheFieldForTheKeyboardAgain() {
        let model = QuickChatModel(store: ChatStore(runner: FakeChatRunner(streams: [])))
        model.requestFocus()
        model.prepareForShow()
        model.requestFocus()
        XCTAssertEqual(model.focusRequests, 2)
    }

    func testEscapeGivesTheKeyboardBackOnlyToAnotherApp() {
        XCTAssertTrue(QuickChatPanelController.returnsFocus(toPID: 42, ownPID: 7))
        XCTAssertFalse(QuickChatPanelController.returnsFocus(toPID: 7, ownPID: 7))
        XCTAssertFalse(QuickChatPanelController.returnsFocus(toPID: nil, ownPID: 7))
    }
}
