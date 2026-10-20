import XCTest
import DevmachineCore
@testable import DevmachineApp

/// Demo mode shows every screen and runs nothing: each store that can
/// change a machine, a configuration or this Mac refuses before it reaches
/// a runner, a terminal or the CLI.
@MainActor
final class DemoRefusalTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("DEVMACHINE_DEMO", "1", 1)
    }

    override func tearDown() {
        unsetenv("DEVMACHINE_DEMO")
        super.tearDown()
    }

    func testRemovingAMachineIsRefusedWithoutCallingTheCLI() async {
        let store = MachinesStore(read: { .none }, remove: { _ in XCTFail("demo mode removed a machine") })

        await store.removeMachine("staging")

        XCTAssertEqual(store.removalError?.details, "Demo mode never removes a machine.")
        XCTAssertNil(store.removing)
    }

    func testTheAddMachineRunnerNeitherTypesNorStartsAProcess() async {
        let hooks = MachineStepRunner.Hooks(
            executable: { "/opt/homebrew/bin/devmachine" },
            isReady: { _ in true },
            type: { _, _ in XCTFail("demo mode typed into a terminal") },
            matchCount: { _, _ in 0 },
            writeScript: { _, _ in
                XCTFail("demo mode wrote a step script")
                return "/tmp/x.sh"
            },
            isAtPrompt: { _ in nil },
            runProcess: { _, _, _ in
                XCTFail("demo mode started the CLI")
                return 0
            },
            beginTask: { _, _ in nil }, setTask: { _, _ in }, endTask: { _, _ in })
        var draft = MachineDraft()
        draft.name = "main"
        draft.address = "203.0.113.10"
        draft.keyFile = "~/.ssh/id_ed25519"
        draft.fingerprint = "SHA256:" + String(repeating: "D", count: 43)
        let steps = MachinePlan.steps(for: draft)

        for inTerminal in [true, false] {
            let runner = MachineStepRunner(hooks: hooks, pollInterval: 1_000_000)
            await runner.run(steps, inTerminal: inTerminal)
            XCTAssertEqual(runner.phase, .failed(step: steps[0].id))
            XCTAssertEqual(runner.problem, "Demo mode never adds a machine.")
        }
    }

    func testAPrepareOrDNSSyncNeverResolvesTheCLI() async {
        let runner = ProcessJobRunner(cli: {
            XCTFail("demo mode resolved the CLI for a sync")
            throw DevmachineCLIError.commandFailed("no")
        })

        do {
            _ = try await runner.run(arguments: ["sync", "--machine", "main", "--yes"], output: { _ in })
            XCTFail("demo mode ran a sync")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Demo mode never runs a devmachine command.")
        }
    }

    func testPrepareFailsInTheCornerWithoutResolvingTheCLI() async throws {
        let center = MachineJobCenter(runner: ProcessJobRunner(cli: {
            XCTFail("demo mode resolved the CLI for Prepare")
            throw DevmachineCLIError.commandFailed("no")
        }))
        var snapshot = ReadinessSnapshot()
        snapshot.machines = ["main"]
        snapshot.declared = ["main": true]
        snapshot.lock = PackagesLock(machines: ["main": []])
        snapshot.cliVersion = SemanticVersion("0.7.24")
        let ready = snapshot
        let store = MachineReadinessStore(read: { ready }, jobs: { center }, listensForReports: false)
        await store.check()

        let id = try XCTUnwrap(store.prepare("main"))

        let deadline = Date().addingTimeInterval(5)
        while center.job(id)?.phase != .failed(cause: "Demo mode never runs a devmachine command."), Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(center.job(id)?.phase, .failed(cause: "Demo mode never runs a devmachine command."))
    }

    func testADNSSyncFailsInTheCornerWithoutResolvingTheCLI() async throws {
        let center = MachineJobCenter(runner: ProcessJobRunner(cli: {
            XCTFail("demo mode resolved the CLI for a DNS sync")
            throw DevmachineCLIError.commandFailed("no")
        }))
        let setup = DNSSetupStore(
            service: CaddyService(cli: DevmachineCLI(executable: "/fake", runner: DemoMode.runner)),
            center: { center }, canRunSync: { true })
        setup.update(
            machine: "main",
            packages: [CLIPackage(name: "hostinger", scope: "machine", installedOn: ["machine main"],
                                  summary: "DNS zones on Hostinger.")],
            answers: [])

        let id = try XCTUnwrap(setup.sync("hostinger"))

        let deadline = Date().addingTimeInterval(5)
        while setup.state == .working(.sync), Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(center.job(id)?.phase, .failed(cause: "Demo mode never runs a devmachine command."))
        XCTAssertEqual(setup.state, .failed(.sync, cause: "Demo mode never runs a devmachine command.",
                                            details: "$ devmachine sync --machine main --tags hostinger --yes"))
    }

    func testRemoveInDemoModeIsRefused() async {
        let center = MachineJobCenter(runner: ProcessJobRunner(cli: {
            XCTFail("demo mode resolved the CLI to remove a DNS provider")
            throw DevmachineCLIError.commandFailed("no")
        }))
        let setup = DNSSetupStore(
            service: CaddyService(cli: DevmachineCLI(executable: "/fake", runner: DemoMode.runner)),
            center: { center }, canRunSync: { true })
        setup.update(
            machine: "main",
            packages: [CLIPackage(name: "hostinger", scope: "machine", installedOn: ["machine main"],
                                  summary: "DNS zones on Hostinger.")],
            answers: [])

        await setup.remove("hostinger")

        guard case let .failed(step, _, details) = setup.stateOf("hostinger") else { return XCTFail() }
        XCTAssertEqual(step, .remove)
        XCTAssertEqual(details, "Demo mode never changes a configuration or a secret.")
        XCTAssertTrue(center.jobs.isEmpty)
    }
}
