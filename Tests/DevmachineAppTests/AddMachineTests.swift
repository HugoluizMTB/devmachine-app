import XCTest
import DevmachineCore
@testable import DevmachineApp

/// Stands in for the terminal: records what was typed, and "prints" the
/// marker each step's script would print, as the test decides.
@MainActor
private final class FakeTerminal {
    var typed: [String] = []
    var scripts: [String: String] = [:]
    var ready = true
    var executable: String? = "/opt/homebrew/bin/devmachine"
    /// The steps (by their arguments' first words) that end with an error.
    var failing: Set<String> = []
    var printed: [String] = []
    var tasks: [(String, Int)] = []
    var ended: [Bool] = []

    var hooks: MachineStepRunner.Hooks {
        MachineStepRunner.Hooks(
            executable: { self.executable },
            isReady: { _ in self.ready },
            type: { text, _ in self.typed.append(text) },
            matchCount: { term, _ in self.printed.filter { $0 == term }.count },
            writeScript: { script, nonce in
                let path = "/tmp/steps/\(nonce).sh"
                self.scripts[path] = script
                let fails = self.failing.contains { script.contains($0) }
                self.printed.append(fails ? TerminalStepMarker.fail(nonce: nonce) : TerminalStepMarker.ok(nonce: nonce))
                return path
            },
            beginTask: { label, total in
                self.tasks.append((label, total))
                return UUID()
            },
            setTask: { _, _ in },
            endTask: { _, succeeded in self.ended.append(succeeded) })
    }
}

@MainActor
final class MachineStepRunnerTests: XCTestCase {
    private let fingerprint = "SHA256:" + String(repeating: "D", count: 43)

    private func plan(packages: [String] = []) -> [MachinePlanStep] {
        var draft = MachineDraft()
        draft.name = "main"
        draft.address = "203.0.113.10"
        draft.fingerprint = fingerprint
        draft.keyFile = "~/.ssh/id_ed25519"
        draft.packages = packages
        return MachinePlan.steps(for: draft)
    }

    func testEveryStepRunsInOrderThroughAScriptTypedIntoTheTerminal() async {
        let terminal = FakeTerminal()
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000)
        let steps = plan(packages: ["docker"])

        await runner.run(steps)

        XCTAssertEqual(runner.phase, .succeeded)
        XCTAssertEqual(terminal.typed.count, 3)
        XCTAssertTrue(terminal.typed.allSatisfy { $0.hasPrefix("sh /tmp/steps/") && $0.hasSuffix(".sh\r") })
        let scripts = terminal.typed.map { terminal.scripts[String($0.dropFirst(3).dropLast())] ?? "" }
        XCTAssertTrue(scripts[0].contains("/opt/homebrew/bin/devmachine machines add --name main"))
        XCTAssertTrue(scripts[1].contains("packages add docker --machine main --yes"))
        XCTAssertTrue(scripts[2].contains("sync --machine main --yes"))
        XCTAssertEqual(steps.map { runner.status(of: $0) }, [.done, .done, .done])
        XCTAssertEqual(terminal.tasks.first?.1, 3)
        XCTAssertEqual(terminal.ended, [true])
    }

    func testAFailedStepStopsTheRunAndSaysWhich() async {
        let terminal = FakeTerminal()
        terminal.failing = ["packages add docker"]
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000)
        let steps = plan(packages: ["docker"])

        await runner.run(steps)

        XCTAssertEqual(runner.phase, .failed(step: steps[1].id))
        XCTAssertEqual(steps.map { runner.status(of: $0) }, [.done, .failed, .waiting])
        XCTAssertEqual(terminal.typed.count, 2)
        XCTAssertNotNil(runner.problem)
        XCTAssertEqual(terminal.ended, [false])
    }

    func testARetrySkipsWhatIsDoneAndRunsTheRest() async {
        let terminal = FakeTerminal()
        terminal.failing = ["packages add docker"]
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000)
        let steps = plan(packages: ["docker"])
        await runner.run(steps)

        terminal.failing = []
        await runner.run(steps)

        XCTAssertEqual(runner.phase, .succeeded)
        XCTAssertEqual(terminal.typed.count, 4)
        XCTAssertFalse(terminal.scripts.values.filter { $0.contains("machines add") }.count > 1)
    }

    func testWithoutTheCLINothingIsTyped() async {
        let terminal = FakeTerminal()
        terminal.executable = nil
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000)

        await runner.run(plan())

        XCTAssertEqual(terminal.typed, [])
        XCTAssertEqual(runner.problem, "The devmachine CLI was not found on this Mac.")
    }

    func testATerminalThatNeverStartsFailsInsteadOfWaitingForever() async {
        let terminal = FakeTerminal()
        terminal.ready = false
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000, readyTimeout: 3)

        await runner.run(plan())

        XCTAssertEqual(terminal.typed, [])
        XCTAssertEqual(runner.problem, "The terminal below did not start.")
    }

    func testResetForgetsTheRun() async {
        let terminal = FakeTerminal()
        let runner = MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000)
        let steps = plan()
        await runner.run(steps)

        runner.reset()

        XCTAssertEqual(runner.phase, .idle)
        XCTAssertEqual(runner.status(of: steps[0]), .waiting)
    }
}

