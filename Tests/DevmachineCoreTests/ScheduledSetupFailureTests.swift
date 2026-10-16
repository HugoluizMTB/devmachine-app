import XCTest
@testable import DevmachineCore

final class ScheduledSetupFailureTests: XCTestCase {
    private let failedSetupStderr = """
    added scheduled to workspace alice
    workspace alice (user alice):
      + scheduled
    PLAY [main] ****
    TASK [scheduled : Unpack the release] ****
    fatal: [main]: FAILED! => {"changed": false, "msg": "Failed to find handler"}
    PLAY RECAP ****
    main : ok=9 changed=1 unreachable=0 failed=1
    error: setting up scheduled on main failed: 1 task(s) failed on main, first "scheduled : Unpack the release": Failed to find handler
    """

    func testTheReasonIsTheCLIsErrorLineNotTheSyncAboveIt() {
        XCTAssertEqual(
            CLIStderr.reason(failedSetupStderr),
            #"setting up scheduled on main failed: 1 task(s) failed on main, first "scheduled : Unpack the release": Failed to find handler"#)
    }

    func testTheLastErrorLineWins() {
        XCTAssertEqual(CLIStderr.reason("error: first\nmore output\nerror: second\n"), "second")
    }

    func testStderrWithoutAnErrorLineIsKeptWhole() {
        XCTAssertEqual(CLIStderr.reason("  something broke\nbadly  \n"), "something broke\nbadly")
        XCTAssertEqual(CLIStderr.reason("error: only one"), "only one")
    }

    private func workspace(error kind: String?) throws -> ScheduledWorkspace {
        let error = kind.map { #","error":{"kind":"\#($0)","message":"m"}"# } ?? ""
        let json = #"{"workspaces":[{"name":"alice","machine":"main","installed":false,"tasks":[]\#(error)}]}"#
        return try XCTUnwrap(ScheduledJSON.decodeList(Data(json.utf8)).first)
    }

    func testAnIncompleteSetupAsksToBeFinished() throws {
        XCTAssertTrue(try workspace(error: "setup-incomplete").setupIncomplete)
        XCTAssertTrue(try workspace(error: "not-installed").setupIncomplete)
        XCTAssertFalse(try workspace(error: "unreachable").setupIncomplete)
        XCTAssertFalse(try workspace(error: nil).setupIncomplete)
    }

    func testFinishingASetupOnlyConnectsAndInstalls() {
        var p = ScheduledSetupProgress(workspace: "alice", machine: "main", finishing: true)
        XCTAssertEqual(p.steps.map(\.title), ["Connect to main", "Install on main"])
        XCTAssertEqual(p.steps.map(\.state), [.running, .waiting])
        p.read("PLAY [main] ****")
        p.read("TASK [scheduled : Unpack the release] ****")
        XCTAssertEqual(p.steps.map(\.state), [.done, .running])
        p.read("PLAY RECAP ****")
        XCTAssertEqual(p.steps.map(\.state), [.done, .done])
    }
}
