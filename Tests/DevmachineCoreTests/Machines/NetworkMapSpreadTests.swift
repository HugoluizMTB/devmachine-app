import XCTest
@testable import DevmachineCore

final class NetworkMapSpreadTests: XCTestCase {
    private func machine(
        _ name: String, location: String, isSelf: Bool = false, hasCaddy: Bool = false, workspaces: [String] = []
    ) -> NetworkMapInput.Machine {
        .init(name: name, location: location, hosts: isSelf ? [] : ["100.64.0.10"], isSelf: isSelf,
              isLocalVM: false, hasCaddy: hasCaddy, workspaces: workspaces)
    }

    /// This Mac, one server with Caddy in the middle and one more: the
    /// owner's shape, where the server's tile used to sit behind the digits.
    private var three: NetworkMap {
        NetworkMap.build(NetworkMapInput(machines: [
            machine("laptop", location: "local", isSelf: true),
            machine("main", location: "hostinger", hasCaddy: true, workspaces: ["acme"]),
            machine("homebox", location: "office"),
        ], sites: [.init(host: "app.example.com", servingMachine: "main", workspace: "acme")]))
    }

    private var fleet: NetworkMap {
        NetworkMap.build(NetworkMapInput(machines: [
            machine("laptop", location: "local", isSelf: true),
            machine("lab", location: "local"),
            machine("main", location: "hostinger", hasCaddy: true, workspaces: ["acme", "globex"]),
            machine("staging", location: "hostinger", hasCaddy: true, workspaces: ["beta"]),
            machine("homebox", location: "home", workspaces: ["umbrella"]),
        ], sites: [
            .init(host: "app.example.com", servingMachine: "main", workspace: "acme"),
            .init(host: "beta.example.com", servingMachine: "staging", workspace: "beta"),
            .init(host: "media.example.com", servingMachine: "main", workspace: "umbrella"),
        ]))
    }

    private var lonely: NetworkMap {
        NetworkMap.build(NetworkMapInput(machines: [machine("main", location: "hostinger", hasCaddy: true)], sites: []))
    }

    /// Areas the large wallpaper gets (70% of Home), with the clock's band in them.
    private let cases: [(size: CGSize, clear: CGRect)] = [
        (CGSize(width: 728, height: 640), CGRect(x: 214, y: 230, width: 300, height: 170)),
        (CGSize(width: 1040, height: 900), CGRect(x: 310, y: 300, width: 420, height: 230)),
        (CGSize(width: 1210, height: 900), CGRect(x: 395, y: 300, width: 420, height: 230)),
        (CGSize(width: 1400, height: 940), CGRect(x: 490, y: 320, width: 420, height: 230)),
    ]

    private func spread(_ map: NetworkMap, _ size: CGSize, _ clear: CGRect) throws -> NetworkMapGeometry {
        try XCTUnwrap(NetworkMapGeometry.spread(
            map: map, size: size, keepClear: clear, maximumScale: 4, siteRow: NetworkMapBackdrop.siteRow),
            "\(size)")
    }

    func testNoTileLabelOrZoneSitsInTheClocksBand() throws {
        for (size, clear) in cases {
            for map in [three, fleet, lonely] {
                let geometry = try spread(map, size, clear)
                for node in map.nodes {
                    XCTAssertFalse(geometry.frame(of: node.id).intersects(clear), "\(size) \(node.id)")
                }
                for zone in map.zones {
                    XCTAssertFalse(geometry.frame(ofZone: zone).intersects(clear), "\(size) zone \(zone.name)")
                }
            }
        }
    }

    private func segments(_ geometry: NetworkMapGeometry, _ map: NetworkMap) -> [(CGPoint, CGPoint)] {
        map.links.flatMap { link in
            let points = geometry.route(of: link)
            return Array(zip(points, points.dropFirst()))
        }
    }

    private func crosses(_ segment: (CGPoint, CGPoint), _ clear: CGRect) -> Bool {
        let (a, b) = segment
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            .insetBy(dx: -0.5, dy: -0.5).intersects(clear)
    }

    func testNoLineRunsThroughTheClocksBandWhenThereIsRoomToGoAround() throws {
        for (size, clear) in cases {
            for map in [three, fleet, lonely] where !(map == fleet && size.width < 800) {
                let geometry = try spread(map, size, clear)
                for segment in segments(geometry, map) {
                    XCTAssertFalse(crosses(segment, clear), "\(size) \(segment)")
                }
            }
        }
    }

