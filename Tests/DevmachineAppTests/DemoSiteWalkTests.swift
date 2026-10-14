import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class DemoSiteWalkTests: XCTestCase {
    override func tearDown() async throws {
        DemoData.transcriptOverride = [:]
        DemoContextOverride.shared.value = nil
        try await super.tearDown()
    }

    func testTheSiteWalkIsFiveScenesOfNumberedFramesEachInItsOwnFolder() {
        let screens = DemoSnapshots.walk(environment: ["DEVMACHINE_DEMO_WALK": "site"])
        XCTAssertEqual(DemoSiteWalk.scenes.map(\.id), ["sessions", "cli", "context", "publish", "home"])
        XCTAssertEqual(screens.count, DemoSiteWalk.scenes.reduce(0) { $0 + $1.frames.count })
        XCTAssertEqual(screens.first?.fileName, "sessions/001.png")
        XCTAssertEqual(screens.last?.fileName, "home/002.png")
        XCTAssertEqual(Set(screens.map(\.id)).count, screens.count)
        XCTAssertTrue(screens.allSatisfy { DemoSiteWalk.handles($0.id) })
        XCTAssertFalse(DemoSnapshots.screens.contains { DemoSiteWalk.handles($0.id) })
    }

    func testEverySceneLastsSixToTenSeconds() {
        for scene in DemoSiteWalk.scenes {
            XCTAssertTrue((6...10).contains(scene.seconds), "\(scene.id) lasts \(scene.seconds)s")
        }
    }

    func testTheConcatListHoldsEachFrameAndNamesTheLastOneAgain() {
        let scene = DemoSiteWalk.Scene(id: "x", frames: [
            .init(step: .home, hold: 1.5), .init(step: .homeWide, hold: 3),
        ])
        XCTAssertEqual(DemoSiteWalk.ffconcat(scene), """
            ffconcat version 1.0
            file '001.png'
            duration 1.50
            file '002.png'
            duration 3.00
            file '002.png'

            """)
    }

    func testEachFrameIsFoundByItsScreenID() {
        XCTAssertEqual(DemoSiteWalk.frame(for: "site-sessions-001")?.step, .sidebar)
        XCTAssertEqual(DemoSiteWalk.frame(for: "site-home-002")?.step, .homeWide)
        XCTAssertNil(DemoSiteWalk.frame(for: "site-home-099"))
    }

    func testTheSessionsSceneMarksOneRowBusyAndAnotherWaiting() {
        let sessions = DemoSiteWalk.sessions(busy: true, attention: true)["acme-devmachine"] ?? []
        XCTAssertEqual(sessions.filter { $0.indicators?.busy == true }.map(\.name), ["claude — payments refactor"])
        XCTAssertEqual(sessions.filter { $0.indicators?.attention == true }.map(\.name), ["codex — landing page"])
        XCTAssertTrue(sessions.allSatisfy { $0.indicators?.branch != nil && $0.indicators?.ageSeconds != nil })
        let calm = DemoSiteWalk.sessions(busy: false, attention: false).values.joined()
        XCTAssertFalse(calm.contains { $0.indicators?.busy == true || $0.indicators?.attention == true })
    }

    func testTheCLISceneAddsOutputToTheSameTerminalStepByStep() {
        let transcripts = DemoSiteWalk.cliTranscripts
        XCTAssertEqual(transcripts.count, DemoSiteWalk.scenes[1].frames.count)
        for (earlier, later) in zip(transcripts, transcripts.dropFirst()) {
            XCTAssertTrue(later.hasPrefix(earlier))
        }
        let last = transcripts.last ?? ""
        XCTAssertTrue(last.contains("added main to /Users/alice/.config/devmachine/config.yml"))
        XCTAssertTrue(last.contains("added claude-code to workspace acme"))
        XCTAssertTrue(last.contains("main: ok=86 changed=12 failed=0"))
    }

    func testTheCLITranscriptReplacesTheOperatorsOwnOnlyWhileSet() {
        let kind = DemoSiteWalk.operatorKind
        DemoData.transcriptOverride = [kind: "$ devmachine sync"]
        XCTAssertTrue(DemoData.terminalTranscript(for: kind).hasSuffix("$ devmachine sync"))
        DemoData.transcriptOverride = [:]
        XCTAssertFalse(DemoData.terminalTranscript(for: kind).hasSuffix("$ devmachine sync"))
    }

    func testTheContextSceneMovesTheToDoListForwardAndTurnsThePullRequestGreen() throws {
        let states = DemoSiteWalk.contextStates
        let done = states.map { $0.plan?.done ?? 0 }
        XCTAssertEqual(done, done.sorted())
        XCTAssertEqual(states.last?.plan?.done, states.last?.plan?.total)
        XCTAssertEqual(states.first?.prs.first { $0.number == 415 }?.ci, "pending")
        XCTAssertEqual(states.last?.prs.first { $0.number == 415 }?.ci, "success")
        XCTAssertEqual(states.map { $0.agents.first?.status }, [nil, "running", "done", "done", "done"])
        XCTAssertEqual(DemoSiteWalk.contextTranscripts.count, states.count)
    }

    func testTheDemoContextAnswersWithTheWalksStateWhileOneIsSet() throws {
        let target = CommandTarget.remote(alias: "globex-devmachine", session: "claude")
        let walkState = try XCTUnwrap(DemoSiteWalk.contextStates.last)
        DemoContextOverride.shared.value = walkState
        XCTAssertEqual(try DemoContextSource().context(for: target, settings: .empty), walkState)
        DemoContextOverride.shared.value = nil
        XCTAssertEqual(try DemoContextSource().context(for: target, settings: .empty), DemoData.contextState)
    }

    func testTheShareFramesDrawTheirSheetOverTheWindow() {
        XCTAssertNotNil(DemoSiteWalk.sheet(for: "site-publish-004"))
        XCTAssertNotNil(DemoSiteWalk.sheet(for: "site-publish-005"))
        XCTAssertNil(DemoSiteWalk.sheet(for: "site-publish-006"))
    }
}
