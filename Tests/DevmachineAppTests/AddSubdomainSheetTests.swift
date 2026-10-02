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

final class AddSubdomainViaTests: XCTestCase {
    private let workspaces = [
        Workspace(name: "alice", alias: "alice-devmachine"),
        Workspace(name: "bob", alias: "bob-devmachine"),
    ]
    private let places = PublishPlaces(
        servingMachines: ["edge"], machineOf: ["alice": "edge", "bob": "lab"])

    private func form(_ selected: String, preferring: String? = nil) -> AddSubdomainForm {
        var form = AddSubdomainForm(workspaces: workspaces, preselectedWorkspace: selected)
        form.update(places: places, preferring: preferring)
        form.label = "app"
        form.port = "8080"
        return form
    }

    func testAWorkspaceWhoseMachineHasCaddyIsServedThere() {
        let form = form("alice")

        XCTAssertEqual(form.servingMachine, "edge")
        XCTAssertNil(form.via)
        XCTAssertFalse(form.workspaceMachineHasNoCaddy)
    }

    func testAWorkspaceOnAMachineWithoutCaddyIsServedByOneThatHasIt() {
        let form = form("bob")

        XCTAssertEqual(form.servingMachine, "edge")
        XCTAssertEqual(form.via, "edge")
        XCTAssertTrue(form.workspaceMachineHasNoCaddy)
        XCTAssertEqual(form.workspaceMachine, "lab")
    }

    func testThePageMachineIsPreferredAmongSeveral() {
        var form = AddSubdomainForm(workspaces: workspaces, preselectedWorkspace: "bob")
        form.update(
            places: PublishPlaces(servingMachines: ["edge", "spare"], machineOf: ["bob": "lab"]),
            preferring: "spare")

        XCTAssertEqual(form.via, "spare")
    }

    func testChoosingAnotherWorkspaceChoosesItsMachineAgain() {
        var form = form("bob")
        form.selectedWorkspace = "alice"
        form.workspaceChanged()

        XCTAssertNil(form.via)
    }

    func testWithoutKnowingWhereAnythingLivesNothingIsSentVia() {
        var form = AddSubdomainForm(workspaces: workspaces, preselectedWorkspace: "bob")
        form.update(places: PublishPlaces(), preferring: nil)

        XCTAssertNil(form.via)
        XCTAssertFalse(form.workspaceMachineHasNoCaddy)
    }
}
