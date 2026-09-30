import XCTest
@testable import DevmachineCore

final class RelaunchCommandTests: XCTestCase {
    func testWaitsForThisProcessThenOpensANewCopy() {
        let command = RelaunchCommand(appPath: "/Applications/Devmachine.app", processID: 4242)
        XCTAssertEqual(command.executable, "/bin/sh")
        XCTAssertEqual(command.arguments.count, 4)
        XCTAssertEqual(command.arguments[0], "-c")
        XCTAssertTrue(command.arguments[1].contains("kill -0"))
        XCTAssertTrue(command.arguments[1].contains("sleep 1"))
        XCTAssertTrue(command.arguments[1].contains("/usr/bin/open -n"))
        XCTAssertEqual(command.arguments[2], "/Applications/Devmachine.app")
        XCTAssertEqual(command.arguments[3], "4242")
    }

    func testThePathNeverEntersTheScriptText() {
        let path = "/Applications/Dev \"$(rm -rf ~)\".app"
        let command = RelaunchCommand(appPath: path, processID: 1)
        XCTAssertFalse(command.arguments[1].contains(path))
    }
}
