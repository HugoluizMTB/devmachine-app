import XCTest
@testable import DevmachineCore

final class ChatSettingsTests: XCTestCase {
    func testTheDefaultShortcutIsControlOptionSpace() {
        let hotkey = ChatHotkey.defaultValue
        XCTAssertEqual(hotkey.display, "⌃⌥Space")
        XCTAssertEqual(hotkey.keyCaps, ["⌃", "⌥", "Space"])
        XCTAssertEqual(hotkey.keyCode, 49)
        XCTAssertEqual(hotkey.carbonModifiers, 0x1000 | 0x0800)
        XCTAssertTrue(hotkey.isValid)
    }

    func testRecordingAKeyPress() {
        XCTAssertEqual(
            ChatHotkey.recorded(keyCode: 40, modifiers: [.command, .shift], characters: "k"),
            ChatHotkey(keyCode: 40, modifiers: [.command, .shift], key: "K"))
        XCTAssertEqual(ChatHotkey.recorded(keyCode: 40, modifiers: [.command, .shift], characters: "k")?.display, "⇧⌘K")
        XCTAssertNil(ChatHotkey.recorded(keyCode: 40, modifiers: [.shift], characters: "k"))
        XCTAssertNil(ChatHotkey.recorded(keyCode: 40, modifiers: [], characters: "k"))
        XCTAssertEqual(ChatHotkey.recorded(keyCode: 49, modifiers: [.option], characters: " ")?.key, "Space")
    }

    func testOlderSettingsDecodeToTheDefaults() throws {
        let old = Data(#"{"opsRepoPath":"/Users/alice/.config/devmachine","hostAlias":"","publicIP":"","baseDomain":""}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertEqual(settings.chats, .default)
        XCTAssertEqual(settings.chats.folder, "~/chats")
        XCTAssertEqual(settings.chats.hotkey, .defaultValue)
        XCTAssertTrue(settings.chats.showsInMenuBar)
        XCTAssertEqual(settings.chats.harnesses, [.claude, .codex])
    }

    func testAClearedShortcutStaysCleared() throws {
        var settings = AppSettings.empty
        settings.chats.hotkey = nil
        settings.chats.defaultWorkspace = "acme"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertNil(decoded.chats.hotkey)
        XCTAssertEqual(decoded.chats.defaultWorkspace, "acme")
    }

    func testTheDefaultPlace() {
        var chats = ChatSettings()
        XCTAssertEqual(chats.defaultPlace(workspaces: ["main", "acme"]), .workspace("main"))
        XCTAssertEqual(chats.defaultPlace(workspaces: []), .local)
        chats.defaultWorkspace = "acme"
        XCTAssertEqual(chats.defaultPlace(workspaces: ["main", "acme"]), .workspace("acme"))
        chats.defaultWorkspace = "gone"
        XCTAssertEqual(chats.defaultPlace(workspaces: ["main"]), .workspace("main"))
        chats.defaultWorkspace = "local"
        XCTAssertEqual(chats.defaultPlace(workspaces: ["main"]), .local)
    }

    func testHarnessesNeverEmpty() {
        XCTAssertEqual(ChatSettings(enabledHarnesses: [.codex]).harnesses, [.codex])
        XCTAssertEqual(ChatSettings(enabledHarnesses: []).harnesses, [.claude])
        XCTAssertEqual(ChatSettings(enabledHarnesses: [.codex, .pi, .claude]).harnesses, [.claude, .codex])
    }
}
