import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class DemoSiteWalkTests: XCTestCase {
    override func tearDown() async throws {
        DemoData.transcriptOverride = [:]
        DemoData.walkLocalSessions = []
        DemoContextOverride.shared.value = nil
        try await super.tearDown()
    }

    func testTheSiteWalkIsSixScenesOfNumberedFramesEachInItsOwnFolder() {
        let screens = DemoSnapshots.walk(environment: ["DEVMACHINE_DEMO_WALK": "site"])
        XCTAssertEqual(
            DemoSiteWalk.scenes.map(\.id), ["operator", "sessions", "cli", "context", "publish", "home"])
        XCTAssertEqual(screens.count, DemoSiteWalk.scenes.reduce(0) { $0 + $1.frames.count })
        XCTAssertEqual(screens.first?.fileName, "operator/001.png")
        XCTAssertEqual(Set(screens.map(\.id)).count, screens.count)
        XCTAssertTrue(screens.allSatisfy { DemoSiteWalk.handles($0.id) })
        XCTAssertFalse(DemoSnapshots.screens.contains { DemoSiteWalk.handles($0.id) })
    }

    func testEverySceneLastsSixToTwelveSecondsWithItsPointerMoves() {
        for scene in DemoSiteWalk.scenes {
            XCTAssertTrue((6...12).contains(scene.seconds), "\(scene.id) lasts \(scene.seconds)s")
        }
    }

    func testEverySceneOpensOnItsSubjectWithoutAClick() {
        XCTAssertEqual(DemoSiteWalk.scenes.map { $0.frames.first?.pointer }, Array(repeating: nil, count: 6))
        XCTAssertEqual(DemoSiteWalk.scenes.map { $0.frames.first?.step }, [
            .operatorChat(0), .sidebar, .cli(0), .context(0), .publishedApps, .homeStart,
        ])
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

    func testAClickAddsAMoveAndARingAndAHoverOnlyTheMove() {
        let spot = DemoSiteWalk.Spot(target: "footer:close-sidebar")
        func seconds(_ pointer: DemoSiteWalk.Pointer?) -> Double {
            DemoSiteWalk.Scene(id: "x", frames: [.init(step: .homeStart, hold: 1, pointer: pointer)]).seconds
        }
        XCTAssertEqual(seconds(.click(spot)) - seconds(nil), DemoPointer.clickSeconds, accuracy: 0.001)
        XCTAssertEqual(seconds(.hover(spot)) - seconds(nil), DemoPointer.moveSeconds, accuracy: 0.001)
        XCTAssertEqual(seconds(.follow(spot)), seconds(nil), accuracy: 0.001)
        XCTAssertTrue((0.2...0.4).contains(DemoPointer.moveSeconds))
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

    func testEveryPointerNamesAControlTheAppMarks() {
        let targets = Set(DemoSiteWalk.scenes.flatMap(\.frames).compactMap(\.pointer?.spot.target))
        XCTAssertEqual(targets, [
            "grid:acme-devmachine", "context:todo", "context:sub-agents", "context:pull-requests", "tab:Git",
            "session:acme-devmachine/claude — payments refactor", "sheet:share", "sheet:done", "tab:Chat",
            "widget:\(DemoSiteWalk.codexUsage)", "widget:\(DemoSiteWalk.claudeUsage)", "home:add",
            "sheet:gallery:\(DemoSiteWalk.summaryType)",
        ])
    }

    func testLabelsAreSparseAndPlain() {
        for scene in DemoSiteWalk.scenes {
            let labels = scene.frames.compactMap(\.label?.text)
            XCTAssertLessThanOrEqual(Set(labels).count, 4, scene.id)
            XCTAssertTrue(labels.allSatisfy { $0.count <= 40 }, scene.id)
        }
    }

    func testTheSessionsSceneMarksOneRowBusyAndAnotherWaiting() {
        let sessions = DemoSiteWalk.sessions(busy: true, attention: true)["acme-devmachine"] ?? []
        XCTAssertEqual(sessions.filter { $0.indicators?.busy == true }.map(\.name), ["claude — payments refactor"])
        XCTAssertEqual(sessions.filter { $0.indicators?.attention == true }.map(\.name), ["codex — landing page"])
        XCTAssertTrue(sessions.allSatisfy { $0.indicators?.branch != nil && $0.indicators?.ageSeconds != nil })
        let calm = DemoSiteWalk.sessions(busy: false, attention: false).values.joined()
        XCTAssertFalse(calm.contains { $0.indicators?.busy == true || $0.indicators?.attention == true })
    }

    func testTheCLISceneIsTypedIntoAPlainTerminalStepByStep() {
        let frames = DemoSiteWalk.cliFrames
        XCTAssertEqual(frames.count, DemoSiteWalk.scenes[2].frames.count)
        for (earlier, later) in zip(frames, frames.dropFirst()) {
            XCTAssertTrue(later.hasPrefix(earlier))
        }
        let last = frames.last ?? ""
        XCTAssertTrue(last.contains("added main to /Users/alice/.config/devmachine/config.yml"))
        XCTAssertTrue(last.contains("added claude-code to workspace acme"))
        XCTAssertTrue(last.contains("main: ok=86 changed=12 failed=0"))
        XCTAssertNotEqual(DemoSiteWalk.terminalKind, DemoSiteWalk.operatorKind)
    }

    func testTheOperatorSceneAnswersThreeRequestsWithTheCLIsOwnWords() {
        let last = DemoSiteWalk.operatorTranscripts.last ?? ""
        XCTAssertEqual(DemoSiteWalk.operatorTranscripts.count, DemoSiteWalk.operatorHolds.count)
        XCTAssertEqual(DemoSiteWalk.operatorTranscripts.count, DemoSiteWalk.operatorLabels.count)
        for request in ["Add a workspace for alice", "Publish port 3000 of acme", "Why is staging slow?"] {
            XCTAssertTrue(last.contains(request), request)
        }
        XCTAssertTrue(last.contains("alice is in the configuration, on main, with the packages claude-code."))
        XCTAssertTrue(last.contains("added docker to machine main"))
        XCTAssertTrue(last.contains("published: https://app.example.com -> acme:3000 on main."))
        XCTAssertTrue(last.contains("memory  3.6G used of 3.8G, 210.0M available"))
    }

    func testAWalkTranscriptReplacesTheSessionsOwnOnlyWhileSet() {
        let kind = DemoSiteWalk.operatorKind
        DemoData.transcriptOverride = [kind: "$ devmachine sync"]
        XCTAssertTrue(DemoData.terminalTranscript(for: kind).hasSuffix("$ devmachine sync"))
        DemoData.transcriptOverride = [:]
        XCTAssertFalse(DemoData.terminalTranscript(for: kind).hasSuffix("$ devmachine sync"))
    }

    func testTheContextSceneTicksATaskFinishesTheSubAgentAndTurnsThePullRequestGreen() throws {
        let states = DemoSiteWalk.contextStates
        let done = states.map { $0.plan?.done ?? 0 }
        XCTAssertEqual(done, done.sorted())
        XCTAssertLessThan(done.first ?? 0, done.last ?? 0)
        XCTAssertEqual(states.first?.prs.first { $0.number == 415 }?.ci, "pending")
        XCTAssertEqual(states.last?.prs.first { $0.number == 415 }?.ci, "success")
        XCTAssertEqual(states.map { $0.agents.first?.status }, [nil, nil, "running", "done", "done"])
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

    func testSheetsAndThePopoverAreDrawnOverTheWindow() {
        XCTAssertNotNil(DemoSiteWalk.sheet(for: .shareSheet))
        XCTAssertNotNil(DemoSiteWalk.sheet(for: .shareLink))
        XCTAssertEqual(DemoSiteWalk.sheet(for: .homeGallery)?.below, "home:add")
        XCTAssertNil(DemoSiteWalk.sheet(for: .shared))
    }

    func testClickTargetsAreRecordedOnlyWhileAWalkCaptures() {
        XCTAssertFalse(DemoClickTargets.isRecording)
    }
}
