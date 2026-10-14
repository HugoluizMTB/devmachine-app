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
        XCTAssertEqual(screens.last?.fileName, "home/003.png")
        XCTAssertEqual(Set(screens.map(\.id)).count, screens.count)
        XCTAssertTrue(screens.allSatisfy { DemoSiteWalk.handles($0.id) })
        XCTAssertFalse(DemoSnapshots.screens.contains { DemoSiteWalk.handles($0.id) })
    }

    func testEverySceneLastsSixToTenSecondsWithItsPointerMoves() {
        for scene in DemoSiteWalk.scenes {
            XCTAssertTrue((6...10).contains(scene.seconds), "\(scene.id) lasts \(scene.seconds)s")
        }
    }

    func testTheConcatListHoldsEachFrameAndNamesTheLastOneAgain() {
        XCTAssertEqual(DemoSiteWalk.ffconcat([1.5, 0.033, 3]), """
            ffconcat version 1.0
            file '001.png'
            duration 1.500
            file '002.png'
            duration 0.033
            file '003.png'
            duration 3.000
            file '003.png'

            """)
    }

    func testAClickAddsAMoveAndARingOfAboutHalfASecond() {
        let plain = DemoSiteWalk.Scene(id: "x", frames: [.init(step: .home, hold: 1)])
        let clicked = DemoSiteWalk.Scene(
            id: "x", frames: [.init(step: .home, hold: 1, click: .init(target: "footer:close-sidebar"))])
        XCTAssertEqual(clicked.seconds - plain.seconds, DemoPointer.clickSeconds, accuracy: 0.001)
        XCTAssertTrue((0.2...0.4).contains(Double(DemoPointer.moveFrames) * DemoPointer.moveFrameSeconds))
        XCTAssertEqual(Double(DemoPointer.rings.count) * DemoPointer.clickFrameSeconds, 0.15, accuracy: 0.001)
    }

    func testThePointerEasesFromWhereItWasToTheTarget() {
        let path = DemoPointer.path(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 50))
        XCTAssertEqual(path.count, DemoPointer.moveFrames)
        XCTAssertEqual(path.last, CGPoint(x: 100, y: 50))
        let steps = zip(path, path.dropFirst()).map { $1.x - $0.x }
        XCTAssertLessThan(steps.first ?? 0, steps[steps.count / 2])
        XCTAssertLessThan(steps.last ?? 0, steps[steps.count / 2])
    }

    func testTheClickRingShrinksAndFades() {
        let rings = DemoPointer.rings
        XCTAssertEqual(rings.map(\.radius), rings.map(\.radius).sorted(by: >))
        XCTAssertEqual(rings.map(\.opacity), rings.map(\.opacity).sorted(by: >))
    }

    func testEveryClickNamesAControlTheAppMarks() {
        let targets = DemoSiteWalk.scenes.flatMap(\.frames).compactMap(\.click?.target)
        XCTAssertEqual(Set(targets), [
            "grid:acme-devmachine", "local:\(Workspace.operatorSession)", "session:globex-devmachine/claude",
            "footer:published-apps", "session:acme-devmachine/claude — payments refactor", "sheet:share",
            "sheet:done", "tab:Chat", "footer:close-sidebar",
        ])
        XCTAssertFalse(DemoSiteWalk.scenes.contains { $0.frames.first?.click != nil })
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
        XCTAssertEqual(transcripts.count, DemoSiteWalk.scenes[1].frames.count - 1)
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
        XCTAssertNotNil(DemoSiteWalk.sheet(for: .shareSheet))
        XCTAssertNotNil(DemoSiteWalk.sheet(for: .shareLink))
        XCTAssertNil(DemoSiteWalk.sheet(for: .shared))
    }

    func testClickTargetsAreRecordedOnlyWhileAWalkCaptures() {
        XCTAssertFalse(DemoClickTargets.isRecording)
    }
}
