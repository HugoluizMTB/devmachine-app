import XCTest
import DevmachineCore
@testable import DevmachineApp

/// Runs every command in the background and records it; nothing reaches a
/// CLI, a terminal or a machine.
@MainActor
private final class FakeCLI {
    var commands: [[String]] = []
    var status: ([String]) -> Int32 = { _ in 0 }
    var output: ([String]) -> String = { "ok: \($0.joined(separator: " "))" }

    var hooks: MachineStepRunner.Hooks {
        MachineStepRunner.Hooks(
            executable: { "/opt/homebrew/bin/devmachine" },
            isReady: { _ in true },
            type: { _, _ in XCTFail("a workspace run typed into a terminal") },
            matchCount: { _, _ in 0 },
            writeScript: { _, _ in
                XCTFail("a workspace run wrote a terminal script")
                return "/tmp/x.sh"
            },
            isAtPrompt: { _ in nil },
            runProcess: { arguments, input, output in
                XCTAssertNil(input)
                self.commands.append(arguments)
                output(self.output(arguments))
                return self.status(arguments)
            },
            beginTask: { _, _ in nil }, setTask: { _, _ in }, endTask: { _, _ in })
    }
}

@MainActor
final class WorkspacesStoreTests: XCTestCase {
    private let acme = WorkspaceSummary(
        name: "acme", machine: "main", user: "acme", packages: ["dev", "zsh"], settings: ["zsh.theme": "clean"])
    private let gamma = WorkspaceSummary(name: "gamma", machine: "staging", user: "gamma", packages: ["pi"])

    private func machines() -> MachinesStore {
        let snapshot = MachinesSnapshot(
            hasConfiguration: true,
            machines: [
                ConfiguredMachine(name: "main", hosts: ["203.0.113.10"], adminUser: "root", port: 22,
                                  workspaces: ["acme"], packages: ["essentials"], isSelf: false),
                ConfiguredMachine(name: "staging", hosts: ["203.0.113.12"], adminUser: "deploy", port: 22,
                                  workspaces: ["gamma"], packages: [], isSelf: false),
                ConfiguredMachine(name: "laptop", hosts: [], adminUser: "", port: 0,
                                  workspaces: [], packages: [], isSelf: true),
            ],
            packages: [
                CLIPackage(name: "workspace", scope: "workspace", installedOn: [], category: "Foundation"),
                CLIPackage(name: "dev", scope: "workspace", installedOn: ["workspace acme"], category: "Foundation"),
                CLIPackage(name: "zsh", scope: "workspace", installedOn: ["workspace acme"], category: "Foundation"),
                CLIPackage(name: "mise", scope: "workspace", installedOn: [], category: "Foundation"),
                CLIPackage(
                    name: "pi", scope: "workspace", installedOn: [], category: "Coding agents",
                    credentials: [PackageCredential(name: "pi", kind: "file", scope: "workspace")],
                    variables: [PackageVariable(name: "port", summary: "", default: .int(3000), type: .number)]),
                CLIPackage(name: "claude-code", scope: "workspace", installedOn: [], category: "Coding agents"),
                CLIPackage(name: "docker", scope: "machine", installedOn: ["machine main"]),
            ])
        let store = MachinesStore(read: { snapshot }, remove: { _ in })
        store.seedDemo(snapshot)
        return store
    }

    private func makeStore(
        cli: FakeCLI, reads: WorkspaceReadTally = WorkspaceReadTally(), changed: WorkspaceChangeTally = WorkspaceChangeTally(),
        lock: PackagesLock? = PackagesLock(machines: [:], workspaces: ["acme": [.init(name: "dev"), .init(name: "zsh")]]),
        harnessesOn: [HarnessID] = [.pi],
        defaults: [String]? = nil, sharing: [String: String] = [:]
    ) -> WorkspacesStore {
        let workspaces = [acme, gamma]
        return WorkspacesStore(
            machines: machines(),
            runner: MachineStepRunner(hooks: cli.hooks, pollInterval: 1_000_000),
            read: {
                await reads.bump()
                return WorkspacesSnapshot(
                    workspaces: workspaces, lock: lock, defaults: defaults, sharing: sharing,
                    reportsSharing: defaults != nil)
            },
            loadMachines: false,
            codingAgents: { available in
                CodingAgentPackages.choose(
                    harnesses: [(.claude, "claude-code"), (.pi, "pi")], enabled: harnessesOn, available: available)
            },
            onChanged: { changed.value += 1 })
    }

    func testTheListGroupsByMachineAndSaysWhatTheLastSyncApplied() async {
        let store = makeStore(cli: FakeCLI())
        await store.load()

        XCTAssertEqual(store.groups.map(\.machine), ["main", "staging"])
        XCTAssertEqual(store.groups.map { $0.workspaces.map(\.name) }, [["acme"], ["gamma"]])
        XCTAssertEqual(store.syncState(acme), .applied)
        XCTAssertEqual(store.syncState(gamma), .neverSynced)
    }

