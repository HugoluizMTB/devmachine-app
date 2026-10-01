import XCTest
@testable import DevmachineCore

final class PackagesLockTests: XCTestCase {
    private let lock = """
        release: v0.7.3
        applied_at: "2026-09-18T12:00:00Z"
        machines:
            beta: []
            main:
                - name: base
                  source: release
                  version: v0.7.3
                  checksum: abc
                - name: devmachine-app
                  source: release
                  version: v0.7.3
                  checksum: abc
        workspaces:
            acme:
                - name: devmachine-app
                  source: release
        extensions:
            main:
                - /etc/x
        """

    func testReadsWhatEachMachineHasApplied() throws {
        let parsed = try XCTUnwrap(PackagesLock.parse(lock))
        XCTAssertEqual(parsed.appliedAt, "2026-09-18T12:00:00Z")
        XCTAssertTrue(parsed.has("devmachine-app", onMachine: "main"))
        XCTAssertEqual(parsed.entry("devmachine-app", onMachine: "main")?.version, "v0.7.3")
        XCTAssertFalse(parsed.has("devmachine-app", onMachine: "beta"))
        XCTAssertEqual(parsed.machines["beta"], [])
    }

    func testAWorkspaceEntryIsNotAMachineEntry() throws {
        let parsed = try XCTUnwrap(PackagesLock.parse(lock))
        XCTAssertNil(parsed.machines["acme"])
    }

    func testReadsTwoSpaceIndentAndAnEmptyMap() throws {
        let parsed = try XCTUnwrap(PackagesLock.parse(
            "applied_at: \"2026-09-18T12:00:00Z\"\nmachines:\n  main: []\nworkspaces: {}\n"))
        XCTAssertEqual(parsed.machines, ["main": []])
    }

    func testTextThatIsNotALockIsNil() {
        XCTAssertNil(PackagesLock.parse(""))
        XCTAssertNil(PackagesLock.parse("just words"))
    }
}

final class ReadinessCheckTests: XCTestCase {
    func testDeclaredAndAppliedIsReady() {
        XCTAssertEqual(ReadinessCheck.evaluate(declared: true, applied: true, observed: nil), .ready)
    }

    func testNotDeclared() {
        XCTAssertEqual(ReadinessCheck.evaluate(declared: false, applied: false, observed: nil), .notDeclared)
    }

    func testDeclaredButNeverSyncedIsNotApplied() {
        XCTAssertEqual(ReadinessCheck.evaluate(declared: true, applied: false, observed: nil), .notApplied)
    }

    func testAnUnreadableLockFailsOpen() {
        XCTAssertEqual(ReadinessCheck.evaluate(declared: true, applied: nil, observed: nil), .ready)
    }

    func testAnUnreadableConfigurationIsUnknownAndNeedsNoAttention() {
        let state = ReadinessCheck.evaluate(declared: nil, applied: nil, observed: nil)
        XCTAssertEqual(state, .unknown)
        XCTAssertFalse(state.needsAttention)
    }

    func testAFailedCallWinsOverTheLock() {
        XCTAssertEqual(
            ReadinessCheck.evaluate(declared: true, applied: true, observed: .notInstalled), .notApplied)
        XCTAssertEqual(
            ReadinessCheck.evaluate(declared: false, applied: nil, observed: .notInstalled), .notDeclared)
        XCTAssertEqual(
            ReadinessCheck.evaluate(declared: true, applied: true, observed: .outdated(detail: "x")),
            .outdated(detail: "x"))
    }

    func testOnlyMissingStatesArePrepared() {
        XCTAssertTrue(MachineReadiness.notDeclared.needsPrepare)
        XCTAssertTrue(MachineReadiness.notApplied.needsPrepare)
        XCTAssertFalse(MachineReadiness.outdated(detail: "").needsPrepare)
        XCTAssertTrue(MachineReadiness.outdated(detail: "").needsAttention)
        XCTAssertFalse(MachineReadiness.ready.needsAttention)
    }
}

final class PackageCallFailureTests: XCTestCase {
    func testTheCLIsNotInstalledWording() {
        let detail = "error: devmachine-app is not installed on main. Add it with "
            + "`devmachine packages add devmachine-app` and apply with `devmachine sync`"
        XCTAssertEqual(PackageCallFailure.classify(detail), .notInstalled)
        XCTAssertEqual(PackageCallFailure.machine(in: detail), "main")
    }

    func testTheWorkspaceFormNamesTheMachineFirst() {
        let detail = "devmachine-app is not installed on main or workspace acme. Add it with …"
        XCTAssertEqual(PackageCallFailure.machine(in: detail), "main")
    }

    func testAnUnknownCommandIsOutdated() {
        let detail = #"error: devmachine-app does not accept "stats". It accepts context"#
        XCTAssertEqual(PackageCallFailure.classify(detail), .outdated(detail: detail))
    }

    func testAMissingEntrypointOnTheMachineIsNotInstalled() {
        let detail = "sh: 1: /opt/devmachine/roles/devmachine-app/bin/devmachine-app: not found"
        XCTAssertEqual(PackageCallFailure.classify(detail), .notInstalled)
    }

    func testAnotherPackagesErrorsAreNotThisPackages() {
        XCTAssertNil(PackageCallFailure.classify("cloudflare is not installed on main. Add it with …"))
        XCTAssertNil(PackageCallFailure.classify("ssh: connect to host 203.0.113.7 port 22: Connection refused"))
    }
}

