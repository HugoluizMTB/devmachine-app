import XCTest
@testable import DevmachineCore

final class MachineObservedTests: XCTestCase {
    private let macJSON = """
        {"name":"studio","hosts":["203.0.113.10"],"admin_user":"alice","port":22,"workspaces":[],
         "packages":["mac-ports"],"location":"external","platform":"macos","future_field":1,
         "observed":{"observed_at":"2026-10-05T15:22:00-03:00","system":"Darwin","os_family":"Darwin",
           "distribution":"MacOSX","distribution_version":"15.7.9","pkg_mgr":"macports","service_mgr":"launchd",
           "architecture":"x86_64","ansible_playbook":"/opt/local/bin/ansible-playbook-3.14",
           "path_prefix":["/opt/local/bin","/opt/local/sbin"],"new_fact":"x"}}
        """

    private func observed(
        system: String, distribution: String = "", version: String = "", architecture: String = ""
    ) -> MachineObserved {
        MachineObserved(
            system: system, distribution: distribution, distributionVersion: version, architecture: architecture)
    }

    func testParsesTheObservedPartOfMachinesShow() throws {
        let fact = try XCTUnwrap(MachineObserved.parse(macJSON))
        XCTAssertEqual(fact, observed(system: "Darwin", distribution: "MacOSX", version: "15.7.9", architecture: "x86_64"))
    }

    func testAMachineNeverReadHasNoObservedFacts() {
        XCTAssertNil(MachineObserved.parse(#"{"name":"main","hosts":["203.0.113.10"]}"#))
        XCTAssertNil(MachineObserved.parse("not json"))
    }

    func testMissingKeysAreEmptyNotAFailure() throws {
        let fact = try XCTUnwrap(MachineObserved.parse(#"{"name":"main","observed":{"system":"Linux"}}"#))
        XCTAssertEqual(fact, observed(system: "Linux"))
    }

    func testAskedWithTheGlobalFormatFlag() {
        XCTAssertEqual(MachineObserved.arguments(machine: "studio"), ["--format", "json", "machines", "show", "studio"])
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
        XCTAssertNil(observed(system: "").displayName)
    }

    func testSystemLineAddsTheArchitecture() {
        XCTAssertEqual(
            observed(system: "Linux", distribution: "Ubuntu", version: "24.04", architecture: "x86_64").systemLine,
            "Ubuntu 24.04 · x86_64")
        XCTAssertEqual(
            observed(system: "Linux", distribution: "Archlinux", architecture: "aarch64").systemLine,
            "Arch Linux · aarch64")
        XCTAssertEqual(observed(system: "Darwin", distribution: "MacOSX", version: "15.7.9").systemLine, "macOS 15.7")
        XCTAssertNil(observed(system: "", architecture: "x86_64").systemLine)
    }

    func testSystemLineForAMachine() {
        let ubuntu = observed(system: "Linux", distribution: "Ubuntu", version: "24.04", architecture: "x86_64")
        XCTAssertEqual(MachineObserved.systemLine(ubuntu, isSelf: false), "Ubuntu 24.04 · x86_64")
        XCTAssertNil(MachineObserved.systemLine(nil, isSelf: false))
        XCTAssertEqual(MachineObserved.systemLine(nil, isSelf: true), "macOS")
    }
}
