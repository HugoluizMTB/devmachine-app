import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

/// A CLI with a Linux server (`main`), a remote Mac (`studio`), a server
/// nothing has read yet (`fresh`) and this Mac (`laptop`).
private struct MultiSystemCLIRunner: CommandRunner {
    var version = "devmachine 0.8.0\n"

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        switch args {
        case ["version"]:
            return version
        case ["--format", "json", "config", "show"]:
            return #"""
            {"machines":[{"name":"main"},{"name":"studio"},{"name":"fresh"},{"name":"laptop","self":true}],
             "workspaces":[{"name":"acme","machine":"main","user":"acme"},
                           {"name":"beta","machine":"studio","user":"beta"}],"domain":"example.com"}
            """#
        case ["--format", "json", "machines", "list"]:
            return #"""
            [{"name":"main","hosts":["203.0.113.10"]},{"name":"studio","hosts":["203.0.113.11"]},
             {"name":"fresh","hosts":["203.0.113.12"]},{"name":"laptop","self":true}]
            """#
        case ["--format", "json", "packages", "list"]:
            return #"""
            {"packages":[
              {"name":"docker","scope":"machine","source":"release","platforms":["linux"],"installed_on":[]},
              {"name":"mac-ports","scope":"machine","source":"release","platforms":["macos"],"installed_on":[]},
              {"name":"git","scope":"machine","source":"release","platforms":[],"installed_on":[]}
            ]}
            """#
        case ["--format", "json", "config", "path"]:
            return #"{"path":"/Users/alice/.config/devmachine","source":"default"}"#
        case ["--format", "json", "machines", "show", "main"]:
            return #"""
            {"name":"main","observed":{"system":"Linux","distribution":"Archlinux","path_prefix":[]}}
            """#
        case ["--format", "json", "machines", "show", "studio"]:
            return #"""
            {"name":"studio","observed":{"system":"Darwin","distribution":"MacOSX",
             "distribution_version":"15.7.9","path_prefix":["/opt/local/bin","/opt/local/sbin"]}}
            """#
        case ["--format", "json", "machines", "show", "fresh"], ["--format", "json", "machines", "show", "laptop"]:
            return #"{"name":"fresh"}"#
        default:
            throw DevmachineCLIError.commandFailed("unexpected \(args)")
        }
    }
}

final class MachineSystemTests: XCTestCase {
    private func cli(version: String = "devmachine 0.8.0\n") -> DevmachineCLI {
        DevmachineCLI(executable: "/fake/devmachine", runner: MultiSystemCLIRunner(version: version))
    }

    func testMachinesShowGivesTheObservedSystem() throws {
        XCTAssertEqual(try cli().observed(machine: "studio")?.displayName, "macOS 15.7")
        XCTAssertNil(try cli().observed(machine: "fresh"))
    }

    func testAnOlderCLIIsNotAskedAndAFailedReadIsLeftOut() {
        XCTAssertEqual(cli().observed(machines: ["main", "nope"], cliVersion: MachineObserved.minimumCLIVersion).keys
            .sorted(), ["main"])
        XCTAssertTrue(cli().observed(machines: ["main"], cliVersion: SemanticVersion(major: 0, minor: 7, patch: 32))
            .isEmpty)
    }

    func testThePackagesPageKnowsWhatEachMachineRuns() throws {
        let snap = try PackagesReader.read(cli: cli(), readLock: { _ in .missing })
        XCTAssertEqual(snap.platforms.platform(of: .machine("main", isSelf: false)), .linux)
        XCTAssertEqual(snap.platforms.platform(of: .machine("studio", isSelf: false)), .macos)
        XCTAssertEqual(snap.platforms.platform(of: .workspace("beta", machine: "studio")), .macos)
        XCTAssertNil(snap.platforms.platform(of: .machine("fresh", isSelf: false)))
        XCTAssertEqual(snap.platforms.platform(of: .machine("laptop", isSelf: true)), .macos)
        XCTAssertEqual(snap.systemNames, ["main": "Arch Linux", "studio": "macOS 15.7"])
    }

    func testARowSaysWhyAPackageDoesNotRunOnTheFocusedMachine() throws {
        let snap = try PackagesReader.read(cli: cli(), readLock: { _ in .missing })
        let entry = { (name: String) in try XCTUnwrap(snap.entries.first { $0.name == name }) }
        let studio = PackageTarget.machine("studio", isSelf: false)
        let main = PackageTarget.machine("main", isSelf: false)
        let fresh = PackageTarget.machine("fresh", isSelf: false)
        XCTAssertEqual(snap.unsupported(try entry("docker"), on: [studio]), "Linux only")
        XCTAssertEqual(snap.unsupported(try entry("mac-ports"), on: [main]), "macOS only")
        XCTAssertNil(snap.unsupported(try entry("git"), on: [studio]))
        XCTAssertNil(snap.unsupported(try entry("docker"), on: [fresh]))
        XCTAssertNil(snap.unsupported(try entry("docker"), on: []))
        XCTAssertNil(snap.unsupported(try entry("docker"), on: [studio, main]))
    }

    func testTheInstallPlanLeavesALinuxPackageOffARemoteMac() throws {
        let snap = try PackagesReader.read(cli: cli(), readLock: { _ in .missing })
        let studio = PackageTarget.machine("studio", isSelf: false)
        let batch = PackagesSettingsView.plan(["docker", "mac-ports"], on: [studio], .install, snapshot: snap)
        XCTAssertEqual(batch.edits.map(\.changes), [PackageChanges(adds: ["mac-ports"], removes: [])])
        XCTAssertEqual(batch.skips.map(\.reason), ["Linux only."])
    }

    func testAnOlderCLIKeepsTreatingServersAsLinux() throws {
        let snap = try PackagesReader.read(cli: cli(version: "devmachine 0.7.32\n"), readLock: { _ in .missing })
        XCTAssertEqual(snap.platforms.platform(of: .machine("studio", isSelf: false)), .linux)
        XCTAssertTrue(snap.systemNames.isEmpty)
    }

    func testSettingsShowsTheSystemOnlyOnceItIsKnown() throws {
        let snap = try MachinesReader.read(cli: cli(), fileExists: { _ in true })
        let rows = Dictionary(uniqueKeysWithValues: snap.machines.map { ($0.name, MachineSettingsRow.system($0)) })
        XCTAssertEqual(rows["main"], "Arch Linux")
        XCTAssertEqual(rows["studio"], "macOS 15.7")
        XCTAssertEqual(rows["fresh"], .some(nil))
        XCTAssertEqual(rows["laptop"], "macOS")
    }

    func testEachWorkspaceAliasGetsItsMachinesPathPrefix() {
        var snapshot = ReadinessSnapshot()
        snapshot.workspaceMachines = ["acme": "main", "beta": "studio", "gamma": "fresh"]
        snapshot.observed = [
            "main": MachineObserved(system: "Linux"),
            "studio": MachineObserved(system: "Darwin", pathPrefix: ["/opt/homebrew/bin"]),
        ]
        let hosts = AppModel.remoteHosts(
            workspaces: [Workspace(name: "acme", alias: "acme-devmachine"), Workspace(name: "beta", alias: "beta-devmachine"),
                         Workspace(name: "gamma", alias: "gamma-devmachine"), .local],
            snapshot: snapshot)
        XCTAssertEqual(hosts["beta-devmachine"], RemoteHosts.Host(system: "Darwin", pathPrefix: ["/opt/homebrew/bin"]))
        XCTAssertEqual(hosts["acme-devmachine"], RemoteHosts.Host(system: "Linux", pathPrefix: []))
        XCTAssertNil(hosts["gamma-devmachine"])
        XCTAssertNil(hosts["local"])
        XCTAssertTrue(AppModel.remoteHosts(workspaces: [], snapshot: nil).isEmpty)
    }

    func testARemoteMacsFilesAreListedWithLs() {
        let hosts = RemoteHosts(["beta-devmachine": .init(system: "Darwin", pathPrefix: [])])
        XCTAssertTrue(CommandTarget.remote(alias: "beta-devmachine", session: "dev").listsPortably(hosts: hosts))
        XCTAssertFalse(CommandTarget.remote(alias: "acme-devmachine", session: "dev").listsPortably(hosts: hosts))
        XCTAssertTrue(CommandTarget.local(session: "dev", path: "/Users/alice").listsPortably(hosts: hosts))
    }

    func testRemoteServicePutsThePrefixOnTheCommandOnly() {
        XCTAssertEqual(RemoteService.forHost(["tmux ls"], alias: "unknown-devmachine"), ["tmux ls"])
        XCTAssertEqual(RemoteService.forHost([], alias: "unknown-devmachine"), [])
    }
}
