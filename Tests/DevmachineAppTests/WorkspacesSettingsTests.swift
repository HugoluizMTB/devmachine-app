import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class SilentRunner: CommandRunner, @unchecked Sendable {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
}

@MainActor
final class WorkspacesSettingsTests: XCTestCase {
    private func settingsStore(hidden: [String] = []) -> SettingsStore {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)")!)
        var settings = AppSettings.empty
        settings.opsRepoPath = "/Users/alice/.config/devmachine"
        settings.hiddenWorkspaces = hidden
        store.settings = settings
        return store
    }

    func testPackagesForThisWorkspaceOpensSettingsPackagesOnIt() {
        let model = AppModel(store: SessionStore(runner: SilentRunner()))
        model.openPackages(workspace: "acme")
        XCTAssertEqual(model.activePage, .setup)
        XCTAssertEqual(model.requestedSettingsSection, .packages)
        XCTAssertEqual(model.requestedPackagesWorkspace, "acme")
        XCTAssertNil(model.requestedPackagesMachine)
    }

    func testThePackagesPageOpensWithTheWorkspaceDropdownSet() {
        let page = PackagesPageState.requested(machine: nil, workspace: "acme")
        XCTAssertEqual(page?.workspace, "acme")
        XCTAssertNil(page?.machine)
        XCTAssertEqual(page?.scope, "workspace")
        XCTAssertEqual(PackagesPageState.requested(machine: "main", workspace: nil)?.machine, "main")
        XCTAssertNil(PackagesPageState.requested(machine: nil, workspace: nil))
    }

    func testASwitchSavesTheHiddenListAtOnceAndNothingElse() {
        let store = settingsStore()
        let model = AppModel(store: SessionStore(runner: SilentRunner()))
        model.setHiddenWorkspaces(["acme-devmachine"], in: store)
        XCTAssertEqual(store.settings?.hiddenWorkspaces, ["acme-devmachine"])
        XCTAssertEqual(store.settings?.opsRepoPath, "/Users/alice/.config/devmachine")
        model.setHiddenWorkspaces([], in: store)
        XCTAssertEqual(store.settings?.hiddenWorkspaces, [])
    }

    func testASwitchBeforeTheAppIsSetUpWritesNothing() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "app.devmachine.mac.tests.\(UUID().uuidString)")!)
        let model = AppModel(store: SessionStore(runner: SilentRunner()))
        model.setHiddenWorkspaces(["acme-devmachine"], in: store)
        XCTAssertNil(store.settings)
    }

    func testNewWorkspaceFromTheSidebarOpensSettingsWorkspaces() {
        let model = AppModel(store: SessionStore(runner: SilentRunner()))
        model.requestNewWorkspace()
        XCTAssertEqual(model.activePage, .setup)
        XCTAssertEqual(model.requestedSettingsSection, .workspaces)
        XCTAssertTrue(model.pendingNewWorkspace)
    }

    /// The Edit screen has no package cards: packages live in Settings → Packages.
    func testTheEditFormLinksToPackagesInsteadOfListingCards() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/DevmachineApp/WorkspacesSettingsView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private struct WorkspaceEditForm"))
        let end = try XCTUnwrap(source.range(of: "private struct WorkspaceVariableFields", range: start.upperBound..<source.endIndex))
        let edit = source[start.lowerBound..<end.lowerBound]
        XCTAssertFalse(edit.contains("WorkspacePackageCards"))
        XCTAssertTrue(edit.contains("WorkspacesContent.packagesLink"))
        XCTAssertTrue(source.contains("model.openPackages(workspace: flow.name)"))
        XCTAssertTrue(source.contains(".onDisappear { store.leave() }"), "leaving the section drops the flow")
    }
}