final class MachinePrepareTests: XCTestCase {
    func testAddsOnlyWhenNotDeclaredThenSyncsOnlyThePackage() {
        XCTAssertEqual(MachinePrepare.steps(machine: "main", declared: false), [
            ["packages", "add", "devmachine-app", "--machine", "main", "--yes"],
            ["sync", "--machine", "main", "--tags", "devmachine-app", "--yes"],
        ])
        XCTAssertEqual(MachinePrepare.steps(machine: "main", declared: true), [
            ["sync", "--machine", "main", "--tags", "devmachine-app", "--yes"],
        ])
    }

    func testPrepareNeedsACLIThatLocksOnlyTaggedPackages() {
        XCTAssertFalse(MachinePrepare.canPrepareInApp(cliVersion: SemanticVersion("0.7.23")))
        XCTAssertTrue(MachinePrepare.canPrepareInApp(cliVersion: SemanticVersion("0.7.24")))
        XCTAssertTrue(MachinePrepare.canPrepareInApp(cliVersion: SemanticVersion("0.8.0")))
        XCTAssertFalse(MachinePrepare.canPrepareInApp(cliVersion: nil))
    }

    func testManualCommandsUseAPlainSyncThatAsksFirst() {
        XCTAssertEqual(MachinePrepare.manualCommands(machine: "main", declared: false), [
            "devmachine packages add devmachine-app --machine main",
            "devmachine sync --machine main",
        ])
        XCTAssertEqual(MachinePrepare.manualCommands(machine: "main", declared: true), [
            "devmachine sync --machine main",
        ])
    }

    func testOutdatedNeverMovesThePinItself() {
        XCTAssertEqual(MachinePrepare.outdatedCommands(machine: "main"), [
            "devmachine packages pin", "devmachine sync --machine main",
        ])
    }

    func testFailureCauseReadsTheLastErrorLine() {
        XCTAssertEqual(
            MachinePrepare.failureCause(["PLAY [devmachine]", "error: 1 task(s) failed on main: exit status 2"]),
            "1 task(s) failed on main: exit status 2")
        XCTAssertNil(MachinePrepare.failureCause(["ok"]))
    }
}

final class SessionListProblemTests: XCTestCase {
    func testSSHLookingUpTheAliasItselfMeansNoHostEntry() {
        let stderr = "ssh: Could not resolve hostname acme-devmachine: nodename nor servname provided, or not known"
        XCTAssertEqual(
            SessionListProblem.classify(alias: "acme-devmachine", exitCode: 255, stderr: stderr),
            .aliasMissing(alias: "acme-devmachine"))
    }

    func testARealHostThatDoesNotResolveIsNotAMissingAlias() {
        let stderr = "ssh: Could not resolve hostname vps.example.com: nodename nor servname provided, or not known"
        XCTAssertNil(SessionListProblem.classify(alias: "acme-devmachine", exitCode: 255, stderr: stderr))
    }

    func testExit127IsNoTmux() {
        XCTAssertEqual(SessionListProblem.classify(alias: "acme-devmachine", exitCode: 127, stderr: ""), .tmuxMissing)
    }

    func testNoServerRunningIsNotAProblem() {
        XCTAssertNil(SessionListProblem.classify(
            alias: "acme-devmachine", exitCode: 1, stderr: "no server running on /tmp/tmux-1000/default"))
    }

    func testTheStoreThrowsTheProblemInsteadOfAnEmptyList() {
        struct Runner: CommandRunner {
            func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
            func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
                -> (stdout: String, stderr: String, exitCode: Int32) { ("@@PANES@@\n", "", 127) }
        }
        XCTAssertThrowsError(try SessionStore(runner: Runner()).sessions(
            for: Workspace(name: "acme", alias: "acme-devmachine"), processNames: [:])) { error in
            XCTAssertEqual((error as? SessionListError)?.problem, .tmuxMissing)
        }
    }
}

final class CLIInstallPlanTests: XCTestCase {
    func testPrefersHomebrewWhenThisMacHasIt() {
        let plan = CLIInstallPlan.choose(exists: { $0 == "/usr/local/bin/brew" })
        XCTAssertEqual(plan, .homebrew(brew: "/usr/local/bin/brew"))
        XCTAssertEqual(plan.executable, "/bin/sh")
        XCTAssertEqual(plan.arguments, [
            "-c",
            "'/usr/local/bin/brew' trust --formula mydevmachine/tap/devmachine >/dev/null 2>&1 || true; "
                + "'/usr/local/bin/brew' install mydevmachine/tap/devmachine",
        ])
        XCTAssertEqual(plan.copyCommand, "brew install mydevmachine/tap/devmachine")
    }

    func testUsesTheInstallerWithoutHomebrew() {
        let plan = CLIInstallPlan.choose(exists: { _ in false })
        XCTAssertEqual(plan, .installer)
        XCTAssertEqual(plan.arguments, ["-c", "curl -fsSL https://mydevmachine.sh/install.sh | sh"])
    }

    func testTheInstallerPutsTheBinaryInLocalBin() {
        XCTAssertEqual(CLIInstallPlan.installerBinary(home: "/Users/alice"), "/Users/alice/.local/bin/devmachine")
    }
}
