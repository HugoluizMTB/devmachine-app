import XCTest
import DevmachineCore
@testable import DevmachineApp

final class AddSubdomainSheetTests: XCTestCase {
    func testNoWorkspaceMeansTheFormCannotPublish() {
        var form = AddSubdomainForm(workspaces: [])
        form.label = "app"
        form.port = "8080"

        XCTAssertNil(form.request(baseDomain: "example.com"))
    }

    func testTheFirstVisibleRemoteWorkspaceIsSelectedInitially() {
        let form = AddSubdomainForm(workspaces: [
            Workspace(name: "operator", alias: "local", kind: .local),
            Workspace(name: "alice", alias: "alice-devmachine"),
            Workspace(name: "bob", alias: "bob-devmachine"),
        ])

        XCTAssertEqual(form.selectedWorkspace, "alice")
        XCTAssertEqual(form.workspaceNames, ["alice", "bob"])
    }

    func testAPreselectedWorkspaceWinsOverTheFirstOne() {
        let form = AddSubdomainForm(
            workspaces: [
                Workspace(name: "alice", alias: "alice-devmachine"),
                Workspace(name: "bob", alias: "bob-devmachine"),
            ],
            preselectedWorkspace: "bob")

        XCTAssertEqual(form.selectedWorkspace, "bob")
    }

    func testAPreselectedWorkspaceOutsideTheListIsIgnored() {
        let form = AddSubdomainForm(
            workspaces: [Workspace(name: "alice", alias: "alice-devmachine")],
            preselectedWorkspace: "ghost")

        XCTAssertEqual(form.selectedWorkspace, "alice")
    }

    func testSuggestedPortsFillTheFirstPortAndTheLabel() {
        let form = AddSubdomainForm(
            workspaces: [Workspace(name: "alice", alias: "alice-devmachine")],
            suggestedPorts: [PortSuggestion(port: 8810, containerName: "web")],
            suggestedLabel: "alice")

        XCTAssertEqual(form.port, "8810")
        XCTAssertEqual(form.label, "alice")
        XCTAssertEqual(form.suggestedPorts, [PortSuggestion(port: 8810, containerName: "web")])
    }

    func testAWorkspaceOutsideTheAvailableListIsRejected() {
        var form = AddSubdomainForm(workspaces: [
            Workspace(name: "alice", alias: "alice-devmachine"),
        ])
        form.selectedWorkspace = "hidden"
        form.label = "app"
        form.port = "8080"

        XCTAssertNil(form.request(baseDomain: "example.com"))
    }
}

final class AddSubdomainMachineScopeTests: XCTestCase {
    func testTheFormOffersOnlyTheWorkspacesOnTheChosenMachine() {
        let form = AddSubdomainForm(
            workspaces: [
                Workspace(name: "alice", alias: "alice-devmachine"),
                Workspace(name: "bob", alias: "bob-devmachine"),
            ],
            onMachine: ["bob"])

        XCTAssertEqual(form.workspaceNames, ["bob"])
        XCTAssertEqual(form.selectedWorkspace, "bob")
    }

    func testNoMachineScopeOffersEveryRemoteWorkspace() {
        let form = AddSubdomainForm(
            workspaces: [
                Workspace(name: "alice", alias: "alice-devmachine"),
                Workspace(name: "bob", alias: "bob-devmachine"),
            ],
            onMachine: nil)

        XCTAssertEqual(form.workspaceNames, ["alice", "bob"])
    }

    func testFreshPortsReplaceTheSuggestionWhenThePortWasNotTouched() {
        var form = AddSubdomainForm(
            workspaces: [Workspace(name: "alice", alias: "alice-devmachine")],
            suggestedPorts: [PortSuggestion(port: 3000)])

        form.updateSuggestions([PortSuggestion(port: 5173), PortSuggestion(port: 3000)])

        XCTAssertEqual(form.port, "5173")
        XCTAssertEqual(form.suggestedPorts.map(\.port), [5173, 3000])
    }

    func testFreshPortsLeaveATypedPortAlone() {
        var form = AddSubdomainForm(
            workspaces: [Workspace(name: "alice", alias: "alice-devmachine")],
            suggestedPorts: [PortSuggestion(port: 3000)])
        form.port = "9000"

        form.updateSuggestions([PortSuggestion(port: 5173)])

        XCTAssertEqual(form.port, "9000")
    }

    func testFirstPortsFillAnEmptyField() {
        var form = AddSubdomainForm(workspaces: [Workspace(name: "alice", alias: "alice-devmachine")])

        form.updateSuggestions([PortSuggestion(port: 5173)])

        XCTAssertEqual(form.port, "5173")
    }
}