@MainActor
final class AddMachineModelTests: XCTestCase {
    private func store(_ snapshot: MachinesSnapshot) async -> MachinesStore {
        let store = MachinesStore(read: { snapshot }, remove: { _ in })
        await store.load()
        return store
    }

    func testTheWizardKnowsTheNamesTakenAndWhetherAConfigurationExists() async {
        let machines = await store(MachinesSnapshot(
            hasConfiguration: true,
            machines: [ConfiguredMachine(
                name: "main", hosts: ["203.0.113.10"], adminUser: "root", port: 22,
                workspaces: [], packages: [], isSelf: false)],
            packages: []))
        let model = AddMachineModel(
            machines: machines, runner: MachineStepRunner(hooks: FakeTerminal().hooks), findLima: { nil },
            onAdded: {})

        XCTAssertEqual(model.wizard.existingMachines, ["main"])
        XCTAssertFalse(model.wizard.limaFound)
        XCTAssertTrue(model.wizard.draft.hasConfiguration)

        let empty = AddMachineModel(
            machines: await store(.none), runner: MachineStepRunner(hooks: FakeTerminal().hooks),
            findLima: { "/opt/homebrew/bin/limactl" }, onAdded: {})
        XCTAssertFalse(empty.wizard.draft.hasConfiguration)
        XCTAssertTrue(empty.wizard.limaFound)
    }

    func testCreatingRunsThePlanAndReloadsOnSuccess() async {
        let terminal = FakeTerminal()
        var added = 0
        let model = AddMachineModel(
            machines: await store(.none),
            runner: MachineStepRunner(hooks: terminal.hooks, pollInterval: 1_000_000),
            findLima: { "/opt/homebrew/bin/limactl" }, onAdded: { added += 1 })
        model.wizard.choose(.localVM)
        model.wizard.draft.name = "lab"
        model.wizard.next()
        model.wizard.next()

        await model.create()

        XCTAssertEqual(model.wizard.stage, .run)
        XCTAssertEqual(model.runner.phase, .succeeded)
        XCTAssertEqual(added, 1)
        XCTAssertEqual(terminal.typed.count, 3)
    }

    func testOpeningThePageAfterASuccessStartsAFreshWizard() async {
        let model = AddMachineModel(
            machines: await store(.none),
            runner: MachineStepRunner(hooks: FakeTerminal().hooks, pollInterval: 1_000_000),
            findLima: { "/opt/homebrew/bin/limactl" }, onAdded: {})
        model.wizard.choose(.localVM)
        model.wizard.draft.name = "lab"
        model.wizard.next()
        model.wizard.next()
        await model.create()

        model.openPage()

        XCTAssertEqual(model.wizard.stage, .kind)
        XCTAssertEqual(model.wizard.draft.name, "")
    }

    func testOpeningThePageKeepsAnswersNotRunYet() async {
        let model = AddMachineModel(
            machines: await store(.none), runner: MachineStepRunner(hooks: FakeTerminal().hooks),
            findLima: { nil }, onAdded: {})
        model.wizard.choose(.server)
        model.wizard.draft.name = "main"

        model.openPage()

        XCTAssertEqual(model.wizard.stage, .details)
        XCTAssertEqual(model.wizard.draft.name, "main")
    }
}

