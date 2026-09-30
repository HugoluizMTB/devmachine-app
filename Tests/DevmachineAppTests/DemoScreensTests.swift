import XCTest
import DevmachineCore
import HarnessUsageKit
@testable import DevmachineApp

@MainActor
final class DemoScreensTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("DEVMACHINE_DEMO", "1", 1)
    }

    override func tearDown() {
        unsetenv("DEVMACHINE_DEMO")
        super.tearDown()
    }

    func testDemoWallpaperIsAGeneratedGradientNotAPhoto() {
        guard case .gradient = DemoData.settings.wallpaper else {
            return XCTFail("the demo must never show a photo wallpaper")
        }
    }

    func testDemoWallpaperIsTheGeneratedLandscape() {
        XCTAssertEqual(DemoData.settings.wallpaper, .gradient(name: "peaks"))
    }

    func testDemoClaudeUsageListsThreeModelsAndTheMostUsedOne() throws {
        let claude = try XCTUnwrap(DemoData.usageProviders.first { $0.harnessID == "claude" } as? DemoUsageProvider)
        let stats = try XCTUnwrap(claude.snapshot.stats)
        XCTAssertEqual(stats.modelTotals.map(\.model), ["claude-sonnet", "claude-opus", "claude-haiku"])
        XCTAssertEqual(stats.mostUsedModel, "claude-sonnet")
    }

    func testTheCertificateWarningSaysWhenTheNextRunIs() {
        let details = DemoData.machineHealth.flatMap(\.checks).map(\.detail)
        XCTAssertTrue(details.contains("renews in 6 days, next run in 4h"))
    }

    func testDemoSettingsRaiseNoIssueAlthoughTheFolderIsInvented() {
        XCTAssertEqual(SetupPage.issues(for: DemoData.settings, demo: true), [])
    }

    func testOutsideDemoAMissingFolderIsStillReported() {
        let fields = SetupPage.issues(for: DemoData.settings, demo: false).map(\.field)
        XCTAssertTrue(fields.contains(.opsRepoPath))
    }

    func testOperatorOpensInTheDevmachineFolder() {
        let operatorSession = DemoData.localSessions.first { $0.name == Workspace.operatorSession }
        XCTAssertEqual(operatorSession?.path, "/Users/alice/.config/devmachine")
        XCTAssertEqual(DemoData.settings.opsRepoPath, "/Users/alice/.config/devmachine")
    }

    func testOperatorTranscriptAddsAndSyncsGlobex() {
        let transcript = DemoData.terminalTranscript(
            for: .local(session: Workspace.operatorSession, path: DemoData.operatorPath))
        XCTAssertTrue(transcript.contains("Add a workspace globex"))
        XCTAssertTrue(transcript.contains("devmachine workspaces new globex"))
        XCTAssertTrue(transcript.contains("devmachine packages add claude-code --workspace globex"))
        XCTAssertTrue(transcript.contains("changed=12"))
        XCTAssertTrue(transcript.contains("failed=0"))
    }

    func testOperatorContextFollowsTheGlobexChange() {
        let state = DemoData.contextState(
            for: .local(session: Workspace.operatorSession, path: DemoData.operatorPath))
        XCTAssertEqual(state?.cwd, DemoData.operatorPath)
        XCTAssertEqual(state?.plan?.title, "Add the globex workspace")
        XCTAssertEqual(DemoData.contextState(for: .remote(alias: "acme-devmachine", session: "claude"))?.cwd,
                       "/Users/alice/dev/acme-app")
    }

    func testTheDemoContextShowsEveryPullRequestStateAndSeveralLinkKinds() {
        let state = DemoData.contextState
        XCTAssertEqual(Set(state.prs.map(\.rowState.kind)), Set(PRStateKind.allCases))
        XCTAssertGreaterThanOrEqual(Set(state.links.map(\.kind)).count, 3)
    }

    func testDemoLocalSessionsKnowTheirHarnessSoTheContextPanelFills() {
        let model = AppModel(cliAvailabilityCheck: { false })
        model.checkCLIAndProceed(isConfigured: true)

        let socketDirectory = Zmx.socketDirectory()
        let operatorName = Zmx.sessionName(from: Workspace.operatorSession, socketDirectory: socketDirectory)
        let codexName = Zmx.sessionName(from: "codex", socketDirectory: socketDirectory)
        XCTAssertEqual(model.localSessionHarnesses[operatorName], [.claude])
        XCTAssertEqual(model.localSessionHarnesses[codexName], [.codex])
    }

    func testUsageResetTextIsNotPrefixedTwice() throws {
        for provider in DemoData.usageProviders {
            let snapshot = try provider.fetchSnapshot(previous: nil)
            for block in snapshot.blocks {
                XCTAssertFalse(block.resets.hasPrefix("resets"), block.resets)
            }
        }
    }

    func testTheDemoUsageErrorFailsOnlyTheNamedHarness() throws {
        let providers = DemoData.usageProviders(failing: ["codex"])
        let codex = try XCTUnwrap(providers.first { $0.harnessID == "codex" })
        let claude = try XCTUnwrap(providers.first { $0.harnessID == "claude" })

        XCTAssertThrowsError(try codex.fetchSnapshot(previous: nil)) { error in
            XCTAssertEqual(HarnessUsageErrorKind(error: error), .notSignedIn)
        }
        XCTAssertNoThrow(try claude.fetchSnapshot(previous: nil))
    }

    func testTheDemoUsageErrorIsOffUnlessAsked() {
        XCTAssertEqual(DemoData.failingUsageHarnesses(from: [:]), [])
        XCTAssertEqual(
            DemoData.failingUsageHarnesses(from: ["DEVMACHINE_DEMO_USAGE_ERROR": "codex, claude"]),
            ["codex", "claude"])
    }

    func testTheDemoBackupMachineHasNoDocker() throws {
        let backup = try XCTUnwrap(DemoData.statsSnapshots["backup"])
        let main = try XCTUnwrap(DemoData.statsSnapshots["main"])

        XCTAssertFalse(backup.docker.available)
        XCTAssertTrue(main.docker.available)
    }

    func testTheDemoStatsMachineIsMainUnlessAnotherDemoMachineIsAsked() {
        XCTAssertEqual(DemoData.statsMachine(from: [:]), "main")
        XCTAssertEqual(DemoData.statsMachine(from: ["DEVMACHINE_DEMO_STATS_MACHINE": "backup"]), "backup")
        XCTAssertEqual(DemoData.statsMachine(from: ["DEVMACHINE_DEMO_STATS_MACHINE": "nowhere"]), "main")
    }

    func testDemoShortcutsAreInventedAndIgnoreSavedOnes() throws {
        let suiteName = "\(#function)-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let saved = [SkillCommand(label: "private", command: "/private", systemImage: "star")]
        defaults.set(try JSONEncoder().encode(saved), forKey: "skillShortcuts")

        let store = SkillsStore(defaults: defaults)

        XCTAssertEqual(store.skills.map(\.label), DemoData.skills.map(\.label))
        XCTAssertTrue(Set(store.skills.map(\.label)).isDisjoint(with: SkillsStore.defaultSkills.map(\.label)))
    }

    func testATranscriptDropsTheScrollbackSoAReplayNeverStacksCopies() {
        let transcript = DemoData.terminalTranscript(for: .remote(alias: "acme-devmachine", session: "claude"))
        XCTAssertTrue(transcript.hasPrefix("\u{1B}[H\u{1B}[2J\u{1B}[3J"))
    }

    func testEveryTranscriptFitsAStackedGridCell() {
        let kinds: [TerminalKind] = DemoData.sessionsByAlias.flatMap { alias, sessions in
            sessions.map { TerminalKind.remote(alias: alias, session: $0.name) }
        } + DemoData.localSessions.map { .local(session: $0.name, path: $0.path) }
        for kind in kinds {
            let lines = DemoData.terminalTranscript(for: kind).components(separatedBy: "\r\n")
            XCTAssertLessThanOrEqual(lines.count, 24, "\(kind)")
        }
    }

    func testReplayingTranscriptsRedrawsAnEmptiedPane() {
        let kind = TerminalKind.remote(alias: "globex-devmachine", session: "claude-replay-test")
        let term = TerminalRegistry.shared.terminal(for: kind)
        defer { TerminalRegistry.shared.close(kind) }
        term.feed(text: "\u{1B}[2J\u{1B}[H")

        TerminalRegistry.shared.replayDemoTranscripts()

        let screen = String(decoding: term.getBufferAsData(), as: UTF8.self)
        XCTAssertTrue(screen.contains("Claude Code"), screen)
    }

    func testATypedPromptFollowsTheSessionsTranscript() {
        let kind = TerminalKind.remote(alias: "acme-devmachine", session: "claude")
        let plain = DemoData.terminalTranscript(for: kind)
        DemoData.typedAtPrompt = [kind: "look at /tmp/a.png"]
        defer { DemoData.typedAtPrompt = [:] }
        let typed = DemoData.terminalTranscript(for: kind)
        XCTAssertTrue(typed.hasPrefix(plain))
        XCTAssertTrue(typed.hasSuffix(" look at /tmp/a.png"))
    }

    func testOtherSessionsKeepTheirTranscriptWhileOneHasATypedPrompt() {
        let other = TerminalKind.remote(alias: "globex-devmachine", session: "claude")
        let plain = DemoData.terminalTranscript(for: other)
        DemoData.typedAtPrompt = [.remote(alias: "acme-devmachine", session: "claude"): "x"]
        defer { DemoData.typedAtPrompt = [:] }
        XCTAssertEqual(DemoData.terminalTranscript(for: other), plain)
    }
}
