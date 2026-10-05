import XCTest
@testable import DevmachineCore

final class NetworkMapTests: XCTestCase {
    private typealias M = NetworkMapInput.Machine

    private func machine(
        _ name: String, location: String, hosts: [String] = ["203.0.113.10"], isSelf: Bool = false,
        isLocalVM: Bool = false, hasCaddy: Bool = false, workspaces: [String] = []
    ) -> M {
        M(name: name, location: location, hosts: hosts, isSelf: isSelf, isLocalVM: isLocalVM, hasCaddy: hasCaddy,
          workspaces: workspaces)
    }

    private var fleet: [M] {
        [
            machine("main", location: "hostinger", hosts: ["100.64.0.10", "203.0.113.10"], hasCaddy: true,
                    workspaces: ["acme", "globex"]),
            machine("homebox", location: "home", hosts: ["tailscale:homebox"], workspaces: ["umbrella"]),
            machine("lab", location: "local", hosts: ["127.0.0.1"], isLocalVM: true, workspaces: ["acme-lab"]),
            machine("laptop", location: "local", hosts: [], isSelf: true),
            machine("staging", location: "hostinger", hosts: ["203.0.113.12"]),
        ]
    }

    func testMachinesAreGroupedByLocationThisMacFirstThenTheInternetsDoors() {
        let map = NetworkMap.build(NetworkMapInput(machines: fleet, sites: []))
        XCTAssertEqual(map.zones.map(\.name), ["local", "hostinger", "home"])
        XCTAssertEqual(map.zones.map(\.machines), [["laptop", "lab"], ["main", "staging"], ["homebox"]])
    }

    func testColumnsRunLeftToRightWithAGapBetweenZones() {
        let map = NetworkMap.build(NetworkMapInput(machines: fleet, sites: []))
        let columns = map.machineNodes.map(\.column)
        XCTAssertEqual(map.machineNodes.map(\.id), ["laptop", "lab", "main", "staging", "homebox"])
        XCTAssertEqual(columns, columns.sorted())
        XCTAssertEqual(columns[1] - columns[0], 1)
        XCTAssertGreaterThan(columns[2] - columns[1], 1)
    }

    func testTheLayoutIsTheSameWhateverOrderTheCLIListsMachinesIn() {
        let one = NetworkMap.build(NetworkMapInput(machines: fleet, sites: []))
        let two = NetworkMap.build(NetworkMapInput(machines: fleet.reversed(), sites: []))
        XCTAssertEqual(one, two)
    }

    func testThisMacReachesEveryOtherMachineOverSSH() {
        let map = NetworkMap.build(NetworkMapInput(machines: fleet, sites: []))
        let ssh = map.links.filter { $0.kind == .ssh }
        XCTAssertEqual(ssh.map(\.from), Array(repeating: "laptop", count: 4))
        XCTAssertEqual(ssh.map(\.to), ["lab", "main", "staging", "homebox"])
    }

    func testWithoutASelfMachineThisMacIsStillDrawnButNotSelectable() {
        let machines = fleet.filter { !$0.isSelf }
        let map = NetworkMap.build(NetworkMapInput(machines: machines, sites: []))
        let mac = map.nodes.first { $0.kind == .thisMac }
        XCTAssertEqual(mac?.id, NetworkMap.thisMacID)
        XCTAssertEqual(mac?.zone, "local")
        XCTAssertFalse(mac?.selectable ?? true)
    }

    func testTheInternetComesInOnlyThroughAMachineWithCaddy() {
        let map = NetworkMap.build(NetworkMapInput(machines: fleet, sites: []))
        XCTAssertEqual(map.links.filter { $0.kind == .https }.map(\.to), ["main"])
        XCTAssertEqual(map.nodes.first { $0.id == "main" }?.isDoor, true)
        XCTAssertNotNil(map.nodes.first { $0.kind == .internet })
    }