    func testWhereCrossingCannotBeAvoidedOnlyThinVerticalsCrossTheBand() throws {
        let (size, clear) = cases[0]
        let geometry = try spread(fleet, size, clear)
        let crossing = segments(geometry, fleet).filter { crosses($0, clear) }
        XCTAssertFalse(crossing.isEmpty, "the small area has no room below the band for five machines' lanes")
        for (a, b) in crossing {
            XCTAssertEqual(a.x, b.x, accuracy: 0.001, "only a line straight up from a tile")
        }
    }

    func testTheInternetIsHighAndTheMachinesLow() throws {
        for (size, clear) in cases {
            let geometry = try spread(three, size, clear)
            XCTAssertLessThan(geometry.frame(of: NetworkMap.internetID).maxY, clear.minY)
            for node in three.machineNodes {
                XCTAssertGreaterThan(geometry.frame(of: node.id).minY, clear.maxY, "\(size) \(node.id)")
            }
            XCTAssertLessThanOrEqual(geometry.height, size.height + 0.5)
        }
    }

    func testTheMachinesSpreadToTheSides() throws {
        for (size, clear) in cases {
            let geometry = try spread(fleet, size, clear)
            let xs = fleet.machineNodes.map { geometry.center(of: $0.id).x }
            XCTAssertLessThanOrEqual(xs.min() ?? 0, size.width * 0.2, "\(size)")
            XCTAssertGreaterThanOrEqual(xs.max() ?? 0, size.width * 0.8, "\(size)")
            let ordinary = NetworkMapGeometry(map: fleet, width: size.width, maximumScale: geometry.scale)
            let ordinaryXs = fleet.machineNodes.map { ordinary.center(of: $0.id).x }
            XCTAssertGreaterThan(
                (xs.max() ?? 0) - (xs.min() ?? 0), (ordinaryXs.max() ?? 0) - (ordinaryXs.min() ?? 0),
                "a wider pitch than the page's map")
        }
    }

    func testWithRoomOnBothSidesNoMachineStandsUnderTheBand() throws {
        for (size, clear) in cases.dropFirst() {
            for map in [three, fleet] {
                let geometry = try spread(map, size, clear)
                for node in map.machineNodes {
                    let x = geometry.center(of: node.id).x
                    XCTAssertFalse(x > clear.minX && x < clear.maxX, "\(size) \(node.id) at \(x)")
                }
            }
        }
    }

    func testEveryTileStaysInsideTheArea() throws {
        for (size, clear) in cases {
            for map in [three, fleet, lonely] {
                let geometry = try spread(map, size, clear)
                let area = CGRect(origin: .zero, size: size).insetBy(dx: -0.5, dy: -0.5)
                for node in map.nodes {
                    XCTAssertTrue(area.contains(geometry.frame(of: node.id)), "\(size) \(node.id)")
                }
            }
        }
    }

    func testTheSameInputsGiveTheSameLayout() throws {
        let (size, clear) = cases[2]
        let first = try spread(fleet, size, clear), second = try spread(fleet, size, clear)
        for node in fleet.nodes {
            XCTAssertEqual(first.center(of: node.id), second.center(of: node.id))
        }
    }

    func testNoRoomAroundTheBandMeansNoSpread() {
        let size = CGSize(width: 1040, height: 400)
        XCTAssertNil(NetworkMapGeometry.spread(
            map: three, size: size, keepClear: CGRect(x: 310, y: 40, width: 420, height: 320), maximumScale: 4,
            siteRow: NetworkMapBackdrop.siteRow))
    }

    func testThePagesMapIsLaidOutAsBefore() {
        let geometry = NetworkMapGeometry(map: fleet, width: 900)
        let step = NetworkMapGeometry.pitch * IsoCamera.cosine * 2 * geometry.scale
        let main = fleet.node("main")!, laptop = fleet.node("laptop")!
        XCTAssertEqual(
            geometry.center(of: "main").x - geometry.center(of: "laptop").x, (main.column - laptop.column) * step,
            accuracy: 1e-9)
    }
}

final class NetworkMapLargeSpreadBackdropTests: XCTestCase {
    private var three: NetworkMap {
        NetworkMap.build(NetworkMapInput(machines: [
            .init(name: "laptop", location: "local", hosts: [], isSelf: true, isLocalVM: false, hasCaddy: false,
                  workspaces: []),
            .init(name: "main", location: "hostinger", hosts: ["100.64.0.10"], isSelf: false, isLocalVM: false,
                  hasCaddy: true, workspaces: ["acme"]),
            .init(name: "homebox", location: "home", hosts: ["100.64.0.11"], isSelf: false, isLocalVM: false,
                  hasCaddy: false, workspaces: []),
        ], sites: []))
    }

