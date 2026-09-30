import XCTest
@testable import DevmachineCore

private final class RecordingRunner: CommandRunner, @unchecked Sendable {
    let exitCode: Int32
    private(set) var calls: [(String, [String])] = []

    init(exitCode: Int32) {
        self.exitCode = exitCode
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }

    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        calls.append((executable, args))
        return ("", "", exitCode)
    }
}

final class AppInstallMethodTests: XCTestCase {
    private func detect(
        bundle: String = "/Applications/Devmachine.app", files: Set<String>, brewListExit: Int32 = 1,
        runner: RecordingRunner? = nil
    ) -> AppInstallMethod {
        let runner = runner ?? RecordingRunner(exitCode: brewListExit)
        return AppInstallMethodDetector(
            bundlePath: bundle, fileExists: { files.contains($0) }, runner: runner
        ).detect()
    }

    func testACaskroomEntryMeansHomebrew() {
        let method = detect(files: ["/opt/homebrew/bin/brew", "/opt/homebrew/Caskroom/devmachine-app"])
        XCTAssertEqual(method, .homebrew(brew: "/opt/homebrew/bin/brew"))
    }

    func testAnIntelPrefixIsFoundToo() {
        let method = detect(files: ["/usr/local/bin/brew", "/usr/local/Caskroom/devmachine-app"])
        XCTAssertEqual(method, .homebrew(brew: "/usr/local/bin/brew"))
    }

    func testBrewListSucceedingMeansHomebrew() {
        let runner = RecordingRunner(exitCode: 0)
        let method = detect(files: ["/opt/homebrew/bin/brew"], runner: runner)
        XCTAssertEqual(method, .homebrew(brew: "/opt/homebrew/bin/brew"))
        XCTAssertEqual(runner.calls.first?.0, "/opt/homebrew/bin/brew")
        XCTAssertEqual(runner.calls.first?.1, ["list", "--cask", "devmachine-app"])
    }

    func testBrewWithoutTheCaskIsAManualInstall() {
        XCTAssertEqual(detect(files: ["/opt/homebrew/bin/brew"], brewListExit: 1), .manual)
    }

    func testNoBrewIsAManualInstall() {
        XCTAssertEqual(detect(files: []), .manual)
    }

    func testACopyOutsideApplicationsIsManualEvenWithTheCask() {
        let runner = RecordingRunner(exitCode: 0)
        let method = detect(
            bundle: "/Users/alice/Downloads/Devmachine.app",
            files: ["/opt/homebrew/bin/brew", "/opt/homebrew/Caskroom/devmachine-app"], runner: runner)
        XCTAssertEqual(method, .manual)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testATrailingSlashOnTheBundlePathStillMatches() {
        let method = detect(
            bundle: "/Applications/Devmachine.app/",
            files: ["/opt/homebrew/bin/brew", "/opt/homebrew/Caskroom/devmachine-app"])
        XCTAssertEqual(method, .homebrew(brew: "/opt/homebrew/bin/brew"))
    }

    func testTheHomebrewCommands() {
        XCTAssertEqual(HomebrewAppUpgrade.displayCommand, "brew upgrade --cask devmachine-app")
        XCTAssertEqual(HomebrewAppUpgrade.arguments, ["upgrade", "--cask", "mydevmachine/tap/devmachine-app"])
    }
}
