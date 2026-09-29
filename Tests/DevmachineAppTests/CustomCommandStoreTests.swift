import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class CustomCommandStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "CustomCommandStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testStartsEmpty() {
        let store = CustomCommandStore(defaults: makeDefaults())
        XCTAssertTrue(store.commands.isEmpty)
    }

    func testAddedCommandsRoundTripThroughUserDefaults() {
        let defaults = makeDefaults()
        let store = CustomCommandStore(defaults: defaults)
        store.add(CustomCommand(name: "Claude (work)", command: "CLAUDE_CONFIG_DIR=~/.claude-work claude"))
        store.add(CustomCommand(name: "npm dev", command: "npm run dev", scope: .localOnly))

        let reloaded = CustomCommandStore(defaults: defaults)

        XCTAssertEqual(reloaded.commands.map(\.name), ["Claude (work)", "npm dev"])
        XCTAssertEqual(reloaded.commands.map(\.command), [
            "CLAUDE_CONFIG_DIR=~/.claude-work claude", "npm run dev"
        ])
        XCTAssertEqual(reloaded.commands.last?.scope, .localOnly)
    }

    func testAddingAnInvalidCommandIsRejected() {
        let store = CustomCommandStore(defaults: makeDefaults())

        let added = store.add(CustomCommand(name: "", command: "claude"))

        XCTAssertFalse(added)
        XCTAssertTrue(store.commands.isEmpty)
    }

    func testUpdateReplacesTheMatchingCommand() {
        let store = CustomCommandStore(defaults: makeDefaults())
        store.add(CustomCommand(name: "Claude", command: "claude"))
        var updated = store.commands[0]
        updated.name = "Claude (personal)"

        let success = store.update(updated)

        XCTAssertTrue(success)
        XCTAssertEqual(store.commands.first?.name, "Claude (personal)")
    }

    func testRemoveDropsTheCommand() {
        let store = CustomCommandStore(defaults: makeDefaults())
        store.add(CustomCommand(name: "Claude", command: "claude"))
        let id = store.commands[0].id

        store.remove(id)

        XCTAssertTrue(store.commands.isEmpty)
    }

    func testMoveReordersTheList() {
        let store = CustomCommandStore(defaults: makeDefaults())
        store.add(CustomCommand(name: "First", command: "a"))
        store.add(CustomCommand(name: "Second", command: "b"))
        store.add(CustomCommand(name: "Third", command: "c"))

        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(store.commands.map(\.name), ["Third", "First", "Second"])
    }

    func testTwoCommandsCanNeverShareAShortcutSlot() {
        let store = CustomCommandStore(defaults: makeDefaults())
        store.add(CustomCommand(name: "First", command: "a", shortcutSlot: 1))
        store.add(CustomCommand(name: "Second", command: "b"))
        var second = store.commands[1]
        second.shortcutSlot = 1

        store.update(second)

        XCTAssertNil(store.commands.first { $0.name == "First" }?.shortcutSlot)
        XCTAssertEqual(store.commands.first { $0.name == "Second" }?.shortcutSlot, 1)
    }

    func testAddingACommandStealsAShortcutSlotFromAnExistingOne() {
        let store = CustomCommandStore(defaults: makeDefaults())
        store.add(CustomCommand(name: "First", command: "a", shortcutSlot: 1))

        store.add(CustomCommand(name: "Second", command: "b", shortcutSlot: 1))

        XCTAssertNil(store.commands.first { $0.name == "First" }?.shortcutSlot)
        XCTAssertEqual(store.commands.first { $0.name == "Second" }?.shortcutSlot, 1)
    }

    func testWorkspaceScopeRoundTripsThroughUserDefaults() {
        let defaults = makeDefaults()
        let store = CustomCommandStore(defaults: defaults)
        store.add(CustomCommand(name: "Acme", command: "npm run dev", scope: .workspaces(["acme-devmachine"])))

        let reloaded = CustomCommandStore(defaults: defaults)

        XCTAssertEqual(reloaded.commands.first?.scope, .workspaces(["acme-devmachine"]))
    }

    func testApplicableDelegatesToScopeFiltering() {
        let store = CustomCommandStore(defaults: makeDefaults())
        store.add(CustomCommand(name: "All", command: "a", scope: .all))
        store.add(CustomCommand(name: "Local", command: "b", scope: .localOnly))
        store.add(CustomCommand(name: "Acme", command: "c", scope: .workspaces(["acme-devmachine"])))

        let local = store.applicable(toLocal: true, alias: Workspace.local.alias)
        let acme = store.applicable(toLocal: false, alias: "acme-devmachine")

        XCTAssertEqual(local.map(\.name), ["All", "Local"])
        XCTAssertEqual(acme.map(\.name), ["All", "Acme"])
    }
}
