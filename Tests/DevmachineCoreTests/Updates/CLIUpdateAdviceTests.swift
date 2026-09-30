import XCTest
@testable import DevmachineCore

final class CLIUpdateAdviceTests: XCTestCase {
    func testALinkIntoTheCellarIsHomebrew() {
        XCTAssertEqual(
            CLIUpdateAdvice.installMethod(resolvedPath: "/opt/homebrew/Cellar/devmachine/0.7.1/bin/devmachine"),
            .homebrew)
        XCTAssertEqual(
            CLIUpdateAdvice.installMethod(resolvedPath: "/usr/local/Cellar/devmachine/0.7.1/bin/devmachine"),
            .homebrew)
        XCTAssertEqual(CLIUpdateAdvice.installMethod(resolvedPath: "/opt/homebrew/bin/devmachine"), .homebrew)
    }

    func testAPlainFileIsTheInstallScript() {
        XCTAssertEqual(CLIUpdateAdvice.installMethod(resolvedPath: "/usr/local/bin/devmachine"), .script)
        XCTAssertEqual(CLIUpdateAdvice.installMethod(resolvedPath: "/Users/alice/.local/bin/devmachine"), .script)
    }

    func testTheCommandForEachMethod() {
        XCTAssertEqual(CLIUpdateAdvice.command(for: .homebrew), "brew upgrade devmachine")
        XCTAssertEqual(CLIUpdateAdvice.command(for: .script), "curl -fsSL https://mydevmachine.sh/install.sh | sh")
    }

    func testANewerReleaseMakesANotice() {
        let latest = GitHubRelease(tagName: "v0.8.0")
        let notice = CLIUpdateAdvice.notice(versionOutput: "0.7.1\n", latest: latest, method: .homebrew)
        XCTAssertEqual(notice, CLIUpdateNotice(
            installed: SemanticVersion("0.7.1")!, latest: SemanticVersion("0.8.0")!,
            command: "brew upgrade devmachine", releaseURL: nil))
    }

    func testNoNoticeWhenCurrentPrereleaseOrUnreadable() {
        XCTAssertNil(CLIUpdateAdvice.notice(
            versionOutput: "0.8.0", latest: GitHubRelease(tagName: "v0.8.0"), method: .script))
        XCTAssertNil(CLIUpdateAdvice.notice(
            versionOutput: "0.7.1", latest: GitHubRelease(tagName: "v0.8.0", isPrerelease: true), method: .script))
        XCTAssertNil(CLIUpdateAdvice.notice(
            versionOutput: "dev", latest: GitHubRelease(tagName: "v0.8.0"), method: .script))
    }
}
