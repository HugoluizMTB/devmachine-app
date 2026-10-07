import XCTest
import DevmachineCore
@testable import DevmachineApp

@MainActor
final class CommandRegistryTests: XCTestCase {
    private let acme = Workspace(name: "acme", alias: "acme-devmachine")
    private let beta = Workspace(name: "beta", alias: "beta-devmachine")

    private func context(
        workspaces: [Workspace]? = nil,
        machines: [String] = ["main"],
        hasCaddyMachine: Bool = true,
        currentTerminal: TerminalKind? = nil,
        currentWorkspaceAlias: String? = nil
    ) -> PaletteContext {
        var context = PaletteContext()
        context.workspaces = workspaces ?? [acme, beta]
        context.localSessions = [
            LocalSession(name: Workspace.operatorSession, path: "/Users/alice/dev/ops"),
            LocalSession(name: "notes", path: "/Users/alice/notes"),
        ]
        context.launchOptions = [
            .terminal,
            HarnessLaunchOption(
                choice: .harness(.claude),
                descriptor: HarnessRegistry.builtIn.adapter(for: .claude)?.descriptor),
        ]
        context.savedCommands = ["acme-devmachine": ["npm run dev"]]
        context.machines = machines
        context.hasCaddyMachine = hasCaddyMachine
        context.subdomainsMachine = machines.first
        context.currentTerminal = currentTerminal
        context.currentWorkspaceAlias = currentWorkspaceAlias
        return context
    }

    private func commands(_ context: PaletteContext) -> [PaletteCommand] {
        CommandRegistry.commands(in: context)
    }

    private func command(_ id: String, in context: PaletteContext) -> PaletteCommand? {
        commands(context).first { $0.id == id }
    }

    func testAHarnessNotOnThisMacStartsOnlyOnARemoteWorkspace() {
        var context = context()
        let opencode = HarnessLaunchOption(
            choice: .harness(.opencode), descriptor: HarnessRegistry.builtIn.adapter(for: .opencode)?.descriptor)
        context.localLaunchOptions = context.launchOptions
        context.launchOptions.append(opencode)

        XCTAssertNotNil(command("ws.acme-devmachine.new.opencode", in: context))
        XCTAssertNil(command("ws.\(Workspace.local.alias).new.opencode", in: context))
        XCTAssertNotNil(command("ws.\(Workspace.local.alias).new.claude", in: context))
    }

