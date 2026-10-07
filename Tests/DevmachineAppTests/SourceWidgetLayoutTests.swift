import XCTest
import SwiftUI
@testable import DevmachineApp
@testable import DevmachineCore

final class SourceWidgetLayoutTests: XCTestCase {
    func testTheRunButtonShowsForManualWidgetsAndEndedStreams() {
        var state = SourceWidgetState()
        XCTAssertTrue(SourceWidgetLayout.showsRunButton(every: .manual, state: state))
        XCTAssertFalse(SourceWidgetLayout.showsRunButton(every: .interval(60), state: state))
        XCTAssertFalse(SourceWidgetLayout.showsRunButton(every: .continuous, state: state))
        state.ended = true
        XCTAssertTrue(SourceWidgetLayout.showsRunButton(every: .continuous, state: state))
        state.isRunning = true
        XCTAssertFalse(SourceWidgetLayout.showsRunButton(every: .manual, state: state))
    }

    func testAListShowsOnlyTheRowsThatFit() {
        XCTAssertEqual(SourceWidgetLayout.listRows(height: 100, rowHeight: 24), 4)
        XCTAssertEqual(SourceWidgetLayout.listRows(height: 10, rowHeight: 24), 1)
    }

    func testAnOlderCLIOffersTheUpdate() {
        let state = SourceErrorPresentation.state(.needsNewerCLI("Error: unknown flag: --argv"))
        XCTAssertTrue(state.needsCLIUpdate)
        XCTAssertEqual(state.title, "This needs a newer devmachine CLI")
        XCTAssertEqual(state.details, "Error: unknown flag: --argv")
        XCTAssertFalse(SourceErrorPresentation.state(.timedOut(30)).needsCLIUpdate)
    }

    func testTheANSIPaletteHasTheSixteenColorsAndTheCube() {
        XCTAssertEqual(ANSIPalette.rgb(.palette(1)).red, 0.80, accuracy: 0.01)
        XCTAssertEqual(ANSIPalette.rgb(.palette(16)).red, 0, accuracy: 0.001)
        XCTAssertEqual(ANSIPalette.rgb(.palette(231)).green, 1, accuracy: 0.001)
        XCTAssertEqual(ANSIPalette.rgb(.palette(232)).blue, 8.0 / 255, accuracy: 0.001)
        XCTAssertEqual(ANSIPalette.rgb(.rgb(255, 0, 128)).blue, 128.0 / 255, accuracy: 0.001)
    }

    func testAttributedTextKeepsEveryCharacter() {
        let text = ANSIPalette.attributed(ANSIText.lines("\u{1B}[31mred\u{1B}[0m plain\nnext"))
        XCTAssertEqual(String(text.characters), "red plain\nnext")
    }

    func testAWebWidgetKeepsItsPageAndSendsClickedLinksToTheBrowser() {
        let page = URL(string: "https://example.com/status")!
        let mail = URL(string: "mailto:alice@example.com")!
        XCTAssertEqual(WebWidgetNavigation.decide(url: page, isMainFrame: true, isLinkClick: false), .allow)
        XCTAssertEqual(WebWidgetNavigation.decide(url: page, isMainFrame: true, isLinkClick: true), .openInBrowser(page))
        XCTAssertEqual(WebWidgetNavigation.decide(url: mail, isMainFrame: true, isLinkClick: true), .cancel)
        XCTAssertEqual(WebWidgetNavigation.decide(url: URL(string: "file:///etc/hosts")!, isMainFrame: true, isLinkClick: false), .cancel)
        XCTAssertEqual(WebWidgetNavigation.decide(url: mail, isMainFrame: false, isLinkClick: false), .allow)
        XCTAssertEqual(WebWidgetNavigation.decide(url: mail, isMainFrame: false, isLinkClick: true), .cancel)
        XCTAssertEqual(WebWidgetNavigation.decide(url: page, isMainFrame: false, isLinkClick: true), .allow)
        XCTAssertEqual(WebWidgetNavigation.popup(url: page), .openInBrowser(page))
        XCTAssertEqual(WebWidgetNavigation.popup(url: mail), .cancel)
        XCTAssertEqual(WebWidgetNavigation.popup(url: nil), .cancel)
    }