    func testNewOffersOnlyMachinesThatAreNotThisMacAndPreselectsTheCLIDefaults() async {
        let store = makeStore(cli: FakeCLI())
        await store.load()
        await store.startNew()

        let flow = try? XCTUnwrap(store.flow)
        XCTAssertEqual(flow?.machines.map(\.name), ["main", "staging"])
        XCTAssertEqual(flow?.draft.packages, ["dev", "zsh", "mise"])
        XCTAssertEqual(flow?.existingWorkspaces, ["acme", "gamma"])
        XCTAssertEqual(store.packageCards.map(\.name), ["workspace", "dev", "mise", "zsh", "pi"])
        XCTAssertFalse(store.packageCards.contains { $0.name == "claude-code" }, "claude is off")
    }

    func testTheCodingAgentsOfferedAreOnlyTheHarnessesTurnedOn() async {
        let store = makeStore(cli: FakeCLI(), harnessesOn: [.claude])
        await store.load()
        await store.startNew()
        XCTAssertTrue(store.packageCards.contains { $0.name == "claude-code" })
        XCTAssertFalse(store.packageCards.contains { $0.name == "pi" })
        XCTAssertFalse(store.noCodingAgentOn)
    }

    func testNoHarnessOnOffersNoAgentAndSaysSo() async {
        let store = makeStore(cli: FakeCLI(), harnessesOn: [])
        await store.load()
        await store.startNew()
        XCTAssertEqual(store.packageCards.map(\.name), ["workspace", "dev", "mise", "zsh"])
        XCTAssertTrue(store.noCodingAgentOn)
    }

    func testEditKeepsAnAgentTheWorkspaceHasEvenWithItsHarnessOff() async {
        let store = makeStore(cli: FakeCLI(), harnessesOn: [])
        await store.load()
        store.startEdit("gamma")
        XCTAssertTrue(store.packageCards.contains { $0.name == "pi" }, "so it can be taken off")
        XCTAssertFalse(store.packageCards.contains { $0.name == "claude-code" })
    }

    func testTheConfiguredDefaultsArePreselectedOnCLI0729() async {
        let store = makeStore(cli: FakeCLI(), defaults: ["zsh", "pi"])
        await store.load()
        await store.startNew()
        XCTAssertEqual(store.flow?.draft.packages, ["zsh", "pi"])
        XCTAssertTrue(store.knowsDefaults)
    }

    func testEditListsTheLoginsOfItsPackagesWithWhatTheyFollow() async {
        let store = makeStore(cli: FakeCLI(), defaults: [], sharing: ["pi": "machine"])
        await store.load()
        store.startEdit("gamma")
        XCTAssertEqual(store.logins, [WorkspaceLogin(name: "pi", package: "pi", inherited: "machine")])
        XCTAssertTrue(store.reportsSharing)
    }

    func testATypedNumberThatIsNotOneHoldsContinue() async {
        let store = makeStore(cli: FakeCLI(), defaults: [])
        await store.load()
        store.startEdit("gamma")
        XCTAssertEqual(store.variables.map(\.package), ["pi"])
        store.flow?.setSetting("pi.port", "eighty")
        XCTAssertFalse(store.canContinue)
        store.flow?.setSetting("pi.port", "8080")
        XCTAssertTrue(store.canContinue)
    }

    func testAnOlderCLIShowsNoLogins() async {
        let store = makeStore(cli: FakeCLI())
        await store.load()
        store.startEdit("gamma")
        XCTAssertFalse(store.reportsSharing)
        XCTAssertFalse(store.knowsDefaults)
    }

    func testCreatingRunsNewThenSyncAndReadsEverythingAgain() async {
        let cli = FakeCLI()
        let reads = WorkspaceReadTally()
        let changed = WorkspaceChangeTally()
        let store = makeStore(cli: cli, reads: reads, changed: changed)
        await store.load()
        await store.startNew()
        store.flow?.draft.name = "beta"
        store.flow?.togglePackage("pi")
        store.next()
        XCTAssertEqual(store.flow?.stage, .review)

        await store.run()

        XCTAssertEqual(cli.commands, [
            ["workspaces", "new", "beta", "--machine", "main", "--packages", "dev,zsh,mise,pi", "--yes"],
            ["sync", "--machine", "main", "--yes"],
        ])
        XCTAssertEqual(store.runner.phase, .succeeded)
        XCTAssertEqual(store.flow?.stage, .run)
        XCTAssertEqual(changed.value, 1)
        let readCount = await reads.value
        XCTAssertEqual(readCount, 2)
    }

