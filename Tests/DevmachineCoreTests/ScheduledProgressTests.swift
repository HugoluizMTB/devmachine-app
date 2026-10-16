import XCTest
@testable import DevmachineCore

final class ScheduledProgressTests: XCTestCase {
    private func run(_ id: String, _ status: String, startedAt: String) throws -> ScheduledRun {
        let json = """
        {"runs":[{"id":"\(id)","task_id":"t_1","status":"\(status)","trigger":"manual",
        "started_at":"\(startedAt)","duration_ms":0}]}
        """
        return try XCTUnwrap(ScheduledJSON.decodeRuns(Data(json.utf8)).first)
    }

    func testLatestRunPrefersTheNewestOfTheListAndTheRunsRead() throws {
        let listed = try run("r1", "succeeded", startedAt: "2026-10-15T10:00:00Z")
        let running = try run("r2", "running", startedAt: "2026-10-16T10:00:00Z")
        XCTAssertEqual(ScheduledRun.latest(listed: listed, read: [running, listed])?.id, "r2")
        XCTAssertEqual(ScheduledRun.latest(listed: running, read: [listed])?.id, "r2")
        XCTAssertEqual(ScheduledRun.latest(listed: nil, read: [running])?.id, "r2")
        XCTAssertEqual(ScheduledRun.latest(listed: listed, read: [])?.id, "r1")
        XCTAssertNil(ScheduledRun.latest(listed: nil, read: []))
    }

    func testLatestRunTakesTheReadCopyOfTheSameRun() throws {
        let listed = try run("r2", "running", startedAt: "2026-10-16T10:00:00Z")
        let ended = try run("r2", "succeeded", startedAt: "2026-10-16T10:00:00Z")
        XCTAssertEqual(ScheduledRun.latest(listed: listed, read: [ended])?.status, .succeeded)
        XCTAssertEqual(ScheduledRun.latest(listed: ended, read: [listed])?.status, .succeeded)
    }

    private let syncOutput = """
    added scheduled to workspace alice
    workspace alice (user alice):
      + scheduled
    \u{1B}[0;32mPLAY [main] *******************************************\u{1B}[0m

    TASK [Gathering Facts] *********************************************
    ok: [main]

    TASK [scheduled : Install the devmachine binary] ********************
    changed: [main]

    TASK [scheduled : Write the timer unit] *****************************
    changed: [main]

    RUNNING HANDLER [scheduled : Reload systemd] ************************
    ok: [main]

    TASK [scheduled : Start the timer] **********************************
    """

    private func progress(after text: String) -> ScheduledSetupProgress {
        var p = ScheduledSetupProgress(workspace: "alice", machine: "main")
        text.split(separator: "\n", omittingEmptySubsequences: false).forEach { p.read(String($0)) }
        return p
    }

    func testSetupStartsByAddingThePackage() {
        let p = ScheduledSetupProgress(workspace: "alice", machine: "main")
        XCTAssertEqual(p.phase, .addingPackage)
        XCTAssertEqual(p.steps.map(\.state), [.running, .waiting, .waiting, .waiting])
    }

    func testThePackageLineMovesToConnecting() {
        let p = progress(after: "added scheduled to workspace alice")
        XCTAssertEqual(p.phase, .connecting)
        XCTAssertEqual(p.steps.map(\.state), [.done, .running, .waiting, .waiting])
    }

    func testAPackageAlreadyThereAlsoMovesOn() {
        XCTAssertEqual(progress(after: "scheduled is already on workspace alice").phase, .connecting)
    }

    func testAnsibleTasksAreCountedAndNamedWithoutTheirRole() {
        let p = progress(after: syncOutput)
        XCTAssertEqual(p.phase, .installing)
        XCTAssertEqual(p.stepsStarted, 5)
        XCTAssertEqual(p.current, "Start the timer")
        XCTAssertEqual(p.recent, ["Install the devmachine binary", "Write the timer unit", "Reload systemd"])
        XCTAssertEqual(p.steps.map(\.state), [.done, .done, .running, .waiting])
        XCTAssertEqual(p.steps[2].detail, "Step 5: Start the timer\nDone: Reload systemd")
    }

    func testTheRecapMovesToCreatingTheTask() {
        let p = progress(after: syncOutput + "\nPLAY RECAP ****\nmain : ok=5 changed=2 failed=0\n\nReach a workspace:")
        XCTAssertEqual(p.phase, .creatingTask)
        XCTAssertEqual(p.steps.map(\.state), [.done, .done, .done, .running])
        XCTAssertEqual(p.steps[2].detail, "5 steps done")
    }

    func testAPhaseNeverGoesBack() {
        var p = progress(after: syncOutput + "\nPLAY RECAP ****")
        p.read("added scheduled to workspace alice")
        p.read("TASK [scheduled : Again] ****")
        XCTAssertEqual(p.phase, .creatingTask)
        XCTAssertEqual(p.stepsStarted, 5)
    }

    func testOutputItDoesNotKnowChangesNothing() {
        let p = progress(after: "something new a later CLI prints\n\n")
        XCTAssertEqual(p, ScheduledSetupProgress(workspace: "alice", machine: "main"))
    }

    func testStepTitlesNameTheWorkspaceAndMachine() {
        XCTAssertEqual(
            ScheduledSetupProgress(workspace: "alice", machine: "main").steps.map(\.title),
            ["Add the scheduled package to alice", "Connect to main", "Install on main", "Create the task"])
    }
}