    func testOneRowThatBarelyFitsGetsNoMoreLine() {
        XCTAssertEqual(SourceWidgetLayout.listFit(count: 5, height: 40, rowHeight: 30).rows, 1)
        XCTAssertEqual(SourceWidgetLayout.listFit(count: 5, height: 40, rowHeight: 30).more, 0)
        XCTAssertEqual(SourceWidgetLayout.listFit(count: 5, height: 90, rowHeight: 30).rows, 2)
        XCTAssertEqual(SourceWidgetLayout.listFit(count: 5, height: 90, rowHeight: 30).more, 3)
        XCTAssertEqual(SourceWidgetLayout.listFit(count: 3, height: 90, rowHeight: 30).rows, 3)
        XCTAssertEqual(SourceWidgetLayout.listFit(count: 3, height: 90, rowHeight: 30).more, 0)
    }

    func testOnlyStreamsScreensAndTailsFollowTheNewestLine() {
        XCTAssertTrue(SourceWidgetLayout.followsNewestLine(kind: "text", every: .continuous, tail: nil))
        XCTAssertTrue(SourceWidgetLayout.followsNewestLine(kind: "terminal", every: .interval(5), tail: nil))
        XCTAssertTrue(SourceWidgetLayout.followsNewestLine(kind: "text", every: .interval(60), tail: 50))
        XCTAssertFalse(SourceWidgetLayout.followsNewestLine(kind: "text", every: .interval(60), tail: nil))
        XCTAssertFalse(SourceWidgetLayout.followsNewestLine(kind: "text", every: .manual, tail: nil))
    }

    func testASparklineWithNoHistoryShowsTheCurrentValue() {
        let view = WidgetView(kind: "sparkline")
        XCTAssertEqual(SparklineWidgetView.latest(history: [], output: .number(7), view: view), 7)
        let history = [SparklinePoint(at: Date(timeIntervalSince1970: 0), value: 3)]
        XCTAssertEqual(SparklineWidgetView.latest(history: history, output: .number(7), view: view), 3)
        XCTAssertNil(SparklineWidgetView.latest(history: [], output: .text("busy"), view: view))
    }

    func testBlackTextShowsOnTheDarkCardAndABlackBackgroundStays() {
        XCTAssertEqual(ANSIPalette.foreground(.palette(0)), .palette(8))
        XCTAssertEqual(ANSIPalette.foreground(.palette(1)), .palette(1))
        XCTAssertEqual(ANSIPalette.rgb(.palette(0)).red, 0, accuracy: 0.001)
        let text = ANSIPalette.attributed(ANSIText.lines("\u{1B}[30;40mx"))
        let run = text.runs.first!
        XCTAssertEqual(run.foregroundColor, ANSIPalette.color(.palette(8)))
        XCTAssertEqual(run.backgroundColor, ANSIPalette.color(.palette(0)))
    }

    func testACompactErrorSaysWhatWentWrongAndNotOnlyTheTitle() throws {
        XCTAssertThrowsError(try ListModel.items(output: .text("plain"), template: ListItemTemplate())) { error in
            let state = SourceErrorPresentation.state(title: "This list cannot be shown", error: error)
            XCTAssertEqual(SourceErrorPresentation.compactDetail(state), "a list view needs lines or a JSON array")
        }
        XCTAssertThrowsError(try ValueExtraction.number(from: .text("busy"), view: WidgetView(kind: "number"))) { error in
            let state = SourceErrorPresentation.state(title: "This value cannot be shown", error: error)
            XCTAssertEqual(SourceErrorPresentation.compactDetail(state), "the output is \"busy\", not a number")
        }
        XCTAssertThrowsError(try StatusModel.make(output: .json(.list([])), view: statusView(value: "{{json.state}}"))) { error in
            let detail = SourceErrorPresentation.compactDetail(
                SourceErrorPresentation.state(title: "This value cannot be shown", error: error))
            XCTAssertEqual(detail, "{{json.state}} found nothing in the answer")
        }
        let timeout = SourceErrorPresentation.state(.timedOut(30))
        XCTAssertEqual(SourceErrorPresentation.compactDetail(timeout), "The machine took too long to answer.")
        let exited = SourceErrorPresentation.state(.exited(status: 2, stderr: "no such file"))
        XCTAssertEqual(SourceErrorPresentation.compactDetail(exited), "no such file")
    }

