import XCTest
@testable import DevmachineApp
import DevmachineCore

final class NetworkMapSourceTests: XCTestCase {
    private let machines = [
        ConfiguredMachine(
            name: "main", hosts: ["100.64.0.10", "203.0.113.10"], adminUser: "root", port: 22,
            workspaces: ["acme"], packages: ["essentials"], isSelf: false, reportedLocation: "hostinger"),
        ConfiguredMachine(
            name: "lab", hosts: ["127.0.0.1"], adminUser: "root", port: 60022, workspaces: ["umbrella"],
            packages: [], isSelf: false),
        ConfiguredMachine(name: "laptop", hosts: [], adminUser: "", port: 0, workspaces: [], packages: [], isSelf: true),
    ]

    func testMachinesCarryTheirLocationCaddyAndKind() {
        let input = NetworkMapSource.input(machines: machines, sites: [:])
        XCTAssertEqual(input.machines.map(\.location), ["hostinger", "local", "local"])
        XCTAssertEqual(input.machines.map(\.hasCaddy), [true, false, false])
        XCTAssertEqual(input.machines.map(\.isLocalVM), [false, true, false])
    }

    func testSitesComeFromEachMachinesListingWithTheirWorkspace() {
        let rows = [
            SubdomainRow(
                site: ExposedSite(host: "app.example.com", port: 3000, workspace: "acme", status: .published),
                resolvedWorkspace: "acme", containerName: nil),
            SubdomainRow(
                site: ExposedSite(host: "media.example.com", port: 8096, workspace: nil, status: .published),
                resolvedWorkspace: "umbrella", containerName: nil),
        ]
        let input = NetworkMapSource.input(machines: machines, sites: ["main": MachineSitesState(rows: rows)])
        XCTAssertEqual(input.sites, [
            NetworkMapInput.Site(host: "app.example.com", servingMachine: "main", workspace: "acme"),
            NetworkMapInput.Site(host: "media.example.com", servingMachine: "main", workspace: "umbrella"),
        ])
    }
}
