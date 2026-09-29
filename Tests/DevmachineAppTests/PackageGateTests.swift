import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class ScriptedRunner: CommandRunner, @unchecked Sendable {
    private let byCommand: [String: (stdout: String, stderr: String, exitCode: Int32)]

    init(byCommand: [String: (stdout: String, stderr: String, exitCode: Int32)]) {
        self.byCommand = byCommand
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        let key = args.contains("machines") ? "machines" : args.contains("packages") ? "list" : (args.last ?? "")
        return byCommand[key] ?? ("", "not stubbed: \(args)", 1)
    }
}

final class PackageGateCheckerTests: XCTestCase {
    func testOKWhenThePackageIsInstalledOnTheAdminMachine() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"acme"},{"name":"mac","self":true}]"#, "", 0),
            "list": (#"{"packages":[{"name":"devmachine-app","scope":"machine","installed_on":["machine acme"]}]}"#, "", 0),
        ])
        let state = PackageGateChecker.check(cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })
        XCTAssertEqual(state, .ok)
    }

    func testMissingWhenThePackageIsNotInThePackagesList() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"acme"},{"name":"mac","self":true}]"#, "", 0),
            "list": (#"{"packages":[{"name":"base","scope":"machine","installed_on":["machine acme"]}]}"#, "", 0),
        ])
        let state = PackageGateChecker.check(cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })
        XCTAssertEqual(state, .missing(machines: ["acme"]))
    }

    func testMissingWhenThePackageIsInstalledOnADifferentMachine() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"acme"},{"name":"mac","self":true}]"#, "", 0),
            "list": (#"{"packages":[{"name":"devmachine-app","scope":"machine","installed_on":["machine mac"]}]}"#, "", 0),
        ])
        let state = PackageGateChecker.check(cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })
        XCTAssertEqual(state, .missing(machines: ["acme"]))
    }

    func testListsEveryMachineMissingThePackageWhenThereAreSeveral() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"acme"},{"name":"beta"},{"name":"gamma"},{"name":"mac","self":true}]"#, "", 0),
            "list": (#"{"packages":[{"name":"devmachine-app","scope":"machine","installed_on":["machine beta"]}]}"#, "", 0),
        ])
        let state = PackageGateChecker.check(cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })
        XCTAssertEqual(state, .missing(machines: ["acme", "gamma"]))
    }

    func testFailsOpenWhenPackagesListItselfFails() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"acme"},{"name":"mac","self":true}]"#, "", 0),
            "list": ("", "connection refused", 1),
        ])
        let state = PackageGateChecker.check(cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })
        XCTAssertEqual(state, .ok)
    }

    func testFailsOpenWhenNoAdminMachineIsConfigured() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"mac","self":true}]"#, "", 0),
        ])
        let state = PackageGateChecker.check(cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })
        XCTAssertEqual(state, .ok)
    }
}

final class CaddyAvailabilityCheckerTests: XCTestCase {
    func testTrueWhenANonSelfMachineHasCaddyDirectly() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"acme"},{"name":"mac","self":true}]"#, "", 0),
            "list": (#"{"packages":[{"name":"caddy","scope":"machine","installed_on":["machine acme"]}]}"#, "", 0),
        ])
        let state = CaddyAvailabilityChecker.check(cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })
        XCTAssertEqual(state, true)
    }

    func testTrueWhenANonSelfMachineHasEssentials() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"acme"},{"name":"mac","self":true}]"#, "", 0),
            "list": (#"{"packages":[{"name":"essentials","scope":"machine","installed_on":["machine acme"]}]}"#, "", 0),
        ])
        let state = CaddyAvailabilityChecker.check(cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })
        XCTAssertEqual(state, true)
    }

    func testFalseWhenNoNonSelfMachineHasEitherPackage() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"acme"},{"name":"mac","self":true}]"#, "", 0),
            "list": (#"{"packages":[{"name":"devmachine-app","scope":"machine","installed_on":["machine acme"]}]}"#, "", 0),
        ])
        let state = CaddyAvailabilityChecker.check(cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })
        XCTAssertEqual(state, false)
    }

    func testFalseWithOnlyASelfMachineConfigured() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"mac","self":true}]"#, "", 0),
            "list": (#"{"packages":[]}"#, "", 0),
        ])
        let state = CaddyAvailabilityChecker.check(cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })
        XCTAssertEqual(state, false)
    }

    func testNilWhenPackagesListItselfFails() {
        let runner = ScriptedRunner(byCommand: [
            "machines": (#"[{"name":"acme"},{"name":"mac","self":true}]"#, "", 0),
            "list": ("", "connection refused", 1),
        ])
        let state = CaddyAvailabilityChecker.check(cli: { DevmachineCLI(executable: "/opt/devmachine", runner: runner) })
        XCTAssertNil(state)
    }
}

final class PackageGateMessageTests: XCTestCase {
    func testAnUnknownCommandGetsTheUpgradeInstructions() {
        let message = PackageGateMessage.friendly(
            for: DevmachineCLIError.commandFailed(#"error: devmachine-app does not accept "stats". It accepts context"#))
        XCTAssertTrue(message.contains("packages pin"))
        XCTAssertTrue(message.contains("sync"))
    }

    func testAnyOtherErrorPassesThrough() {
        let message = PackageGateMessage.friendly(
            for: DevmachineCLIError.commandFailed("ssh: connect to host acme port 22: Connection refused"))
        XCTAssertEqual(message, "ssh: connect to host acme port 22: Connection refused")
    }
}
