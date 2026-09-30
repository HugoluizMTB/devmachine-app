import Foundation
import XCTest
@testable import DevmachineApp

final class HarnessLocatorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-locator-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testSearchesKnownDirectoriesAfterInheritedPath() throws {
        let executable = try makeExecutable(named: "codex")
        let locator = SystemExecutableLocator(path: "/missing", knownDirectories: [directory], loginShellLookup: nil)

        XCTAssertEqual(locator.executable(named: "codex"), executable)
    }

    func testDefaultKnownDirectoriesIncludeCommonCLILocations() {
        let locator = SystemExecutableLocator(path: "")
        let directories = locator.searchDirectories

        XCTAssertTrue(directories.contains(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin")))
        XCTAssertTrue(directories.contains(URL(fileURLWithPath: "/opt/homebrew/bin")))
        XCTAssertTrue(directories.contains(URL(fileURLWithPath: "/usr/local/bin")))
    }

    func testRejectsAnExecutableDirectory() throws {
        let executableDirectory = directory.appendingPathComponent("claude", isDirectory: true)
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableDirectory.path)
        let locator = SystemExecutableLocator(path: directory.path, knownDirectories: [], loginShellLookup: nil)

        XCTAssertNil(locator.executable(named: "claude"))
    }

    func testReturnsTheResolvedTargetOfAnExecutableSymlink() throws {
        let target = try makeExecutable(named: "codex-target")
        let symlink = directory.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        let locator = SystemExecutableLocator(path: directory.path, knownDirectories: [], loginShellLookup: nil)

        XCTAssertEqual(locator.executable(named: "codex"), target)
    }

    func testFallsBackToTheLoginShellWhenNoDirectoryHasTheCLI() throws {
        let shellDirectory = directory.appendingPathComponent("node/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: shellDirectory, withIntermediateDirectories: true)
        let executable = shellDirectory.appendingPathComponent("codex")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let locator = SystemExecutableLocator(
            path: "/missing", knownDirectories: [], loginShellLookup: { _ in executable.path })

        XCTAssertEqual(locator.executable(named: "codex"), executable)
    }

    func testSkipsADanglingSymlinkAndAsksTheLoginShell() throws {
        let dangling = directory.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(
            at: dangling, withDestinationURL: directory.appendingPathComponent("removed/codex"))
        let installed = try makeExecutable(named: "codex-installed")
        let locator = SystemExecutableLocator(
            path: directory.path, knownDirectories: [], loginShellLookup: { _ in installed.path })

        XCTAssertEqual(locator.executable(named: "codex"), installed)
    }

    func testIgnoresALoginShellAnswerThatIsNotAnExecutablePath() {
        let locator = SystemExecutableLocator(
            path: "/missing", knownDirectories: [], loginShellLookup: { _ in "codex: aliased to codex --yolo" })

        XCTAssertNil(locator.executable(named: "codex"))
    }

    func testReadsTheLastAbsolutePathFromNoisyShellOutput() {
        let output = "welcome to zsh\n/Users/alice/.local/share/mise/installs/node/lts/bin/codex\n"

        XCTAssertEqual(
            SystemExecutableLocator.commandPath(fromShellOutput: output),
            "/Users/alice/.local/share/mise/installs/node/lts/bin/codex")
        XCTAssertNil(SystemExecutableLocator.commandPath(fromShellOutput: "codex: aliased to codex\n"))
    }

    private func makeExecutable(named name: String) throws -> URL {
        let executable = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }
}
