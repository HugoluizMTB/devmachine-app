import XCTest
@testable import DevmachineCore

final class ExposedSiteDecodingTests: XCTestCase {
    func testARowDecodesItsStatusAndNote() throws {
        let json = #"""
        [
            {"host": "app.example.com", "port": 8080, "workspace": "alice", "status": "published"},
            {"host": "old.example.com", "port": 9090, "status": "unmanaged", "note": "adopt it"}
        ]
        """#
        let rows = try JSONDecoder().decode([ExposedSite].self, from: Data(json.utf8))

        XCTAssertEqual(rows[0], ExposedSite(
            host: "app.example.com", port: 8080, workspace: "alice", status: .published))
        XCTAssertEqual(rows[1], ExposedSite(
            host: "old.example.com", port: 9090, workspace: nil, status: .unmanaged, note: "adopt it"))
    }

    func testAnUnrecognizedStatusDecodesAsUnknownRatherThanFailing() throws {
        let json = #"[{"host": "x.example.com", "port": 1, "status": "from-the-future"}]"#
        let rows = try JSONDecoder().decode([ExposedSite].self, from: Data(json.utf8))

        XCTAssertEqual(rows[0].status, .unknown)
    }
}

final class SubdomainsTabsTests: XCTestCase {
    func testSitesIsAlwaysFirstAndOnlyInstalledProvidersFollow() {
        let tabs = SubdomainsTabs.build(providers: ["Cloudflare", "Hostinger"])

        XCTAssertEqual(tabs, [.sites, .provider("Cloudflare"), .provider("Hostinger")])
    }

    func testNoProvidersMeansOnlyTheSitesTab() {
        XCTAssertEqual(SubdomainsTabs.build(providers: []), [.sites])
    }
}

final class CaddyDetectionTests: XCTestCase {
    func testCaddyItselfCounts() {
        XCTAssertTrue(CaddyDetection.hasCaddy(installedPackageNames: ["caddy"]))
    }

    func testEssentialsCountsAsCaddyToo() {
        XCTAssertTrue(CaddyDetection.hasCaddy(installedPackageNames: ["essentials"]))
    }

    func testNeitherMeansNoCaddy() {
        XCTAssertFalse(CaddyDetection.hasCaddy(installedPackageNames: ["devmachine-app"]))
    }

    func testAnyMachineHavingItIsEnough() {
        let sets: [Set<String>] = [["devmachine-app"], ["essentials"]]
        XCTAssertTrue(CaddyDetection.anyMachineHasCaddy(installedPackageNamesByMachine: sets))
    }

    func testNoMachineHavingItMeansFalse() {
        let sets: [Set<String>] = [["devmachine-app"], []]
        XCTAssertFalse(CaddyDetection.anyMachineHasCaddy(installedPackageNamesByMachine: sets))
    }
}

final class PortWorkspaceMappingTests: XCTestCase {
    func testAPortsOwnerResolvesToTheWorkspaceWithThatUser() {
        let ports = [PortOwner(port: 8810, owner: "alice"), PortOwner(port: 22, owner: "root")]
        let users = [WorkspaceUser(workspace: "acme", user: "alice")]

        XCTAssertEqual(PortWorkspaceMapping.workspace(forPort: 8810, ports: ports, workspaceUsers: users), "acme")
        XCTAssertNil(PortWorkspaceMapping.workspace(forPort: 22, ports: ports, workspaceUsers: users))
    }

    func testAnUnknownPortResolvesToNil() {
        XCTAssertNil(PortWorkspaceMapping.workspace(forPort: 1, ports: [], workspaceUsers: []))
    }
}

final class PublishSuggestionsTests: XCTestCase {
    func testOnlyPortsOwnedByTheWorkspacesUserAreSuggested() {
        let ports = [
            PortOwner(port: 8810, owner: "alice"),
            PortOwner(port: 5432, owner: "bob"),
            PortOwner(port: 22, owner: "root"),
        ]
        let suggestions = PublishSuggestions.ports(forUser: "alice", ports: ports, containers: [])

        XCTAssertEqual(suggestions.map(\.port), [8810])
    }

    func testAnUnambiguousContainerNameIsAttached() {
        let ports = [PortOwner(port: 8810, owner: "alice")]
        let containers = [ContainerStat(name: "web", memUsedBytes: 0, memLimitBytes: 0, cpuPercent: 0, owner: "alice")]

        let suggestions = PublishSuggestions.ports(forUser: "alice", ports: ports, containers: containers)

        XCTAssertEqual(suggestions, [PortSuggestion(port: 8810, containerName: "web")])
    }

    func testTwoContainersForTheSameUserLeavesTheNameOut() {
        let ports = [PortOwner(port: 8810, owner: "alice")]
        let containers = [
            ContainerStat(name: "web", memUsedBytes: 0, memLimitBytes: 0, cpuPercent: 0, owner: "alice"),
            ContainerStat(name: "worker", memUsedBytes: 0, memLimitBytes: 0, cpuPercent: 0, owner: "alice"),
        ]

        let suggestions = PublishSuggestions.ports(forUser: "alice", ports: ports, containers: containers)

        XCTAssertEqual(suggestions, [PortSuggestion(port: 8810, containerName: nil)])
    }

    func testHostnameJoinsTheLabelAndTheDomain() {
        XCTAssertEqual(PublishSuggestions.hostname(label: "acme", domain: "example.com"), "acme.example.com")
    }
}

final class SubdomainRowBuilderTests: XCTestCase {
    func testAManagedSitesWorkspaceComesStraightFromExposeList() {
        let sites = [ExposedSite(host: "app.example.com", port: 8080, workspace: "acme", status: .published)]

        let rows = SubdomainRowBuilder.rows(sites: sites, ports: [], workspaceUsers: [], containers: [])

        XCTAssertEqual(rows[0].workspaceDisplay, "acme")
        XCTAssertFalse(rows[0].workspaceIsContainerHint)
    }

    func testAnUnmanagedSiteResolvesItsWorkspaceFromThePortsOwner() {
        let sites = [ExposedSite(host: "old.example.com", port: 8810, workspace: nil, status: .unmanaged)]
        let ports = [PortOwner(port: 8810, owner: "alice")]
        let users = [WorkspaceUser(workspace: "acme", user: "alice")]

        let rows = SubdomainRowBuilder.rows(sites: sites, ports: ports, workspaceUsers: users, containers: [])

        XCTAssertEqual(rows[0].workspaceDisplay, "acme")
        XCTAssertFalse(rows[0].workspaceIsContainerHint)
    }

    func testWithNoWorkspaceMatchTheContainerNameIsAHint() {
        let sites = [ExposedSite(host: "old.example.com", port: 8810, workspace: nil, status: .unmanaged)]
        let ports = [PortOwner(port: 8810, owner: "alice")]
        let containers = [ContainerStat(name: "web", memUsedBytes: 0, memLimitBytes: 0, cpuPercent: 0, owner: "alice")]

        let rows = SubdomainRowBuilder.rows(sites: sites, ports: ports, workspaceUsers: [], containers: containers)

        XCTAssertEqual(rows[0].workspaceDisplay, "web")
        XCTAssertTrue(rows[0].workspaceIsContainerHint)
    }

    func testWithNeitherAWorkspaceNorAContainerTheDisplayIsNil() {
        let sites = [ExposedSite(host: "apex.example.com", port: 443, workspace: nil, status: .published)]

        let rows = SubdomainRowBuilder.rows(sites: sites, ports: [], workspaceUsers: [], containers: [])

        XCTAssertNil(rows[0].workspaceDisplay)
    }
}

final class RowSearchTests: XCTestCase {
    func testAnEmptyQueryKeepsEveryRow() {
        let rows = ["alice", "bob"]
        XCTAssertEqual(RowSearch.filter(rows, query: "", fields: { [$0] }), rows)
    }

    func testAQueryMatchesAnyField() {
        let rows = [
            ExposedSite(host: "app.example.com", port: 8080, workspace: "alice", status: .published),
            ExposedSite(host: "api.example.com", port: 9090, workspace: "bob", status: .pending),
        ]

        let byHost = RowSearch.filter(rows, query: "app", fields: { [$0.host, $0.workspace ?? ""] })
        XCTAssertEqual(byHost.map(\.host), ["app.example.com"])

        let byWorkspace = RowSearch.filter(rows, query: "bob", fields: { [$0.host, $0.workspace ?? ""] })
        XCTAssertEqual(byWorkspace.map(\.host), ["api.example.com"])
    }
}
