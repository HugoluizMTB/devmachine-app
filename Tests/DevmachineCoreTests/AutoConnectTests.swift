import XCTest
@testable import DevmachineCore

final class AutoConnectSettingsTests: XCTestCase {
    func testANewSettingsValueConnectsNothingAtStartup() {
        let settings = AppSettings(opsRepoPath: "/tmp", hostAlias: "h", publicIP: "", baseDomain: "example.com")
        XCTAssertEqual(settings.autoConnectWorkspaces, [])
    }

    func testSettingsWrittenBeforeTheListConnectNothing() throws {
        let json = #"{"opsRepoPath":"/tmp","hostAlias":"h","publicIP":"203.0.113.10","baseDomain":"example.com"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.autoConnectWorkspaces, [])
    }

    func testTheListSurvivesARoundTrip() throws {
        let settings = AppSettings(
            opsRepoPath: "/tmp", hostAlias: "h", publicIP: "203.0.113.10", baseDomain: "example.com",
            autoConnectWorkspaces: ["acme-devmachine", "beta-devmachine"])
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(round.autoConnectWorkspaces, ["acme-devmachine", "beta-devmachine"])
    }
}

final class AutoConnectQueueTests: XCTestCase {
    private func target(_ alias: String, _ session: String) -> AutoConnectTarget {
        AutoConnectTarget(alias: alias, session: session)
    }

    private let sessions: [(alias: String, sessions: [String])] = [
        ("acme-devmachine", ["main", "api"]),
        ("beta-devmachine", ["web"]),
    ]

    func testTable() {
        struct Row {
            let name: String
            var autoConnect = ["acme-devmachine", "beta-devmachine"]
            var hidden: [String] = []
            var blocked: Set<String> = []
            var open: Set<AutoConnectTarget> = []
            var queued: [AutoConnectTarget] = []
            var room = 24
            let expected: [AutoConnectTarget]
        }
        let acmeMain = target("acme-devmachine", "main")
        let acmeAPI = target("acme-devmachine", "api")
        let betaWeb = target("beta-devmachine", "web")
        let rows = [
            Row(name: "every session of every chosen workspace, in order", expected: [acmeMain, acmeAPI, betaWeb]),
            Row(name: "a workspace not chosen is left alone", autoConnect: ["beta-devmachine"], expected: [betaWeb]),
            Row(name: "nothing chosen connects nothing", autoConnect: [], expected: []),
            Row(name: "case does not decide the choice", autoConnect: ["ACME-devmachine"], expected: [acmeMain, acmeAPI]),
            Row(name: "a hidden workspace is never reached", hidden: ["acme-devmachine"], expected: [betaWeb]),
            Row(name: "a paused, host-key-refused or unsynced workspace waits", blocked: ["beta-devmachine"],
                expected: [acmeMain, acmeAPI]),
            Row(name: "a session with a terminal already is skipped", open: [acmeMain], expected: [acmeAPI, betaWeb]),
            Row(name: "a session already queued is not queued twice", queued: [acmeAPI], expected: [acmeMain, betaWeb]),
            Row(name: "never more than the room left", room: 2, expected: [acmeMain, acmeAPI]),
            Row(name: "the queue takes its share of the room", queued: [betaWeb], room: 2, expected: [acmeMain]),
            Row(name: "no room connects nothing", room: 0, expected: []),
            Row(name: "a room below zero connects nothing", room: -3, expected: []),
        ]
        for row in rows {
            let queue = AutoConnectQueue(
                autoConnect: row.autoConnect, hidden: row.hidden, blocked: row.blocked, open: row.open)
            XCTAssertEqual(queue.targets(sessions: sessions, queued: row.queued, room: row.room), row.expected, row.name)
        }
    }

    func testIsWantedSaysWhetherAQueuedSessionShouldStillStart() {
        let queue = AutoConnectQueue(
            autoConnect: ["acme-devmachine"], hidden: [], blocked: ["beta-devmachine"],
            open: [target("acme-devmachine", "main")])
        XCTAssertTrue(queue.isWanted(target("acme-devmachine", "api")))
        XCTAssertFalse(queue.isWanted(target("acme-devmachine", "main")))
        XCTAssertFalse(queue.isWanted(target("gamma-devmachine", "main")))
        let blocked = AutoConnectQueue(
            autoConnect: ["beta-devmachine"], hidden: [], blocked: ["beta-devmachine"], open: [])
        XCTAssertFalse(blocked.isWanted(target("beta-devmachine", "web")))
    }
}

