import XCTest
@testable import DevmachineCore

final class WorkspaceSettingsListTests: XCTestCase {
    private let acme = WorkspaceSummary(name: "acme", machine: "main", user: "acme", packages: ["dev"])
    private let beta = WorkspaceSummary(name: "beta", machine: "main", user: "beta", packages: [])
    private let gamma = WorkspaceSummary(name: "gamma", machine: "staging", user: "gamma", packages: ["pi"])
    private let machines = [
        WorkspaceSettingsList.Machine(name: "staging", location: "external"),
        WorkspaceSettingsList.Machine(name: "main", location: "home"),
    ]
    private let sidebar = [
        Workspace(name: "acme", alias: "acme-devmachine"),
        Workspace(name: "beta", alias: "beta-devmachine"),
        Workspace(name: "gamma", alias: "gamma-devmachine"),
    ]

    func testWorkspacesAreGroupedUnderTheirMachineInTheConfigurationsOrder() {
        let sections = WorkspaceSettingsList.sections(
            summaries: [acme, gamma, beta], machines: machines, sidebar: sidebar, hidden: [])
        XCTAssertEqual(sections.map(\.machine), ["staging", "main"])
        XCTAssertEqual(sections.map(\.location), ["external", "home"])
        XCTAssertEqual(sections.map { $0.rows.map(\.name) }, [["gamma"], ["acme", "beta"]])
    }

    func testAMachineWithNoWorkspaceHasNoSection() {
        let sections = WorkspaceSettingsList.sections(
            summaries: [gamma], machines: machines, sidebar: [], hidden: [])
        XCTAssertEqual(sections.map(\.machine), ["staging"])
    }

    func testAMachineTheConfigurationDoesNotNameStillGetsItsSectionWithNoLocation() {
        let edge = WorkspaceSummary(name: "edgy", machine: "edge", user: "edgy", packages: [])
        let sections = WorkspaceSettingsList.sections(
            summaries: [acme, edge], machines: machines, sidebar: [], hidden: [])
        XCTAssertEqual(sections.map(\.machine), ["main", "edge"])
        XCTAssertNil(sections.last?.location)
    }

    func testEachRowSaysWhetherItsWorkspaceIsActive() {
        let sections = WorkspaceSettingsList.sections(
            summaries: [acme, beta], machines: machines, sidebar: Array(sidebar.prefix(2)), hidden: ["BETA-devmachine"])
        let rows = sections.flatMap(\.rows)
        XCTAssertEqual(rows.map(\.alias), ["acme-devmachine", "beta-devmachine"])
        XCTAssertEqual(rows.map(\.isActive), [true, false])
    }

    func testAWorkspaceTheSidebarDoesNotKnowHasNoSwitch() {
        let sections = WorkspaceSettingsList.sections(
            summaries: [acme], machines: machines, sidebar: [], hidden: [])
        XCTAssertNil(sections.first?.rows.first?.alias)
        XCTAssertEqual(sections.first?.rows.first?.isActive, true)
    }

    func testASidebarWorkspaceTheListDoesNotHoldKeepsItsSwitchUnderUnknownMachine() {
        let sections = WorkspaceSettingsList.sections(
            summaries: [acme], machines: machines, sidebar: sidebar + [.local], hidden: ["gamma-devmachine"])
        XCTAssertEqual(sections.map(\.machine), ["main", WorkspaceSettingsList.unknownMachine])
        let other = sections.last?.rows ?? []
        XCTAssertEqual(other.map(\.name), ["beta", "gamma"], "never this Mac")
        XCTAssertEqual(other.map(\.isActive), [true, false])
        XCTAssertNil(other.first?.summary)
    }

    func testSwitchingAWorkspaceOnAndOffWritesTheHiddenList() {
        var hidden = WorkspaceVisibility.setting("acme-devmachine", active: false, in: [])
        XCTAssertEqual(hidden, ["acme-devmachine"])
        hidden = WorkspaceVisibility.setting("acme-devmachine", active: false, in: hidden)
        XCTAssertEqual(hidden, ["acme-devmachine"], "off twice hides it once")
        hidden = WorkspaceVisibility.setting("ACME-devmachine", active: true, in: hidden)
        XCTAssertEqual(hidden, [])
        XCTAssertEqual(WorkspaceVisibility.setting("acme-devmachine", active: true, in: []), [])
    }
}
