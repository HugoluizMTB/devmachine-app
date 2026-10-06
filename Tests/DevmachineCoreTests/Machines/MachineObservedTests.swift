import XCTest
@testable import DevmachineCore

final class MachineObservedTests: XCTestCase {
    private let macJSON = """
        {"name":"studio","hosts":["203.0.113.10"],"admin_user":"alice","port":22,"workspaces":[],
         "packages":["mac-ports"],"location":"external","future_field":1,
         "observed":{"observed_at":"2026-10-05T15:22:00-03:00","system":"Darwin","os_family":"Darwin",
           "distribution":"MacOSX","distribution_version":"15.7.9","pkg_mgr":"macports","service_mgr":"launchd",
           "architecture":"x86_64","ansible_playbook":"/opt/local/bin/ansible-playbook-3.14",
           "path_prefix":["/opt/local/bin","/opt/local/sbin"],"new_fact":"x"}}
        """

    private func observed(system: String, distribution: String = "", version: String = "") -> MachineObserved {
        MachineObserved(system: system, distribution: distribution, distributionVersion: version)
    }

    func testParsesTheObservedPartOfMachinesShow() throws {
        let fact = try XCTUnwrap(MachineObserved.parse(macJSON))
        XCTAssertEqual(fact.system, "Darwin")
        XCTAssertEqual(fact.distribution, "MacOSX")
        XCTAssertEqual(fact.distributionVersion, "15.7.9")
        XCTAssertEqual(fact.pkgMgr, "macports")
        XCTAssertEqual(fact.architecture, "x86_64")
        XCTAssertEqual(fact.pathPrefix, ["/opt/local/bin", "/opt/local/sbin"])
        XCTAssertEqual(fact.platform, .macos)
    }

    func testAMachineNeverReadHasNoObservedFacts() {
        XCTAssertNil(MachineObserved.parse(#"{"name":"main","hosts":["203.0.113.10"]}"#))
        XCTAssertNil(MachineObserved.parse("not json"))
    }

    func testMissingKeysAreEmptyNotAFailure() throws {
        let fact = try XCTUnwrap(MachineObserved.parse(#"{"name":"main","observed":{"system":"Linux"}}"#))
        XCTAssertEqual(fact.system, "Linux")
        XCTAssertEqual(fact.pathPrefix, [])
        XCTAssertEqual(fact.distribution, "")
    }

    func testAskedWithTheGlobalFormatFlag() {
        XCTAssertEqual(MachineObserved.arguments(machine: "studio"), ["--format", "json", "machines", "show", "studio"])
    }

    func testOnlyACLIWithMachinesShowIsAsked() {
        XCTAssertFalse(MachineObserved.isSupported(cliVersion: nil))
        XCTAssertFalse(MachineObserved.isSupported(cliVersion: SemanticVersion(major: 0, minor: 7, patch: 32)))
        XCTAssertTrue(MachineObserved.isSupported(cliVersion: SemanticVersion(major: 0, minor: 8, patch: 0)))
    }

    func testPlatformAsPackagesNameIt() {
        XCTAssertEqual(observed(system: "Linux").platform, .linux)
        XCTAssertEqual(observed(system: "Darwin").platform, .macos)
        XCTAssertNil(observed(system: "FreeBSD").platform)
    }

    func testSystemNameForPeople() {
        XCTAssertEqual(observed(system: "Darwin", distribution: "MacOSX", version: "15.7.9").displayName, "macOS 15.7")
        XCTAssertEqual(observed(system: "Darwin", distribution: "MacOSX", version: "26").displayName, "macOS 26")
        XCTAssertEqual(observed(system: "Linux", distribution: "Archlinux").displayName, "Arch Linux")
        XCTAssertEqual(observed(system: "Linux", distribution: "Ubuntu", version: "24.04").displayName, "Ubuntu 24.04")
        XCTAssertEqual(observed(system: "Linux", distribution: "Debian", version: "12").displayName, "Debian 12")
        XCTAssertEqual(observed(system: "Linux", distribution: "fedora", version: "41").displayName, "Fedora 41")
        XCTAssertEqual(observed(system: "Linux").displayName, "Linux")
        XCTAssertEqual(observed(system: "Darwin").displayName, "macOS")
    }

    func testHomeFolderFollowsTheSystem() {
        XCTAssertEqual(MachineHome.root(system: "Darwin"), "/Users")
        XCTAssertEqual(MachineHome.root(system: "Linux"), "/home")
        XCTAssertEqual(MachineHome.root(system: nil), "/home")
        XCTAssertEqual(MachineHome.folder(user: "alice", system: "Darwin"), "/Users/alice")
        XCTAssertEqual(MachineHome.folder(user: "alice", system: nil), "/home/alice")
    }
}

final class MachinePlatformsTests: XCTestCase {
    private let mac = MachineObserved(system: "Darwin", distribution: "MacOSX", distributionVersion: "15.7")
    private let arch = MachineObserved(system: "Linux", distribution: "Archlinux")
    private let newCLI = SemanticVersion(major: 0, minor: 8, patch: 0)
    private let oldCLI = SemanticVersion(major: 0, minor: 7, patch: 32)

    private var machines: [MachinePlatforms.Machine] {
        [.init(name: "studio", isSelf: false), .init(name: "box", isSelf: false),
         .init(name: "fresh", isSelf: false), .init(name: "laptop", isSelf: true)]
    }

    func testObservedSystemWinsAndThisComputerIsAMac() {
        let platforms = MachinePlatforms.resolve(
            machines: machines, observed: ["studio": mac, "box": arch], cliVersion: newCLI)
        XCTAssertEqual(platforms.platform(of: .machine("studio", isSelf: false)), .macos)
        XCTAssertEqual(platforms.platform(of: .machine("box", isSelf: false)), .linux)
        XCTAssertEqual(platforms.platform(of: .machine("laptop", isSelf: true)), .macos)
        XCTAssertEqual(platforms.platform(of: .workspace("acme", machine: "studio")), .macos)
    }

    func testAMachineNeverReadIsUnknown() {
        let platforms = MachinePlatforms.resolve(machines: machines, observed: [:], cliVersion: newCLI)
        XCTAssertNil(platforms.platform(of: .machine("fresh", isSelf: false)))
        XCTAssertNil(platforms.platform(of: .workspace("beta", machine: "fresh")))
    }

    func testAnOlderCLIOnlySetUpLinuxServers() {
        let platforms = MachinePlatforms.resolve(machines: machines, observed: [:], cliVersion: oldCLI)
        XCTAssertEqual(platforms.platform(of: .machine("fresh", isSelf: false)), .linux)
        XCTAssertEqual(platforms.platform(of: .machine("laptop", isSelf: true)), .macos)
    }
}