    func testOnlyALargeFrameGetsTheFullLayout() {
        let full = WidgetContract.presetOrder.filter { preset in
            let size = CanvasLayout.presetSize(preset)!
            return WidgetDensity.of(width: Double(size.w), height: Double(size.h)) == .full
        }
        XCTAssertEqual(full, ["large"])
    }

    @MainActor
    func testEveryValueViewFitsEveryPreset() {
        let cases: [(String, WidgetView, SourceWidgetState)] = [
            ("number", view("number", unit: "req/s"), state(.number(5182.25))),
            ("gauge", view("gauge", unit: "%"), state(.number(73))),
            ("status", view("status"), state(.status(code: 200, latency: 0.042))),
            ("sparkline", view("sparkline"), state(.number(12))),
            ("list", listView(), state(.lines((1...20).map { "deploy \($0) finished on main" }))),
            ("text", view("text"), state(.text((1...40).map { "line \($0) of a long log" }.joined(separator: "\n")))),
            ("terminal", view("terminal"), state(.ansi("\u{1B}[32malice@main\u{1B}[0m:~$ ls\nREADME.md"))),
            ("markdown", view("markdown"), state(.text("# Notes\n\n- one\n- two\n- three"))),
        ]
        for (name, widgetView, widgetState) in cases {
            assertFitsEveryPreset(name, view: widgetView, state: widgetState)
        }
    }

    @MainActor
    func testAWebWidgetWhoseAddressIsNotAWebPageShowsTheErrorAndFits() {
        let source = ResolvedSource(
            source: .url(URLSource(url: "{{inputs.host}}", every: .interval(60), timeout: 30, parse: .status)),
            view: WidgetView(kind: "web"), every: .interval(60), needsApproval: false, package: "mine", packagePath: nil)
        for preset in WidgetContract.presetOrder {
            let size = CanvasLayout.presetSize(preset)!
            let result = DMFitCheck.render(width: CGFloat(size.w), scale: 1) {
                SourceWidgetContent(
                    title: "Status page", source: source, state: SourceWidgetState(), history: [],
                    size: CGSize(width: size.w, height: size.h), onRun: {},
                    webAddress: .failure(.unreadable("file:///etc/hosts is not a web address")))
            }
            XCTAssertEqual(result.spilledPixels, 0, "web error spills out of \(preset)")
        }
    }

    @MainActor
    func testEveryEmptyAndErrorStateFitsEveryPreset() {
        var failed = SourceWidgetState()
        failed.error = .exited(status: 2, stderr: "error: alice has no such file\nsecond line of stderr")
        var stale = state(.number(42))
        stale.error = .timedOut(30)
        var older = SourceWidgetState()
        older.error = .needsNewerCLI("Error: unknown flag: --argv")
        assertFitsEveryPreset("error", view: view("number"), state: failed)
        assertFitsEveryPreset("stale value", view: view("number"), state: stale)
        assertFitsEveryPreset("older CLI", view: view("number"), state: older)
        assertFitsEveryPreset("waiting", view: view("number"), state: SourceWidgetState(), every: .manual)
        assertFitsEveryPreset("bad value", view: view("number"), state: state(.text("not a number at all")))
    }