    func testALimaMachineWithCaddyIsNoDoorTheInternetCannotReachIt() {
        let machines = [
            machine("lab", location: "local", hosts: ["127.0.0.1"], isLocalVM: true, hasCaddy: true),
            machine("laptop", location: "local", hosts: [], isSelf: true),
        ]
        let map = NetworkMap.build(NetworkMapInput(machines: machines, sites: []))
        XCTAssertEqual(map.node("lab")?.isDoor, false)
        XCTAssertNil(map.node(NetworkMap.internetID))
    }

    func testNoDoorMeansNoInternetNode() {
        let machines = fleet.map {
            machine($0.name, location: $0.location, hosts: $0.hosts, isSelf: $0.isSelf, isLocalVM: $0.isLocalVM)
        }
        let map = NetworkMap.build(NetworkMapInput(machines: machines, sites: []))
        XCTAssertNil(map.nodes.first { $0.kind == .internet })
        XCTAssertTrue(map.links.filter { $0.kind == .https }.isEmpty)
    }

    func testASiteEndsAtTheMachineThatRunsItsWorkspaceEvenThroughAnother() {
        let sites = [
            NetworkMapInput.Site(host: "app.example.com", servingMachine: "main", workspace: "acme"),
            NetworkMapInput.Site(host: "media.example.com", servingMachine: "main", workspace: "umbrella"),
            NetworkMapInput.Site(host: "old.example.com", servingMachine: "main", workspace: nil),
        ]
        let map = NetworkMap.build(NetworkMapInput(machines: fleet, sites: sites))
        XCTAssertEqual(map.sites.map(\.host), ["app.example.com", "media.example.com", "old.example.com"])
        XCTAssertEqual(map.sites.map(\.target), ["main", "homebox", "main"])
        XCTAssertEqual(map.sites.map(\.door), ["main", "main", "main"])
        XCTAssertEqual(map.sites.map(\.row), [0, 1, 2])
    }

    func testASiteFromAMachineWithoutCaddyIsLeftOut() {
        let sites = [NetworkMapInput.Site(host: "x.example.com", servingMachine: "staging", workspace: "acme")]
        XCTAssertTrue(NetworkMap.build(NetworkMapInput(machines: fleet, sites: sites)).sites.isEmpty)
    }

    func testOnlySomeSitesAreDrawnAndTheRestAreCounted() {
        let sites = (0..<12).map {
            NetworkMapInput.Site(host: "s\($0).example.com", servingMachine: "main", workspace: "acme")
        }
        let map = NetworkMap.build(NetworkMapInput(machines: fleet, sites: sites))
        XCTAssertEqual(map.sites.count, NetworkMap.maximumSites)
        XCTAssertEqual(map.hiddenSites, 12 - NetworkMap.maximumSites)
    }

    func testMachinesOnATailnetShareADashedPrivateLink() {
        let map = NetworkMap.build(NetworkMapInput(machines: fleet, sites: []))
        let tailnet = map.links.filter { $0.kind == .tailnet }
        XCTAssertEqual(tailnet.map { [$0.from, $0.to] }, [["main", "homebox"]])
    }

    func testOneTailnetMachineAloneHasNoPrivateLink() {
        let machines = fleet.filter { $0.name != "homebox" }
        let map = NetworkMap.build(NetworkMapInput(machines: machines, sites: []))
        XCTAssertTrue(map.links.filter { $0.kind == .tailnet }.isEmpty)
    }

    func testWorkspacesRideOnTheirMachine() {
        let map = NetworkMap.build(NetworkMapInput(machines: fleet, sites: []))
        XCTAssertEqual(map.nodes.first { $0.id == "main" }?.workspaces, ["acme", "globex"])
        XCTAssertEqual(map.nodes.first { $0.id == "lab" }?.kind, .localVM)
    }

    func testNoMachineMeansAnEmptyMap() {
        XCTAssertTrue(NetworkMap.build(NetworkMapInput(machines: [], sites: [])).nodes.isEmpty)
    }
}

