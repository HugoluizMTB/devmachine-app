import XCTest
@testable import DevmachineCore

final class ProcessTreeTests: XCTestCase {
    func testReadsTheForegroundGroup() {
        XCTAssertEqual(ProcessTree.foregroundGroup(fromTPGID: " 13574\n"), 13574)
    }

    func testNoForegroundGroupWhenThereIsNone() {
        XCTAssertNil(ProcessTree.foregroundGroup(fromTPGID: "-1\n"))
        XCTAssertNil(ProcessTree.foregroundGroup(fromTPGID: "\n"))
        XCTAssertNil(ProcessTree.foregroundGroup(fromTPGID: "what"))
    }

    func testAShellIsAtItsPromptOnlyWhenItIsTheForegroundGroup() {
        XCTAssertEqual(ProcessTree.isAtPrompt(shellPID: 400, tpgidOutput: " 400\n"), true)
        XCTAssertEqual(ProcessTree.isAtPrompt(shellPID: 400, tpgidOutput: " 512\n"), false)
        XCTAssertNil(ProcessTree.isAtPrompt(shellPID: 400, tpgidOutput: "0\n"))
    }

    func testTheSignalGoesToTheWholeGroup() {
        XCTAssertEqual(ProcessTree.windowChangedArguments(group: 42), ["-WINCH", "-42"])
    }

    func testFindsTheSessionPidInAListing() {
        let listing = "  name=dev\tpid=77\tclients=1\tcreated=1\n  name=Operator\tpid=88\tclients=0\tcreated=2"
        XCTAssertEqual(Zmx.pid(of: "Operator", in: listing), 88)
        XCTAssertNil(Zmx.pid(of: "absent", in: listing))
    }
}