    func testTheLargeBackdropSpreadsAroundTheClockInHomesCoordinates() {
        let home = CGSize(width: 1488, height: 1000)
        let area = HomeMapArea.large(size: home, padding: 24, gap: 24, pillMinY: home.height - 60)
        let clock = CGRect(x: 534, y: 380, width: 420, height: 230)
        let backdrop = NetworkMapBackdrop(map: three, size: home, area: area, fit: .large, keepClear: clock)
        XCTAssertTrue(backdrop.isSpread)
        XCTAssertEqual(backdrop.zoom, 1)
        for node in three.nodes {
            let frame = backdrop.geometry.frame(of: node.id).offsetBy(dx: backdrop.origin.x, dy: backdrop.origin.y)
            XCTAssertFalse(frame.intersects(clock), node.id)
            XCTAssertTrue(area.insetBy(dx: -0.5, dy: -0.5).contains(frame), node.id)
        }
        XCTAssertTrue(backdrop.showsMap)
    }

    func testWithoutRoomTheLargeBackdropFallsBackToTheCentredMap() {
        let home = CGSize(width: 1488, height: 500)
        let area = HomeMapArea.large(size: home, padding: 24, gap: 24, pillMinY: home.height - 60)
        let clock = CGRect(x: 534, y: 60, width: 420, height: 380)
        let backdrop = NetworkMapBackdrop(map: three, size: home, area: area, fit: .large, keepClear: clock)
        XCTAssertFalse(backdrop.isSpread)
        XCTAssertEqual(backdrop.mapFrame.midX, area.midX, accuracy: 1)
    }
}

final class HomeMapAreaCentringTests: XCTestCase {
    func testTheAreaShrinksSymmetricallyAroundTheClock() {
        let free = CGRect(x: 468, y: 484, width: 548, height: 192)
        XCTAssertEqual(HomeMapArea.centred(free, onX: 640), CGRect(x: 468, y: 484, width: 344, height: 192))
        XCTAssertEqual(HomeMapArea.centred(free, onX: 900), CGRect(x: 784, y: 484, width: 232, height: 192))
        XCTAssertEqual(HomeMapArea.centred(free, onX: free.midX), free)
    }

    func testAClockOutsideTheAreaGivesNoCentredArea() {
        let free = CGRect(x: 468, y: 484, width: 548, height: 192)
        XCTAssertNil(HomeMapArea.centred(free, onX: 400))
        XCTAssertNil(HomeMapArea.centred(free, onX: 1100))
    }

    private var three: NetworkMap {
        NetworkMap.build(NetworkMapInput(machines: [
            .init(name: "laptop", location: "local", hosts: [], isSelf: true, isLocalVM: false, hasCaddy: false,
                  workspaces: []),
            .init(name: "main", location: "hostinger", hosts: ["100.64.0.10"], isSelf: false, isLocalVM: false,
                  hasCaddy: true, workspaces: ["acme"]),
            .init(name: "homebox", location: "home", hosts: ["100.64.0.11"], isSelf: false, isLocalVM: false,
                  hasCaddy: false, workspaces: []),
        ], sites: []))
    }

    func testTheCompactMapCentresOnTheClockAndStaysClearOfTheCards() {
        let home = CGSize(width: 1280, height: 800)
        let free = CGRect(x: 360, y: 560, width: 896, height: 160)
        let backdrop = NetworkMapBackdrop.compact(
            map: three, size: home, area: free, centreX: 640, minimumMargin: 16)
        XCTAssertEqual(backdrop.mapFrame.midX, 640, accuracy: 1)
        XCTAssertGreaterThanOrEqual(backdrop.mapFrame.minX, free.minX)
    }

    func testTooLittleRoomAroundTheClockFallsBackToTheFreeColumnsCentre() {
        let home = CGSize(width: 1280, height: 800)
        let free = CGRect(x: 360, y: 560, width: 896, height: 160)
        let backdrop = NetworkMapBackdrop.compact(
            map: three, size: home, area: free, centreX: 380, minimumMargin: 16)
        XCTAssertEqual(backdrop.mapFrame.midX, free.midX, accuracy: 1)
    }

    func testWithoutAClockXTheMapCentresInTheFreeColumn() {
        let home = CGSize(width: 1280, height: 800)
        let free = CGRect(x: 360, y: 560, width: 896, height: 160)
        let backdrop = NetworkMapBackdrop.compact(map: three, size: home, area: free, centreX: nil, minimumMargin: 16)
        XCTAssertEqual(backdrop.mapFrame.midX, free.midX, accuracy: 1)
    }
}
