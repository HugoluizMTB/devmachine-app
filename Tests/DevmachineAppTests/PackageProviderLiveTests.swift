import XCTest
import DevmachineCore
@testable import DevmachineApp

/// Runs the real CLI named by `DEVMACHINE_WIDGETS_E2E` against a temp
/// configuration whose only machine is `here` (`self: true`), where no
/// package was ever synced. Skipped otherwise. Nothing runs over ssh.
final class PackageProviderLiveTests: XCTestCase {
    private var folder: URL?

    override func tearDown() {
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        super.tearDown()
    }

    private func environment() throws -> SourceRunEnvironment {
        let inherited = ProcessInfo.processInfo.environment
        guard let binary = inherited["DEVMACHINE_WIDGETS_E2E"], !binary.isEmpty else {
            throw XCTSkip("set DEVMACHINE_WIDGETS_E2E to a devmachine binary")
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackageProviderLiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        try Data("machines:\n  - name: here\n    self: true\n".utf8).write(to: folder.appendingPathComponent("config.yml"))
        var variables = inherited
        variables["DEVMACHINE_CONFIG"] = folder.path
        variables["DEVMACHINE_KEYCHAIN"] = "off"
        variables["DEVMACHINE_NO_UPDATE_HINT"] = "1"
        let captured = variables
        return SourceRunEnvironment(
            cli: { CLIInvocationContext(executable: binary, environment: captured) },
            localEnvironment: captured, home: NSHomeDirectory())
    }

    private func request(_ with: [String: String]) -> SourceRunRequest {
        let source = WidgetSource.packageProvider(PackageProviderSource(
            name: "acme-tools/load", with: with, target: .machine("here"), every: .interval(30), timeout: 30,
            returns: ["load": "number"]))
        return SourceRunRequest(instanceID: "live", source: ResolvedSource(
            source: source, view: WidgetView(kind: "number"), every: .interval(30), needsApproval: false,
            package: "acme-tools", packagePath: nil))
    }

    func testTheRealCLITakesThePackageProviderArgv() async throws {
        let runner = PackageProviderRunner(launcher: FoundationProcessLauncher(), environment: try environment())
        let marker = folder!.appendingPathComponent("INJECTED").path
        do {
            _ = try await runner.fetch(request(["path": "x; touch \(marker)", "all": "--yes"]))
            XCTFail("a package never synced on here cannot answer")
        } catch let error as SourceError {
            switch error {
            case let .neverRan(reason), let .exited(_, reason):
                XCTAssertTrue(reason.contains("acme-tools"), reason)
            case let .needsNewerCLI(reason):
                XCTFail("the CLI did not take the argv: \(reason)")
            default:
                XCTFail("\(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker))
    }
}
