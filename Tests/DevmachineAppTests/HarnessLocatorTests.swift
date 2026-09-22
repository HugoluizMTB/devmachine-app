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
        let locator = SystemExecutableLocator(path: "/missing", knownDirectories: [directory])

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
        let locator = SystemExecutableLocator(path: directory.path, knownDirectories: [])

        XCTAssertNil(locator.executable(named: "claude"))
    }

    func testReturnsTheResolvedTargetOfAnExecutableSymlink() throws {
        let target = try makeExecutable(named: "codex-target")
        let symlink = directory.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        let locator = SystemExecutableLocator(path: directory.path, knownDirectories: [])

        XCTAssertEqual(locator.executable(named: "codex"), target)
    }

    private func makeExecutable(named name: String) throws -> URL {
        let executable = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }
}