@MainActor
final class AutoConnectWarmerTests: XCTestCase {
    @MainActor
    private final class Harness {
        var started: [String] = []
        var completions: [String: (Bool) -> Void] = [:]
        var timers: [(delay: TimeInterval, fire: () -> Void)] = []
        var unwanted: Set<String> = []
        var room = 100

        func warmer() -> AutoConnectWarmer<String> {
            AutoConnectWarmer<String>(
                timeout: 15,
                start: { [unowned self] target, done in
                    self.started.append(target)
                    self.completions[target] = done
                },
                isWanted: { [unowned self] in !self.unwanted.contains($0) },
                hasRoom: { [unowned self] in self.started.count < self.room },
                schedule: { [unowned self] delay, fire in self.timers.append((delay, fire)) })
        }
    }

    func testOnlyOneStartsAtATimeAndTheNextFollowsASuccess() {
        let harness = Harness()
        let warmer = harness.warmer()
        warmer.enqueue(["a", "b", "c"])
        XCTAssertEqual(harness.started, ["a"])
        XCTAssertEqual(warmer.inFlight, "a")
        XCTAssertEqual(warmer.queued, ["b", "c"])
        harness.completions["a"]?(true)
        XCTAssertEqual(harness.started, ["a", "b"])
    }

    func testAFailureAdvancesToo() {
        let harness = Harness()
        let warmer = harness.warmer()
        warmer.enqueue(["a", "b"])
        harness.completions["a"]?(false)
        XCTAssertEqual(harness.started, ["a", "b"])
    }

    func testATimeoutOfFifteenSecondsAdvancesAndALateAnswerIsIgnored() {
        let harness = Harness()
        let warmer = harness.warmer()
        warmer.enqueue(["a", "b", "c"])
        XCTAssertEqual(harness.timers.map(\.delay), [15])
        harness.timers[0].fire()
        XCTAssertEqual(harness.started, ["a", "b"])
        harness.completions["a"]?(true)
        XCTAssertEqual(harness.started, ["a", "b"], "a late answer from a must not start c")
        XCTAssertEqual(warmer.inFlight, "b")
    }

    func testAnOldTimerDoesNotCutTheNextConnectShort() {
        let harness = Harness()
        let warmer = harness.warmer()
        warmer.enqueue(["a", "b", "c"])
        harness.completions["a"]?(true)
        harness.timers[0].fire()
        XCTAssertEqual(harness.started, ["a", "b"])
        XCTAssertEqual(warmer.inFlight, "b")
    }

    func testEnqueueWhileBusyWaitsAndNeverRepeats() {
        let harness = Harness()
        let warmer = harness.warmer()
        warmer.enqueue(["a"])
        warmer.enqueue(["a", "b", "b"])
        XCTAssertEqual(harness.started, ["a"])
        XCTAssertEqual(warmer.queued, ["b"])
    }

    func testASessionNoLongerWantedIsDroppedWhenItsTurnComes() {
        let harness = Harness()
        let warmer = harness.warmer()
        warmer.enqueue(["a", "b", "c"])
        harness.unwanted = ["b"]
        harness.completions["a"]?(true)
        XCTAssertEqual(harness.started, ["a", "c"])
    }

    func testNoRoomLeftEmptiesTheQueue() {
        let harness = Harness()
        harness.room = 1
        let warmer = harness.warmer()
        warmer.enqueue(["a", "b", "c"])
        harness.completions["a"]?(true)
        XCTAssertEqual(harness.started, ["a"])
        XCTAssertNil(warmer.inFlight)
        XCTAssertEqual(warmer.queued, [])
    }

    func testAnAnswerGivenAtOnceStillStartsOneAfterTheOther() {
        var started: [String] = []
        let warmer = AutoConnectWarmer<String>(
            timeout: 15,
            start: { target, done in
                started.append(target)
                done(true)
            },
            isWanted: { _ in true }, hasRoom: { true }, schedule: { _, _ in })
        warmer.enqueue(["a", "b", "c"])
        XCTAssertEqual(started, ["a", "b", "c"])
        XCTAssertNil(warmer.inFlight)
    }
}