    func testAFailedSyncShowsTheCLIsWordsAndRetryRunsOnlyTheSync() async {
        let cli = FakeCLI()
        cli.status = { $0.first == "sync" ? 1 : 0 }
        cli.output = { $0.first == "sync" ? "error: the machine main could not be reached" : "ok" }
        let store = makeStore(cli: cli)
        await store.load()
        await store.startNew()
        store.flow?.draft.name = "beta"
        store.next()
        await store.run()

        XCTAssertEqual(store.runner.phase, .failed(step: "sync --machine main --yes"))
        XCTAssertEqual(store.runner.problem, "the machine main could not be reached")
        XCTAssertEqual(store.failedStep?.kind, .sync)
        XCTAssertFalse(store.canEditAnswers, "the workspace is already in the configuration")

        cli.status = { _ in 0 }
        await store.retry()
        XCTAssertEqual(cli.commands.map(\.first), ["workspaces", "sync", "sync"])
        XCTAssertEqual(store.runner.phase, .succeeded)
    }

    func testARefusedFirstStepGoesBackToTheAnswers() async {
        let cli = FakeCLI()
        cli.status = { _ in 1 }
        cli.output = { _ in "error: a workspace named beta is already configured: pick another name" }
        let store = makeStore(cli: cli)
        await store.load()
        await store.startNew()
        store.flow?.draft.name = "beta"
        store.next()
        await store.run()

        XCTAssertTrue(store.canEditAnswers)
        store.editAnswers()
        XCTAssertEqual(store.flow?.stage, .form)
        XCTAssertEqual(store.flow?.draft.name, "beta")
    }

    func testEditRunsTheChangesThenSyncsItsMachine() async {
        let cli = FakeCLI()
        let store = makeStore(cli: cli)
        await store.load()
        store.startEdit("acme")
        store.flow?.togglePackage("pi")
        store.flow?.settings[0].value = "agnoster"
        store.next()
        await store.run()

        XCTAssertEqual(cli.commands, [
            ["workspaces", "edit", "acme", "--add", "pi", "--set", "zsh.theme=agnoster", "--yes"],
            ["sync", "--machine", "main", "--yes"],
        ])
    }

    func testForgetAndDestroyRunTheirOneCommand() async {
        let cli = FakeCLI()
        let store = makeStore(cli: cli)
        await store.load()

        store.startForget("acme")
        await store.run()
        store.close()
        XCTAssertNil(store.flow)

        store.startDestroy("gamma")
        await store.run()
        XCTAssertTrue(cli.commands.count == 1, "destroy waits for the name typed again")
        store.flow?.typedName = "gamma"
        store.flow?.keepDNS = true
        await store.run()

        XCTAssertEqual(cli.commands, [
            ["workspaces", "rm", "acme", "--yes"],
            ["workspaces", "destroy", "gamma", "--confirm", "gamma", "--keep-dns"],
        ])
    }

    func testTheCLIsRefusalToForgetIsWhatThePageShows() async {
        let cli = FakeCLI()
        cli.status = { _ in 1 }
        cli.output = { _ in
            "error: acme publishes app.example.com through edge, which would keep serving it with nothing left "
                + "to take it off: `devmachine expose rm app.example.com` first"
        }
        let store = makeStore(cli: cli)
        await store.load()
        store.startForget("acme")
        await store.run()

        XCTAssertEqual(store.runner.problem, "acme publishes app.example.com through edge, which would keep serving "
            + "it with nothing left to take it off: `devmachine expose rm app.example.com` first")
    }

    func testCancelGoesBackToTheList() async {
        let store = makeStore(cli: FakeCLI())
        await store.load()
        store.startForget("acme")
        store.close()
        XCTAssertNil(store.flow)
    }

    func testANewWorkspaceRequestOpensTheFlowOnce() async {
        let store = makeStore(cli: FakeCLI())
        await store.load()
        await store.startNew()
        store.flow?.draft.name = "beta"
        await store.startNew()
        XCTAssertEqual(store.flow?.draft.name, "beta", "a second request keeps the answers being typed")
    }

    func testDemoModeRefusesEveryRun() async {
        setenv("DEVMACHINE_DEMO", "1", 1)
        defer { unsetenv("DEVMACHINE_DEMO") }
        let cli = FakeCLI()
        let store = makeStore(cli: cli)
        await store.load()
        store.startForget("acme")
        await store.run()

        XCTAssertEqual(cli.commands, [])
        XCTAssertEqual(store.runner.problem, "Demo mode never changes a workspace.")
    }
}

private actor WorkspaceReadTally {
    private(set) var value = 0
    func bump() { value += 1 }
}

@MainActor
private final class WorkspaceChangeTally {
    var value = 0
}
