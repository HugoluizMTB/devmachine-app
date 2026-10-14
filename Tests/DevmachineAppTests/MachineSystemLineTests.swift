import Foundation
import XCTest
import DevmachineCore
@testable import DevmachineApp

/// An Ubuntu server (`main`), an Arch one (`staging`), a remote Mac
/// (`studio`), a server nothing has read yet (`fresh`) and this Mac
/// (`laptop`). An older CLI reports no `platform` and has no `machines show`.
private final class SystemLineCLIRunner: CommandRunner, @unchecked Sendable {
    let reportsPlatforms: Bool
    private let lock = NSLock()
    private var asked: [String] = []

    init(reportsPlatforms: Bool = true) {
        self.reportsPlatforms = reportsPlatforms
    }

    var shown: [String] { lock.withLock { asked } }

    private var machines: String {
        func platform(_ value: String) -> String { reportsPlatforms ? #","platform":"\#(value)""# : "" }
        return """
        [{"name":"main","hosts":["203.0.113.10"]\(platform("linux"))},
         {"name":"staging","hosts":["203.0.113.12"]\(platform("linux"))},
         {"name":"studio","hosts":["203.0.113.11"]\(platform("macos"))},
         {"name":"fresh","hosts":["203.0.113.13"]},
         {"name":"laptop","self":true\(platform("macos"))}]
        """
    }

    func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        switch args {
        case ["version"]:
            return reportsPlatforms ? "devmachine 0.8.0\n" : "devmachine 0.7.30\n"
        case ["--format", "json", "config", "path"]:
            return #"{"path":"/Users/alice/.config/devmachine","source":"default"}"#
        case ["--format", "json", "machines", "list"]:
            return machines
        case ["--format", "json", "config", "show"]:
            return #"{"machines":\#(machines),"workspaces":[],"domain":"example.com"}"#
        case ["--format", "json", "packages", "list"]:
            return #"{"packages":[]}"#
        default:
            guard reportsPlatforms, args.count == 5, Array(args.prefix(4)) == ["--format", "json", "machines", "show"]
            else { throw DevmachineCLIError.commandFailed("unexpected \(args)") }
            lock.withLock { asked.append(args[4]) }
            switch args[4] {
            case "main":
                return #"""
                {"name":"main","observed":{"system":"Linux","distribution":"Ubuntu","distribution_version":"24.04",
                 "architecture":"x86_64"}}
                """#
            case "staging":
                return #"{"name":"staging","observed":{"system":"Linux","distribution":"Archlinux","architecture":"aarch64"}}"#
            case "studio":
                return #"""
                {"name":"studio","observed":{"system":"Darwin","distribution":"MacOSX","distribution_version":"15.7.9"}}
                """#
            default:
                throw DevmachineCLIError.commandFailed("no machine \(args[4])")
            }
        }
    }
}

@MainActor
final class MachineSystemLineTests: XCTestCase {
    private let expected: [String: String] = [
        "main": "Ubuntu 24.04 · x86_64", "staging": "Arch Linux · aarch64", "studio": "macOS 15.7", "laptop": "macOS",
    ]

    func testSettingsShowsTheSystemOnlyOnceItIsKnown() throws {
        let runner = SystemLineCLIRunner()
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: runner)
        let snap = try MachinesReader.read(cli: cli, fileExists: { _ in true })
        let lines = Dictionary(uniqueKeysWithValues: snap.machines.map { ($0.name, $0.systemLine) })
        XCTAssertEqual(lines.compactMapValues { $0 }, expected)
        XCTAssertEqual(lines["fresh"], .some(nil))
    }

    func testOnlyAMachineTheCLIHasReadIsAsked() throws {
        let runner = SystemLineCLIRunner()
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: runner)
        _ = try MachinesReader.read(cli: cli, fileExists: { _ in true })
        XCTAssertEqual(runner.shown, ["main", "staging", "studio", "laptop"])
    }

    func testAnOlderCLIShowsOnlyThisMac() throws {
        let runner = SystemLineCLIRunner(reportsPlatforms: false)
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: runner)
        let snap = try MachinesReader.read(cli: cli, fileExists: { _ in true })
        XCTAssertEqual(snap.machines.compactMap { machine in machine.systemLine.map { "\(machine.name): \($0)" } }, ["laptop: macOS"])
        XCTAssertTrue(runner.shown.isEmpty)
        let packages = try PackagesReader.read(cli: cli, readLock: { _ in .missing })
        XCTAssertEqual(packages.systemLines, ["laptop": "macOS"])
    }

    func testThePackagesPickerShowsEachMachinesSystem() throws {
        let cli = DevmachineCLI(executable: "/fake/devmachine", runner: SystemLineCLIRunner())
        let snap = try PackagesReader.read(cli: cli, readLock: { _ in .missing })
        XCTAssertEqual(snap.systemLines, expected)
        let options = PackagesHeader.options(snap.targets, scope: "machine", all: "All machines", systems: snap.systemLines)
        XCTAssertEqual(options.map(\.title), [
            "All machines", "main · Ubuntu 24.04 · x86_64", "staging · Arch Linux · aarch64", "studio · macOS 15.7",
            "fresh", "laptop · macOS",
        ])
    }

    func testTheWorkspacePickerKeepsItsNames() {
        let targets: [PackageTarget] = [.machine("main", isSelf: false), .workspace("acme", machine: "main")]
        let options = PackagesHeader.options(
            targets, scope: "workspace", all: "All workspaces", systems: ["main": "Ubuntu 24.04 · x86_64"])
        XCTAssertEqual(options.map(\.title), ["All workspaces", "acme on main"])
    }

    func testTheDemoMachinesHaveSystems() {
        let lines = DemoData.machinesSnapshot.machines.map(\.systemLine)
        XCTAssertEqual(lines, ["Ubuntu 24.04 · x86_64", "Arch Linux · aarch64", "macOS"])
        XCTAssertEqual(DemoPackages.macSnapshot().systemLines, [
            "main": "Ubuntu 24.04 · x86_64", "staging": "Arch Linux · aarch64", "studio": "macOS 15.7 · arm64",
        ])
    }
}
