import XCTest
@testable import DevmachineCore

final class WorkspaceVisibilityTests: XCTestCase {
    private let all = [
        Workspace(name: "acme", alias: "acme-devmachine"),
        Workspace(name: "initech", alias: "initech-devmachine"),
        Workspace(name: "globex", alias: "globex-devmachine"),
    ]

    func testNothingHiddenShowsEverything() {
        XCTAssertEqual(WorkspaceVisibility.visible(all, hidden: []).map(\.name),
                       ["acme", "initech", "globex"])
    }

    func testHiddenAliasesAreLeftOut() {
        let visible = WorkspaceVisibility.visible(
            all, hidden: ["initech-devmachine", "globex-devmachine"])
        XCTAssertEqual(visible.map(\.name), ["acme"])
    }

    func testAnAliasThatIsNotThereChangesNothing() {
        XCTAssertEqual(
            WorkspaceVisibility.visible(all, hidden: ["gone-devmachine"]).count, 3)
    }

    func testCaseDoesNotDecideVisibility() {
        XCTAssertTrue(WorkspaceVisibility.visible(all, hidden: ["ACME-Devmachine"]).allSatisfy {
            $0.name != "acme"
        })
        XCTAssertTrue(WorkspaceVisibility.isHidden("ACME-DEVMACHINE", hidden: ["acme-devmachine"]))
    }

    func testTogglingAddsThenRemoves() {
        var hidden = WorkspaceVisibility.toggling("initech-devmachine", in: [])
        XCTAssertEqual(hidden, ["initech-devmachine"])
        hidden = WorkspaceVisibility.toggling("initech-devmachine", in: hidden)
        XCTAssertEqual(hidden, [])
    }

    func testTogglingNeverRepeatsAnAlias() {
        let hidden = WorkspaceVisibility.toggling("Initech-Devmachine", in: ["initech-devmachine"])
        XCTAssertEqual(hidden, [])
    }

    func testAListIsCarriedThroughSettings() throws {
        let settings = AppSettings(
            opsRepoPath: "/tmp", hostAlias: "host", publicIP: "203.0.113.10",
            baseDomain: "example.com", hiddenWorkspaces: ["initech-devmachine"])
        let round = try JSONDecoder().decode(
            AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(round.hiddenWorkspaces, ["initech-devmachine"])
    }

    func testSettingsWrittenBeforeTheListHideNothing() throws {
        let json = #"{"opsRepoPath":"/tmp","hostAlias":"h","publicIP":"203.0.113.10","baseDomain":"example.com"}"#
        let settings = try JSONDecoder().decode(
            AppSettings.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(settings.hiddenWorkspaces, [])
    }
}