@MainActor
final class MachinesStoreTests: XCTestCase {
    func testNothingIsOfferedBeforeTheFirstRead() {
        let store = MachinesStore(read: { .none }, remove: { _ in })
        XCTAssertNil(store.remoteMachineNames)
    }

    func testThisMacIsNotAMachineToOfferOneFor() async {
        let store = MachinesStore(
            read: {
                MachinesSnapshot(
                    hasConfiguration: true,
                    machines: [ConfiguredMachine(
                        name: "laptop", hosts: [], adminUser: "", port: 0, workspaces: [], packages: [],
                        isSelf: true)],
                    packages: [])
            },
            remove: { _ in })
        await store.load()
        XCTAssertEqual(store.remoteMachineNames, [])
        XCTAssertTrue(AddMachinePrompt.shows(remoteMachines: store.remoteMachineNames))
    }

    func testAFailedReadSaysSoAndOffersNoButton() async {
        struct Broken: Error, LocalizedError { var errorDescription: String? { "config.yml: bad indent" } }
        let store = MachinesStore(read: { throw Broken() }, remove: { _ in })
        await store.load()
        guard case .failed = store.phase else { return XCTFail("expected a failure, got \(store.phase)") }
        XCTAssertNil(store.remoteMachineNames)
    }

    func testRemovingAMachineGoesThroughTheCLIThenReadsAgain() async {
        let removed = RemovedNames()
        let store = MachinesStore(read: { .none }, remove: { removed.append($0) })
        await store.removeMachine("staging")
        XCTAssertEqual(removed.names, ["staging"])
        XCTAssertNil(store.removalError)
        XCTAssertEqual(store.remoteMachineNames, [])
    }

    func testARefusedRemovalShowsTheCLIsWords() async {
        struct Refused: Error, LocalizedError {
            var errorDescription: String? { "machine staging still has workspaces: umbrella" }
        }
        let store = MachinesStore(read: { .none }, remove: { _ in throw Refused() })
        await store.removeMachine("staging")
        XCTAssertEqual(store.removalError?.details, "machine staging still has workspaces: umbrella")
    }
}

private final class RemovedNames: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var names: [String] { lock.withLock { stored } }
    func append(_ name: String) { lock.withLock { stored.append(name) } }
}

/// Answers `config path`, `packages list` and `machines list` like the CLI.
private struct ConfigRunner: CommandRunner {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        switch Array(args.dropFirst(2)) {
        case ["config", "path"]:
            return #"{"path":"/Users/alice/.config/devmachine","source":"default"}"#
        case ["packages", "list"]:
            return #"""
            {"packages":[
              {"name":"essentials","scope":"machine","source":"release","summary":"Most machines want it.","installed_on":["machine main"]},
              {"name":"docker","scope":"machine","source":"release","summary":"Docker.","installed_on":[]},
              {"name":"zsh","scope":"workspace","source":"release","summary":"A shell.","installed_on":["workspace acme"]}
            ]}
            """#
        case ["machines", "list"]:
            return #"[{"name":"main","hosts":["203.0.113.10"],"admin_user":"root","port":22,"workspaces":["acme"]}]"#
        default:
            throw DevmachineCLIError.commandFailed("unexpected \(args)")
        }
    }
}

final class MachinesReaderTests: XCTestCase {
    private let cli = DevmachineCLI(executable: "/opt/homebrew/bin/devmachine", runner: ConfigRunner())

    func testNoConfigurationMeansNoMachineAndNoCall() throws {
        let snapshot = try MachinesReader.read(cli: cli, fileExists: { _ in false })
        XCTAssertEqual(snapshot, .none)
    }

    func testEachMachineCarriesThePackagesThatNameIt() throws {
        let snapshot = try MachinesReader.read(
            cli: cli, fileExists: { $0 == "/Users/alice/.config/devmachine/config.yml" })
        XCTAssertTrue(snapshot.hasConfiguration)
        XCTAssertEqual(snapshot.machines.map(\.name), ["main"])
        XCTAssertEqual(snapshot.machines.first?.packages, ["essentials"])
        XCTAssertEqual(snapshot.machines.first?.workspaces, ["acme"])
        XCTAssertEqual(
            MachinePackageCatalog.cards(from: snapshot.packages.map(\.info)).map(\.name), ["essentials", "docker"])
    }
}