    @MainActor
    private func assertFitsEveryPreset(
        _ name: String, view: WidgetView, state: SourceWidgetState, every: WidgetEvery = .interval(60),
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let source = ResolvedSource(
            source: .command(CommandSource(
                run: "uptime", script: nil, args: [], shell: false, target: .local, every: every, timeout: 30,
                mode: .poll, keep: 200, parse: .text)),
            view: view, every: every, needsApproval: false, package: nil, packagePath: nil)
        let history = (0..<30).map { SparklinePoint(at: Date(timeIntervalSince1970: Double($0)), value: Double($0 % 7)) }
        for preset in WidgetContract.presetOrder {
            let size = CanvasLayout.presetSize(preset)!
            let result = DMFitCheck.render(width: CGFloat(size.w), scale: 1) {
                SourceWidgetContent(
                    title: "Widget on main", source: source, state: state, history: history,
                    size: CGSize(width: size.w, height: size.h), onRun: {})
            }
            XCTAssertEqual(result.spilledPixels, 0, "\(name) spills out of \(preset)", file: file, line: line)
            XCTAssertEqual(result.size.height, CGFloat(size.h), accuracy: 1, "\(name) height in \(preset)",
                           file: file, line: line)
        }
    }

    private func view(_ kind: String, unit: String? = nil) -> WidgetView {
        var view = WidgetView(kind: kind)
        view.unit = unit
        return view
    }

    private func statusView(value: String) -> WidgetView {
        var view = WidgetView(kind: "status")
        view.value = value
        return view
    }

    private func listView() -> WidgetView {
        var view = WidgetView(kind: "list")
        view.item = ListItemTemplate(title: "{{item}}", subtitle: "on main", status: "ok")
        return view
    }

    private func state(_ output: SourceOutput) -> SourceWidgetState {
        var state = SourceWidgetState()
        state.output = output
        return state
    }

    @MainActor
    func testColouredOutputIsParsedOncePerNewOutput() {
        var renders = 0
        let cache = ANSIRenderCache { lines in
            renders += 1
            return AttributedString(lines.joined(separator: "\n"))
        }
        XCTAssertEqual(String(cache.text(for: ["a", "b"]).characters), "a\nb")
        _ = cache.text(for: ["a", "b"])
        XCTAssertEqual(renders, 1)
        XCTAssertEqual(String(cache.text(for: ["c"]).characters), "c")
        XCTAssertEqual(renders, 2)
    }

    func testASessionWidgetOpensTheSessionItNames() {
        let workspaces = [Workspace(name: "alice", alias: "alice-devmachine")]
        let local = [LocalSession(handle: "shell-1", name: "Shell", path: "/Users/alice")]
        XCTAssertEqual(
            SessionOpening.item(target: .workspace("alice"), session: "main", workspaces: workspaces, localSessions: local),
            .session(alias: "alice-devmachine", name: "main"))
        XCTAssertEqual(
            SessionOpening.item(target: .local, session: "shell-1", workspaces: workspaces, localSessions: local),
            .localSession(name: "shell-1", path: "/Users/alice"))
        XCTAssertNil(SessionOpening.item(target: .local, session: "gone", workspaces: workspaces, localSessions: local))
        XCTAssertNil(SessionOpening.item(target: .workspace("bob"), session: "main", workspaces: workspaces, localSessions: local))
        XCTAssertNil(SessionOpening.item(target: .machine("main"), session: "main", workspaces: workspaces, localSessions: local))
    }

    func testTheApprovalCardShowsUntilAllowedAndNeverForWidgetsThatNeedNone() {
        func mode(_ approval: ApprovalState, needs: Bool = true, demo: Bool = false, view: String = "text") -> SourceWidgetCardMode {
            SourceWidgetCardMode.of(approval: approval, needsApproval: needs, isDemo: demo, viewKind: view)
        }
        XCTAssertEqual(mode(.waiting(hash: "h")), .approval)
        XCTAssertEqual(mode(.denied(hash: "h")), .approval)
        XCTAssertEqual(mode(.allowed), .content)
        XCTAssertEqual(mode(.notNeeded, needs: false), .content)
        XCTAssertEqual(mode(.notNeeded, needs: false, demo: true), .demo)
        XCTAssertEqual(mode(.notNeeded, needs: false, demo: true, view: "web"), .content)
        XCTAssertEqual(mode(.waiting(hash: "h"), demo: true), .approval)
    }

