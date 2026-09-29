import XCTest
@testable import DevmachineCore

final class CustomCommandTests: XCTestCase {
    func testValidityRequiresNameAndCommand() {
        XCTAssertTrue(CustomCommand(name: "Claude", command: "claude").isValid)
        XCTAssertFalse(CustomCommand(name: "  ", command: "claude").isValid)
        XCTAssertFalse(CustomCommand(name: "Claude", command: "  ").isValid)
        XCTAssertFalse(CustomCommand(name: "", command: "").isValid)
    }

    func testAllScopeAppliesEverywhere() {
        let command = CustomCommand(name: "Claude", command: "claude", scope: .all)
        XCTAssertTrue(command.applies(toLocal: true, alias: Workspace.local.alias))
        XCTAssertTrue(command.applies(toLocal: false, alias: "acme-devmachine"))
    }

    func testLocalOnlyScopeAppliesOnlyToTheLocalMachine() {
        let command = CustomCommand(name: "Claude", command: "claude", scope: .localOnly)
        XCTAssertTrue(command.applies(toLocal: true, alias: Workspace.local.alias))
        XCTAssertFalse(command.applies(toLocal: false, alias: "acme-devmachine"))
    }

    func testWorkspaceScopeAppliesOnlyToTheChosenWorkspaces() {
        let command = CustomCommand(
            name: "Claude", command: "claude", scope: .workspaces(["acme-devmachine"]))
        XCTAssertTrue(command.applies(toLocal: false, alias: "acme-devmachine"))
        XCTAssertFalse(command.applies(toLocal: false, alias: "beta-devmachine"))
        XCTAssertFalse(command.applies(toLocal: true, alias: Workspace.local.alias))
    }

    func testApplicableFiltersACommandListByScope() {
        let commands = [
            CustomCommand(name: "All", command: "a", scope: .all),
            CustomCommand(name: "Local", command: "b", scope: .localOnly),
            CustomCommand(name: "Acme", command: "c", scope: .workspaces(["acme-devmachine"]))
        ]

        let local = CustomCommand.applicable(in: commands, toLocal: true, alias: Workspace.local.alias)
        XCTAssertEqual(local.map(\.name), ["All", "Local"])

        let acme = CustomCommand.applicable(in: commands, toLocal: false, alias: "acme-devmachine")
        XCTAssertEqual(acme.map(\.name), ["All", "Acme"])

        let beta = CustomCommand.applicable(in: commands, toLocal: false, alias: "beta-devmachine")
        XCTAssertEqual(beta.map(\.name), ["All"])
    }

    func testShortcutEntriesAreOrderedBySlotRegardlessOfListOrder() {
        let commands = [
            CustomCommand(name: "Third", command: "c", shortcutSlot: 3),
            CustomCommand(name: "NoShortcut", command: "d"),
            CustomCommand(name: "First", command: "a", shortcutSlot: 1),
            CustomCommand(name: "Second", command: "b", shortcutSlot: 2)
        ]

        let entries = CustomCommand.shortcutEntries(in: commands)

        XCTAssertEqual(entries.map(\.name), ["First", "Second", "Third"])
    }
}
