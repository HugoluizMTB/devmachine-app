import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

/// A Linux server (`main`), a remote Mac (`studio`), a server nothing has
/// read yet (`fresh`) and this Mac (`laptop`), which the CLI reports or not.
private struct SystemsCLIRunner: CommandRunner {
    var reportsPlatforms = true

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        switch args {
        case ["version"]:
            return "devmachine 0.8.0\n"
        case ["--format", "json", "config", "show"]:
            let main = reportsPlatforms ? #","platform":"linux""# : ""
            let studio = reportsPlatforms ? #","platform":"macos""# : ""
            return """
            {"machines":[{"name":"main"\(main)},{"name":"studio"\(studio)},{"name":"fresh"},
                         {"name":"laptop","self":true}],
             "workspaces":[{"name":"acme","machine":"main","user":"acme"},
                           {"name":"beta","machine":"studio","user":"beta"},
                           {"name":"gamma","machine":"laptop","user":"alice"}],"domain":"example.com"}
            """
        case ["--format", "json", "packages", "list"]:
            return #"""
            {"packages":[
              {"name":"docker","scope":"machine","source":"release","platforms":["linux"],
               "installed_on":["machine studio"]},
              {"name":"mac-ports","scope":"machine","source":"release","platforms":["macos"],"installed_on":[]},
              {"name":"git","scope":"machine","source":"release","platforms":[],"installed_on":[]},
              {"name":"remote-control","scope":"workspace","source":"release","platforms":["linux"],"installed_on":[]}
            ]}
            """#
        case ["--format", "json", "config", "path"]:
            return #"{"path":"/Users/alice/.config/devmachine","source":"default"}"#
        default:
            throw DevmachineCLIError.commandFailed("unexpected \(args)")
        }
    }
}

final class PackageSystemTests: XCTestCase {
    private let main = PackageTarget.machine("main", isSelf: false)
    private let studio = PackageTarget.machine("studio", isSelf: false)
    private let fresh = PackageTarget.machine("fresh", isSelf: false)
    private let laptop = PackageTarget.machine("laptop", isSelf: true)
    private let beta = PackageTarget.workspace("beta", machine: "studio")
    private let gamma = PackageTarget.workspace("gamma", machine: "laptop")

    private func read(reportsPlatforms: Bool = true) throws -> PackagesSnapshot {
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: SystemsCLIRunner(reportsPlatforms: reportsPlatforms))
        return try PackagesReader.read(cli: cli, readLock: { _ in .missing })
    }

    private func entry(_ snap: PackagesSnapshot, _ name: String) throws -> PackageEntry {
        try XCTUnwrap(snap.entries.first { $0.name == name })
    }

    private func fit(_ snap: PackagesSnapshot, _ name: String, on focus: [PackageTarget]) throws -> PackageSystemFit {
        snap.systemFit(try entry(snap, name), on: focus, statuses: PackagesSettingsView.statuses(snap))
    }

    func testEachMachineAndWorkspaceHasItsSystem() throws {
        let snap = try read()
        XCTAssertEqual(snap.platform(of: main), "linux")
        XCTAssertEqual(snap.platform(of: studio), "macos")
        XCTAssertEqual(snap.platform(of: beta), "macos")
        XCTAssertNil(snap.platform(of: fresh))
        XCTAssertEqual(snap.platform(of: laptop), "macos")
        XCTAssertEqual(snap.platform(of: gamma), "macos")
    }

    func testARowSaysWhyAPackageDoesNotRunOnThePickedMachine() throws {
        let snap = try read()
        XCTAssertEqual(try fit(snap, "mac-ports", on: [main]), .blocked("macOS only"))
        XCTAssertEqual(try fit(snap, "docker", on: [laptop]), .blocked("Linux only"))
        XCTAssertEqual(try fit(snap, "remote-control", on: [beta]), .blocked("Linux only"))
        XCTAssertEqual(try fit(snap, "git", on: [studio]), .fits)
        XCTAssertEqual(try fit(snap, "docker", on: [fresh]), .fits)
        XCTAssertEqual(try fit(snap, "docker", on: []), .fits)
    }

    func testAnInstalledPackageForAnotherSystemCanStillBeTicked() throws {
        let snap = try read()
        XCTAssertEqual(try fit(snap, "docker", on: [studio]), .removableOnly("Linux only"))
    }

    func testOnlyThePickedTargetsOfThePackagesKindCount() throws {
        let snap = try read()
        XCTAssertEqual(try fit(snap, "mac-ports", on: [main, beta]), .blocked("macOS only"))
        XCTAssertEqual(try fit(snap, "remote-control", on: [main, beta]), .blocked("Linux only"))
        XCTAssertEqual(try fit(snap, "remote-control", on: [studio]), .fits)
    }

    func testInstallLeavesOutAMachineOfAnotherSystemAndRemovalStillWorks() throws {
        let snap = try read()
        let install = PackagesSettingsView.plan(["docker", "mac-ports"], on: [studio], .install, snapshot: snap)
        XCTAssertEqual(install.edits.map(\.changes), [PackageChanges(adds: ["mac-ports"], removes: [])])
        XCTAssertEqual(install.skips.map(\.reason), ["Linux only."])
        let onMain = PackagesSettingsView.plan(["mac-ports"], on: [main], .install, snapshot: snap)
        XCTAssertTrue(onMain.isEmpty)
        XCTAssertEqual(onMain.skips.map(\.reason), ["macOS only."])
        let remove = PackagesSettingsView.plan(["docker"], on: [studio], .remove, snapshot: snap)
        XCTAssertEqual(remove.edits.map(\.changes), [PackageChanges(adds: [], removes: ["docker"])])
    }

    func testAnOlderCLIBlocksNothingButThisMac() throws {
        let snap = try read(reportsPlatforms: false)
        XCTAssertNil(snap.platform(of: main))
        XCTAssertNil(snap.platform(of: studio))
        XCTAssertEqual(try fit(snap, "mac-ports", on: [main]), .fits)
        XCTAssertEqual(try fit(snap, "docker", on: [studio]), .fits)
        XCTAssertEqual(try fit(snap, "docker", on: [laptop]), .blocked("Linux only"))
    }
}