final class NetworkMapGeometryTests: XCTestCase {
    private var map: NetworkMap {
        NetworkMap.build(NetworkMapInput(machines: [
            .init(name: "main", location: "hostinger", hosts: ["100.64.0.10"], isSelf: false, isLocalVM: false,
                  hasCaddy: true, workspaces: ["acme"]),
            .init(name: "homebox", location: "home", hosts: ["100.64.0.11"], isSelf: false, isLocalVM: false,
                  hasCaddy: false, workspaces: ["umbrella"]),
        ], sites: [.init(host: "app.example.com", servingMachine: "main", workspace: "umbrella")]))
    }

    func testTheScaleFitsTheWidthWithinItsLimits() {
        let wide = NetworkMapGeometry(map: map, width: 4000)
        XCTAssertEqual(wide.scale, NetworkMapGeometry.maximumScale)
        let narrow = NetworkMapGeometry(map: map, width: 10)
        XCTAssertEqual(narrow.scale, NetworkMapGeometry.minimumScale)
        let fitted = NetworkMapGeometry(map: map, width: 500)
        XCTAssertEqual(fitted.contentWidth, 500, accuracy: 0.5)
        XCTAssertGreaterThan(fitted.height, 0)
    }

    func testEveryNodeIsInsideTheMap() {
        let geometry = NetworkMapGeometry(map: map, width: 700)
        for node in map.nodes {
            let frame = geometry.frame(of: node.id)
            XCTAssertGreaterThanOrEqual(frame.minX, -0.5, node.id)
            XCTAssertLessThanOrEqual(frame.maxX, 700.5, node.id)
            XCTAssertGreaterThanOrEqual(frame.minY, -0.5, node.id)
            XCTAssertLessThanOrEqual(frame.maxY, geometry.height + 0.5, node.id)
        }
    }

    func testAClickOnATileFindsItsMachineAndTheInternetIsNotOne() {
        let geometry = NetworkMapGeometry(map: map, width: 700)
        let main = geometry.frame(of: "main")
        XCTAssertEqual(geometry.machine(at: CGPoint(x: main.midX, y: main.midY)), "main")
        let internet = geometry.frame(of: NetworkMap.internetID)
        XCTAssertNil(geometry.machine(at: CGPoint(x: internet.midX, y: internet.midY)))
        XCTAssertNil(geometry.machine(at: CGPoint(x: -50, y: -50)))
    }

    func testLinksRiseStraightToTheirLaneAndRunAlongIt() {
        let geometry = NetworkMapGeometry(map: map, width: 700)
        for link in map.links {
            let points = geometry.route(of: link)
            XCTAssertGreaterThanOrEqual(points.count, 2)
            for (a, b) in zip(points, points.dropFirst()) {
                let flat = abs(b.y - a.y) < 0.01
                let upright = abs(b.x - a.x) < 0.01
                XCTAssertTrue(flat || upright, "\(link.kind) \(a) → \(b)")
            }
        }
    }

    func testTheProjectionIsTheTwoToOneIsometricView() {
        let camera = IsoCamera(scale: 2, originX: 100, originY: 50)
        let x = camera.project(1, 0, 0)
        let y = camera.project(0, 1, 0)
        let z = camera.project(0, 0, 1)
        XCTAssertEqual(x.x - 100, 2 * 0.7071, accuracy: 0.001)
        XCTAssertEqual(x.y - 50, 2 * 0.7071 * 0.5, accuracy: 0.001)
        XCTAssertEqual(y.x - 100, -2 * 0.7071, accuracy: 0.001)
        XCTAssertEqual(z.y - 50, -2 * 0.866, accuracy: 0.001)
        XCTAssertEqual(z.x, 100, accuracy: 0.001)
    }

    func testARoundedFootprintRingAndItsHullStayClosed() {
        let ring = IsoShapes.roundedRect(x0: -10, y0: -10, x1: 10, y1: 10, radius: 4, steps: 4)
        XCTAssertEqual(ring.count, 20)
        let hull = IsoShapes.hull(ring.map { CGPoint(x: $0.u, y: $0.v) })
        XCTAssertGreaterThanOrEqual(hull.count, 8)
        XCTAssertTrue(hull.allSatisfy { abs($0.x) <= 10.001 && abs($0.y) <= 10.001 })
    }
}
