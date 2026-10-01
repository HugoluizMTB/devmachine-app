import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func add(_ line: String) { lock.withLock { stored.append(line) } }
    var all: [String] { lock.withLock { stored } }
}

final class ProcessHomebrewUpgraderTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("brew-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func fakeBrew(_ body: String) throws -> String {
        let script = folder.appendingPathComponent("brew")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    func testStreamsEveryLineAndPassesTheCaskArguments() async throws {
        let brew = try fakeBrew(#"echo "args: $*"; echo "==> Upgrading" 1>&2; printf "done""#)
        let lines = Lines()
        try await ProcessHomebrewUpgrader().upgrade(brew: brew, output: lines.add)
        XCTAssertEqual(lines.all, ["args: upgrade --cask mydevmachine/tap/devmachine-app", "==> Upgrading", "done"])
    }

    func testAFailingBrewThrowsItsStatus() async throws {
        let brew = try fakeBrew("echo nope; exit 3")
        let lines = Lines()
        do {
            try await ProcessHomebrewUpgrader().upgrade(brew: brew, output: lines.add)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? UpdateInstallError, .homebrewFailed(3))
        }
        XCTAssertEqual(lines.all, ["nope"])
    }

    func testTheCLIUpdateRunsOnlyCLIOnlyAndStreamsItsLog() async throws {
        let cli = try fakeBrew(#"echo "args: $*"; echo "path: $PATH"; echo "  updated" 1>&2"#)
        let lines = Lines()
        try await ProcessCLIUpdater(executable: { cli }, environment: ["PATH": "/usr/bin:/bin"])
            .updateCLI(output: lines.add)
        XCTAssertEqual(lines.all, ["args: update --cli-only", "path: /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "  updated"])
    }

    func testAFailingCLIUpdateThrowsItsStatus() async throws {
        let cli = try fakeBrew("echo 'error: unknown flag: --cli-only' 1>&2; exit 1")
        let lines = Lines()
        do {
            try await ProcessCLIUpdater(executable: { cli }, environment: [:]).updateCLI(output: lines.add)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? CLIUpdateError, .exited(1))
        }
        XCTAssertEqual(lines.all, ["error: unknown flag: --cli-only"])
    }
}