    func testAnInlineWidgetTheControllerHasNotSeenYetShowsTheCardNotItsContent() {
        XCTAssertEqual(SourceWidgetCardMode.of(approval: .notNeeded, needsApproval: true, isDemo: false, viewKind: "text"), .approval)
    }

    func testTheApprovalCardSaysWhatRunsWhereAndHowOften() {
        let source = ResolvedSource(
            source: .session(SessionSource(target: .workspace("alice"), session: "main", every: .interval(10))),
            view: WidgetView(kind: "terminal"), every: .interval(10), needsApproval: true, package: nil, packagePath: nil)
        XCTAssertEqual(WidgetApprovalText.headline(kind: "session", denied: false), "Allow this session widget to run?")
        XCTAssertEqual(WidgetApprovalText.headline(kind: "command", denied: true), "Paused: you denied this command widget")
        XCTAssertEqual(WidgetApprovalText.whereAndWhen(ApprovalPrompt(source, context: [:])), "Runs in workspace alice, every 10s.")
        let command = WidgetSource.command(CommandSource(
            run: "tail", script: nil, args: ["-n", "50", "/var/log/system log"], shell: false, target: .local,
            every: .interval(60), timeout: 30, mode: .poll, keep: 200, parse: .text))
        XCTAssertEqual(ApprovalCopy.what(command), "tail -n 50 '/var/log/system log'")
        let script = WidgetSource.command(CommandSource(
            run: nil, script: "scripts/disk.sh", args: ["--all"], shell: false, target: .local,
            every: .interval(60), timeout: 30, mode: .poll, keep: 200, parse: .text))
        XCTAssertEqual(ApprovalCopy.what(script), "scripts/disk.sh --all")
    }

    func testTheCardNamesAThirdPartySourceAndAPackageProvider() {
        let provider = WidgetSource.packageProvider(PackageProviderSource(
            name: "acme-tools/load", with: [:], target: .machine("main"), every: .interval(30), timeout: 30))
        XCTAssertEqual(WidgetApprovalText.kind(provider), "package provider")
        XCTAssertEqual(WidgetApprovalText.headline(kind: WidgetApprovalText.kind(provider), denied: false),
                       "Allow this package provider widget to run?")
        let command = WidgetSource.command(CommandSource(
            run: "df", script: nil, args: [], shell: false, target: .local, every: .interval(60), timeout: 30,
            mode: .poll, keep: 200, parse: .text))
        XCTAssertEqual(WidgetApprovalText.kind(command), "command")
        XCTAssertEqual(WidgetApprovalText.thirdParty(url: "https://example.com/acme/acme-tools.git"),
                       "From a third-party package: https://example.com/acme/acme-tools.git")
        XCTAssertEqual(WidgetApprovalText.thirdParty(url: ""), "From a third-party package.")
    }

    @MainActor
    func testTheThirdPartyCardFitsAtTheSmallSize() throws {
        let small = try XCTUnwrap(CanvasLayout.presetSize("small"))
        let resolved = ResolvedSource(
            source: .packageProvider(PackageProviderSource(
                name: "acme-tools/load", with: ["window": "5m"], target: .machine("main"), every: .interval(30), timeout: 30)),
            view: WidgetView(kind: "number"), every: .interval(30), needsApproval: true, package: "acme-tools",
            packagePath: nil, trust: .thirdParty, packageCommit: String(repeating: "1", count: 40),
            packageSourceURL: "https://example.com/acme/a-very-long-path/that-keeps-going/acme-tools.git")
        let prompt = ApprovalPrompt(resolved, context: [:])
        for scale in DMFitCheck.scales {
            let m = DMMetrics(scale: scale)
            let size = CGSize(width: m.pt(CGFloat(small.w)), height: m.pt(CGFloat(small.h)))
            let result = DMFitCheck.render(width: CGFloat(small.w), scale: scale) {
                WidgetApprovalCard(
                    kind: WidgetApprovalText.kind(resolved.source), prompt: prompt, state: .waiting(hash: "h"),
                    surface: "home", size: size, onAllow: {}, onDeny: {})
            }
            XCTAssertEqual(result.spilledPixels, 0, "the card spills out at \(scale)")
        }
    }
}
