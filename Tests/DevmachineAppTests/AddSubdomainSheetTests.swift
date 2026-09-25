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
