import XCTest
import DevmachineCore
@testable import DevmachineApp

final class PublishSuggestionsServiceTests: XCTestCase {
    func testPortsAreReadOnTheMachineTheWorkspaceLivesOn() {
        let runner = MultiMachineCLIRunner()
        let service = PublishSuggestionsService(cli: DevmachineCLI(executable: "/fake/devmachine", runner: runner))

        let suggestions = service.suggestions(forWorkspace: "alice")

        XCTAssertEqual(suggestions.domain, "example.com")
        XCTAssertEqual(suggestions.ports.map(\.port), [8810])
        XCTAssertTrue(runner.calls.contains(["run", "--machine", "box", "--package", "devmachine-app", "--", "stats"]))
        XCTAssertEqual(runner.callsWithoutATarget, [])
    }
}
