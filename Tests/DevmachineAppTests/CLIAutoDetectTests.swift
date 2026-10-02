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
        let key = args.last ?? ""
        return byCommand[key] ?? ("", "not stubbed: \(args)", 1)
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return storedCalls
    }
}

final class CLIAutoDetectTests: XCTestCase {
    func testDetectsEverythingWhenTheCLIAnswersEachCall() {
        let runner = ScriptedRunner(byCommand: [
            "path": (#"{"path":"/Users/alice/.config/devmachine","source":"default"}"#, "", 0),
            "show": (#"""
                {
                  "machines": [
                    {"name": "acme", "hosts": ["100.64.0.5", "203.0.113.10"], "admin_user": "root", "port": 22, "workspaces": ["dash"]},
                    {"name": "mac", "hosts": [], "admin_user": "", "port": 0, "workspaces": [], "self": true}
                  ],
                  "workspaces": [{"name": "dash", "machine": "acme", "user": "dash"}],
                  "domain": "example.com"
                }
                """#, "", 0),
            "aliases": (#"""
                {"aliases": [
                  {"name": "dash-devmachine", "host": "100.64.0.5", "user": "dash", "port": 22},
                  {"name": "dash-devmachine-pub", "host": "203.0.113.10", "user": "dash", "port": 22}
                ]}
                """#, "", 0),
        ])
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        let detected = CLIAutoDetect.detect(cli: { cli })

        XCTAssertEqual(detected.opsRepoPath, "/Users/alice/.config/devmachine")
        XCTAssertEqual(detected.adminMachine, "acme")
        // The tailnet address (100.64.0.0/10) is skipped for the public one.
        XCTAssertEqual(detected.publicIP, "203.0.113.10")
        XCTAssertEqual(detected.baseDomain, "example.com")
        XCTAssertEqual(detected.workspaceAliases, ["dash": "dash-devmachine"])
    }

    func testAFailedCallLeavesItsPartUndetected() {
        let runner = ScriptedRunner(byCommand: [
            "path": ("", "config folder missing", 1),
            "show": (#"""
                {"machines": [{"name": "acme", "hosts": ["203.0.113.10"], "admin_user": "root", "port": 22, "workspaces": []}],
                 "workspaces": [], "domain": "example.com"}
                """#, "", 0),
        ])
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        let detected = CLIAutoDetect.detect(cli: { cli })

        XCTAssertNil(detected.opsRepoPath)
        XCTAssertEqual(detected.baseDomain, "example.com")
        XCTAssertEqual(detected.adminMachine, "acme")
    }

    func testAWorkspaceWithNoMatchingAliasIsLeftOutOfTheMap() {
        let runner = ScriptedRunner(byCommand: [
            "path": (#"{"path":"/x","source":"default"}"#, "", 0),
            "show": (#"""
                {"machines": [{"name": "acme", "hosts": ["203.0.113.10"], "admin_user": "root", "port": 22, "workspaces": ["dash"]}],
                 "workspaces": [{"name": "dash", "machine": "acme", "user": "dash"}], "domain": "example.com"}
                """#, "", 0),
            "aliases": (#"{"aliases": []}"#, "", 0),
        ])
        let cli = DevmachineCLI(executable: "/opt/devmachine", runner: runner)

        let detected = CLIAutoDetect.detect(cli: { cli })

        XCTAssertEqual(detected.workspaceAliases, [:])
    }

    func testTailscaleAddressDetection() {
        XCTAssertTrue(CLIAutoDetect.isTailscaleAddress("100.64.0.5"))
        XCTAssertTrue(CLIAutoDetect.isTailscaleAddress("100.127.255.254"))
        XCTAssertFalse(CLIAutoDetect.isTailscaleAddress("100.63.0.1"))
        XCTAssertFalse(CLIAutoDetect.isTailscaleAddress("203.0.113.10"))
        XCTAssertFalse(CLIAutoDetect.isTailscaleAddress("not-an-ip"))
    }
}

final class CLIDetectedSettingsFillingTests: XCTestCase {
    private let detected = CLIDetectedSettings(
        opsRepoPath: "/Users/alice/.config/devmachine", adminMachine: "acme",
        publicIP: "203.0.113.10", baseDomain: "example.com",
        workspaceAliases: ["acme": "acme-devmachine"])

    func testEmptyFieldsTakeWhatTheCLIReports() {
        let filled = detected.filling(.empty)
        XCTAssertEqual(filled.opsRepoPath, "/Users/alice/.config/devmachine")
        XCTAssertEqual(filled.publicIP, "203.0.113.10")
        XCTAssertEqual(filled.baseDomain, "example.com")
        XCTAssertEqual(filled.workspaceAliases, ["acme": "acme-devmachine"])
    }

    func testAValueThePersonSetIsKept() {
        var mine = AppSettings.empty
        mine.opsRepoPath = "/Users/alice/other"
        mine.publicIP = "203.0.113.99"
        let filled = detected.filling(mine)
        XCTAssertEqual(filled.opsRepoPath, "/Users/alice/other")
        XCTAssertEqual(filled.publicIP, "203.0.113.99")
        XCTAssertEqual(filled.baseDomain, "example.com")
    }

    func testNothingDetectedChangesNothing() {
        var mine = AppSettings.empty
        mine.hostAlias = "lab"
        XCTAssertEqual(CLIDetectedSettings.empty.filling(mine), mine)
    }
}