    func testEveryCommandIDIsUnique() {
        let ids = commands(context()).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testTheScreensAreAlwaysThere() {
        let ids = Set(commands(context()).map(\.id))
        for id in ["go.home", "go.stats", "go.settings", "go.health", "go.shortcuts", "go.operator"] {
            XCTAssertTrue(ids.contains(id), id)
        }
    }

    func testWorkspacesHasAPageAndANewWorkspaceCommand() throws {
        let all = commands(context())
        let page = try XCTUnwrap(all.first { $0.id == "go.workspaces" })
        XCTAssertEqual(page.title, "Workspaces…")
        XCTAssertEqual(page.action, .openSettings(.workspaces))
        let new = try XCTUnwrap(all.first { $0.id == "action.new-workspace" })
        XCTAssertEqual(new.title, "New workspace…")
        XCTAssertEqual(new.action, .newWorkspace)
    }

    func testTheOperatorSessionOpensTheLocalOperatorShell() {
        let operatorCommand = command("go.operator", in: context())
        XCTAssertEqual(
            operatorCommand?.action,
            .openSession(.localSession(name: "Operator", path: "/Users/alice/dev/ops")))
    }

    func testEverySettingsPaneHasACommand() {
        let panes = commands(context())
            .compactMap { command -> SettingsSection? in
                if case let .openSettings(section) = command.action, command.category == .settings {
                    return section
                }
                return nil
            }
        XCTAssertEqual(Set(panes), Set(SettingsSection.allCases))
    }

    func testThePackagesCommandOpensItsSettingsPane() {
        let packages = command("settings.packages", in: context())
        XCTAssertEqual(packages?.title, "Packages")
        XCTAssertEqual(packages?.action, .openSettings(.packages))
    }

    func testNoSubdomainCommandsWithoutACaddyMachine() {
        let all = commands(context(hasCaddyMachine: false))
        XCTAssertFalse(all.contains { command in
            switch command.action {
            case .showPage(.subdomains), .subdomains, .addSubdomain, .publishPort: return true
            default: return false
            }
        })
    }

    func testNoMachineCommandsWithoutARemoteMachine() {
        let all = commands(context(machines: []))
        XCTAssertFalse(all.contains { $0.category == .machine && $0.id != "machine.health" })
        XCTAssertFalse(all.contains { if case .addSubdomain = $0.action { return true } else { return false } })
    }

    func testEachMachineGetsStatsAndSubdomainCommands() {
        let all = commands(context(machines: ["main", "staging"]))
        let actions = all.map(\.action)
        for machine in ["main", "staging"] {
            XCTAssertTrue(actions.contains(.stats(machine: machine)))
            XCTAssertTrue(actions.contains(.subdomains(machine: machine)))
            XCTAssertTrue(actions.contains(.addSubdomain(machine: machine)))
        }
    }

    func testEachWorkspaceGetsANewSessionPerLaunchOption() {
        let actions = commands(context()).map(\.action)
        for alias in ["acme-devmachine", "beta-devmachine", "local"] {
            XCTAssertTrue(actions.contains(.newSession(alias: alias, choice: .terminal)), alias)
            XCTAssertTrue(actions.contains(.newSession(alias: alias, choice: .harness(.claude))), alias)
            XCTAssertTrue(actions.contains(.customCommand(alias: alias)), alias)
        }
    }

    func testSavedCommandsBecomeCommandsOfTheirWorkspaceOnly() {
        let actions = commands(context()).map(\.action)
        XCTAssertTrue(actions.contains(.runSavedCommand(alias: "acme-devmachine", command: "npm run dev")))
        XCTAssertFalse(actions.contains(.runSavedCommand(alias: "beta-devmachine", command: "npm run dev")))
    }

    func testRemoteWorkspacesPublishAPortAndOpenFilesButTheLocalOneDoesNot() {
        let actions = commands(context()).map(\.action)
        XCTAssertTrue(actions.contains(.publishPort(workspace: "acme")))
        XCTAssertTrue(actions.contains(.openFiles(alias: "acme-devmachine")))
        XCTAssertFalse(actions.contains(.openFiles(alias: "local")))
    }

    func testLocalSessionsCanBeRevealedInFinder() {
        let actions = commands(context()).map(\.action)
        XCTAssertTrue(actions.contains(.revealInFinder(path: "/Users/alice/notes")))
    }

    func testSendingAFileNeedsACurrentSession() {
        XCTAssertNil(command("action.send-file", in: context()))
        let kind = TerminalKind.remote(alias: "acme-devmachine", session: "dash")
        XCTAssertEqual(command("action.send-file", in: context(currentTerminal: kind))?.action, .sendFile(kind))
    }

    func testEndingASessionNeedsASingleSessionOnScreen() {
        XCTAssertNil(command("action.end-session", in: context()))
        var single = context()
        single.endableSession = .session(alias: "acme-devmachine", name: "dash")
        let end = command("action.end-session", in: single)
        XCTAssertEqual(end?.title, "End session…")
        XCTAssertEqual(end?.shortcut, "⌘W")
        XCTAssertEqual(end?.action, .endSession)
    }

    func testPublishAPortPicksTheCurrentRemoteWorkspace() {
        XCTAssertNil(command("action.publish-port", in: context()))
        let current = context(currentWorkspaceAlias: "beta-devmachine")
        XCTAssertEqual(command("action.publish-port", in: current)?.action, .publishPort(workspace: "beta"))
        XCTAssertNil(command("action.publish-port", in: context(currentWorkspaceAlias: "local")))
    }

    func testAddSubdomainPicksTheSelectedSubdomainsMachine() {
        var current = context(machines: ["main", "staging"])
        current.subdomainsMachine = "staging"
        XCTAssertEqual(command("action.add-subdomain", in: current)?.action, .addSubdomain(machine: "staging"))
    }

    func testSessionsBecomeSessionCommands() {
        var current = context()
        current.sessions = [PaletteItem(
            id: "acme-devmachine/dash", title: "dash", subtitle: "acme",
            target: .session(alias: "acme-devmachine", name: "dash"), badges: [])]
        let session = command("session.acme-devmachine/dash", in: current)
        XCTAssertEqual(session?.category, .session)
        XCTAssertEqual(session?.action, .openSession(.session(alias: "acme-devmachine", name: "dash")))
    }

    func testSynonymsReachTheirScreens() {
        let all = commands(context())
        func top(_ query: String) -> String? {
            PaletteRanker.sections(all, query: query, mru: CommandMRU(ids: []))
                .first?.commands.first?.id
        }
        XCTAssertEqual(top("dns"), "go.subdomains")
        XCTAssertEqual(top("caddy"), "go.subdomains")
        XCTAssertEqual(top("ram"), "go.stats")
        XCTAssertEqual(top("prefs"), "go.settings")
    }

    func testCheckForUpdatesIsAlwaysThere() {
        let command = commands(context()).first { $0.id == "action.check-updates" }
        XCTAssertEqual(command?.title, "Check for Updates…")
        XCTAssertEqual(command?.action, .checkForUpdates)
    }

    func testPickAColorIsAlwaysThereAndFoundByItsKeywords() {
        let all = commands(context())
        let command = all.first { $0.id == "action.pick-color" }
        XCTAssertEqual(command?.title, "Pick a color from the screen")
        XCTAssertEqual(command?.action, .pickColor)
        let top = PaletteRanker.sections(all, query: "eyedropper", mru: CommandMRU(ids: []))
            .first?.commands.first?.id
        XCTAssertEqual(top, "action.pick-color")
    }

    func testTheCLIUpdateCommandShowsOnlyWhenThereIsOne() {
        XCTAssertNil(commands(context()).first { $0.id == "action.update-cli" })

        var withNotice = context()
        withNotice.cliUpdate = CLIUpdateNotice(
            installed: SemanticVersion("0.7.1")!, latest: SemanticVersion("0.8.0")!,
            command: "brew upgrade devmachine", releaseURL: nil)
        let command = commands(withNotice).first { $0.id == "action.update-cli" }
        XCTAssertEqual(command?.title, "Update the devmachine CLI")
        XCTAssertEqual(command?.badgeText, "0.8.0")
        XCTAssertEqual(command?.action, .openSettings(.about))
    }

    func testAddingAWidgetIsAlwaysOffered() {
        let command = CommandRegistry.commands(in: context()).first { $0.id == "action.add-widget" }
        XCTAssertEqual(command?.title, "Add a widget to Home…")
        XCTAssertEqual(command?.action, .addWidget)
    }
}
