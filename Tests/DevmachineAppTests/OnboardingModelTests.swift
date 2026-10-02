import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class ScriptedRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [[String]] = []
    private let byCommand: [String: (stdout: String, stderr: String, exitCode: Int32)]

    init(byCommand: [String: (stdout: String, stderr: String, exitCode: Int32)]) {
        self.byCommand = byCommand
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock()
        storedCalls.append(args)
        lock.unlock()
        let key = args.contains("machines") ? "machines" : (args.contains("packages") ? "list" : (args.last ?? ""))
        return byCommand[key] ?? ("", "not stubbed: \(args)", 1)
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return storedCalls
    }
}

private func detection(
    cliFound: Bool = true, adminMachine: String? = nil, missingPackageMachines: [String] = []
) -> OnboardingDetection {
    OnboardingDetection(cliFound: cliFound, adminMachine: adminMachine, missingPackageMachines: missingPackageMachines)
}

// MARK: - OnboardingPlan.prepareSteps

final class OnboardingPlanPrepareStepsTests: XCTestCase {
    func testWithoutTheCLIOnlyTheCLIIsInstalledWithoutHomebrew() {
        let steps = OnboardingPlan.prepareSteps(for: detection(cliFound: false))
        XCTAssertEqual(steps, [.installCLI])
        XCTAssertEqual(steps[0].displayLine, CLIInstallPlan.noHomebrewCommand)
        XCTAssertFalse(steps[0].displayLine.contains("brew install"))
    }

    func testEachMachineMissingThisAppsPackageGetsItAndASyncInOrder() {
        let steps = OnboardingPlan.prepareSteps(
            for: detection(adminMachine: "acme", missingPackageMachines: ["acme", "beta"]))
        XCTAssertEqual(steps.map(\.arguments), [
            ["packages", "add", "devmachine-app", "--machine", "acme", "--yes"],
            ["sync", "--machine", "acme", "--yes"],
            ["packages", "add", "devmachine-app", "--machine", "beta", "--yes"],
            ["sync", "--machine", "beta", "--yes"],
        ])
    }

    func testAMacWithEverythingHasNothingToPrepare() {
        XCTAssertEqual(OnboardingPlan.prepareSteps(for: detection(adminMachine: "acme")), [])
    }
}

// MARK: - OnboardingDetector

final class OnboardingDetectorTests: XCTestCase {
    func testEverythingReadyReportsComplete() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"acme","hosts":["203.0.113.10"],"admin_user":"root","port":22,"workspaces":[]}]"#, "", 0),
            "list": (#"{"packages":[{"name":"devmachine-app","scope":"machine","installed_on":["machine acme"]}]}"#, "", 0),
        ])
        let result = OnboardingDetector.detect(
            cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })
        XCTAssertTrue(result.cliFound)
        XCTAssertEqual(result.adminMachine, "acme")
        XCTAssertEqual(result.missingPackageMachines, [])
        XCTAssertTrue(result.isComplete)
    }

    func testMissingCLIReportsNothingElseDetected() {
        let result = OnboardingDetector.detect(
            cli: { throw DevmachineCLIError.executableNotFound(["/fake"]) })
        XCTAssertFalse(result.cliFound)
        XCTAssertNil(result.adminMachine)
        XCTAssertEqual(result.missingPackageMachines, [])
        XCTAssertFalse(result.isComplete)
    }

    func testCLIFoundButNoMachineConfiguredLeavesThePackageUnchecked() {
        let runner = ScriptedRunner(byCommand: ["machines": ("[]", "", 0)])
        let result = OnboardingDetector.detect(
            cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })

        XCTAssertTrue(result.cliFound)
        XCTAssertNil(result.adminMachine)
        XCTAssertEqual(result.missingPackageMachines, [])
        XCTAssertFalse(runner.calls.contains { $0.contains("packages") })
    }

    func testSeveralMachinesReportsOnlyTheOnesMissingThePackage() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"""
                [{"name":"acme","hosts":["203.0.113.10"],"admin_user":"root","port":22,"workspaces":[]},
                 {"name":"beta","hosts":["203.0.113.20"],"admin_user":"root","port":22,"workspaces":[]}]
                """#, "", 0),
            "list": (#"{"packages":[{"name":"devmachine-app","scope":"machine","installed_on":["machine acme"]}]}"#, "", 0),
        ])
        let result = OnboardingDetector.detect(
            cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })

        XCTAssertEqual(result.missingPackageMachines, ["beta"])
        XCTAssertFalse(result.isComplete)
    }

    func testAFailedPackagesReadFailsOpenWithNothingMissing() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"acme","hosts":["203.0.113.10"],"admin_user":"root","port":22,"workspaces":[]}]"#, "", 0),
            "list": ("", "connection refused", 1),
        ])
        let result = OnboardingDetector.detect(
            cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })

        XCTAssertEqual(result.missingPackageMachines, [])
        // Failing open still leaves the machine detected, so `isComplete`
        // reads true rather than stuck behind a flaky `packages` read.
        XCTAssertTrue(result.isComplete)
    }
}

// MARK: - OnboardingDetection.isComplete (success detection)

final class OnboardingDetectionCompleteTests: XCTestCase {
    func testCompleteOnlyWhenCLIMachineAndEveryMachinesPackageAllHold() {
        XCTAssertFalse(OnboardingDetection.empty.isComplete)

        var result = detection(cliFound: true, adminMachine: nil, missingPackageMachines: [])
        XCTAssertFalse(result.isComplete)

        result.adminMachine = "acme"
        XCTAssertTrue(result.isComplete)

        result.missingPackageMachines = ["acme"]
        XCTAssertFalse(result.isComplete)

        result.missingPackageMachines = []
        XCTAssertTrue(result.isComplete)
    }

}
