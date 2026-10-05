import XCTest
@testable import DevmachineCore

final class NetworkMapPresentationTests: XCTestCase {
    func testTheMachinesPageMapAnswersClicksAndShowsItsSelection() {
        let page = NetworkMapPresentation.interactive
        XCTAssertTrue(page.allowsHitTesting)
        XCTAssertEqual(page.highlighted("main"), "main")
        XCTAssertEqual(page.inkOpacity, 1)
        XCTAssertEqual(page.groundOpacity, 1)
        XCTAssertTrue(page.showsSiteLabels)
        XCTAssertTrue(page.showsHiddenSiteCount)
    }

    func testTheBackgroundMapNeverTakesAClickNorShowsASelection() {
        let background = NetworkMapPresentation.decorative
        XCTAssertFalse(background.allowsHitTesting)
        XCTAssertNil(background.highlighted("main"))
        XCTAssertNil(background.highlighted(nil))
    }

    func testTheBackgroundMapIsToneddownSoHomeStaysReadable() {
        let background = NetworkMapPresentation.decorative
        XCTAssertLessThan(background.inkOpacity, NetworkMapPresentation.interactive.inkOpacity)
        XCTAssertGreaterThan(background.inkOpacity, 0)
        XCTAssertLessThanOrEqual(background.groundOpacity, 1)
        XCTAssertFalse(background.showsSiteLabels, "hosts would run under the clock's digits")
        XCTAssertFalse(background.showsHiddenSiteCount, "a count pointing at another page means nothing behind Home")
    }
}

final class NetworkMapBackdropTests: XCTestCase {
    private func machine(
        _ name: String, location: String, isSelf: Bool = false, hasCaddy: Bool = false, workspaces: [String] = []
    ) -> NetworkMapInput.Machine {
        .init(name: name, location: location, hosts: isSelf ? [] : ["100.64.0.10"], isSelf: isSelf,
              isLocalVM: false, hasCaddy: hasCaddy, workspaces: workspaces)
    }

    private var fleet: NetworkMap {
        NetworkMap.build(NetworkMapInput(machines: [
            machine("laptop", location: "local", isSelf: true),
            machine("main", location: "hostinger", hasCaddy: true, workspaces: ["acme", "globex"]),
            machine("staging", location: "hostinger"),
            machine("homebox", location: "home", workspaces: ["umbrella"]),
        ], sites: [
            .init(host: "app.example.com", servingMachine: "main", workspace: "acme"),
            .init(host: "media.example.com", servingMachine: "main", workspace: "umbrella"),
        ]))
    }

    private var one: NetworkMap {
        NetworkMap.build(NetworkMapInput(machines: [machine("main", location: "hostinger")], sites: []))
    }

    private let windows = [CGSize(width: 1040, height: 760), CGSize(width: 1488, height: 1040),
                           CGSize(width: 700, height: 420), CGSize(width: 2000, height: 1120)]

    func testTheMapFitsInsideTheMarginsAtCommonWindowSizes() {
        for size in windows {
            for map in [fleet, one] {
                let backdrop = NetworkMapBackdrop(map: map, size: size)
                let inner = CGRect(origin: .zero, size: size)
                    .insetBy(dx: backdrop.margins.width - 0.5, dy: backdrop.margins.height - 0.5)
                XCTAssertTrue(inner.contains(backdrop.mapFrame), "\(size): \(backdrop.mapFrame) outside \(inner)")
            }
        }
    }

    func testTheMapIsCentred() {
        for size in windows {
            let frame = NetworkMapBackdrop(map: fleet, size: size).mapFrame
            XCTAssertEqual(frame.midX, size.width / 2, accuracy: 1, "\(size)")
            XCTAssertEqual(frame.midY, size.height / 2, accuracy: 1, "\(size)")
        }
    }

    func testMarginsAreGenerous() {
        let backdrop = NetworkMapBackdrop(map: fleet, size: CGSize(width: 1488, height: 1040))
        XCTAssertGreaterThanOrEqual(backdrop.margins.width, NetworkMapBackdrop.minimumMargin)
        XCTAssertGreaterThanOrEqual(backdrop.margins.height, NetworkMapBackdrop.minimumMargin)
        XCTAssertGreaterThanOrEqual(backdrop.margins.width, 1488 * 0.1)
    }

    func testAThumbnailCanAskForSmallerMargins() {
        let size = CGSize(width: 480, height: 150)
        let thumbnail = NetworkMapBackdrop(map: fleet, size: size, minimumMargin: 12)
        XCTAssertEqual(thumbnail.margins.height, 18, accuracy: 0.01)
        XCTAssertGreaterThan(thumbnail.zoom, NetworkMapBackdrop(map: fleet, size: size).zoom)
    }

    func testOneMachineDoesNotBlowUpToFillABigWindow() {
        let backdrop = NetworkMapBackdrop(map: one, size: CGSize(width: 2000, height: 1120))
        XCTAssertLessThanOrEqual(backdrop.geometry.scale, NetworkMapBackdrop.maximumScale)
        XCTAssertEqual(backdrop.zoom, 1)
    }

    func testAShortWindowShrinksTheWholeMapInsteadOfCuttingIt() {
        let size = CGSize(width: 1400, height: 300)
        let backdrop = NetworkMapBackdrop(map: fleet, size: size)
        XCTAssertLessThan(backdrop.zoom, 1)
        XCTAssertLessThanOrEqual(backdrop.mapFrame.height, size.height - 2 * backdrop.margins.height + 0.5)
    }

    func testTheGroundCoversTheWholeContainerInTheMapsOwnPoints() {
        let size = CGSize(width: 1400, height: 300)
        let backdrop = NetworkMapBackdrop(map: fleet, size: size)
        let ground = backdrop.ground
        XCTAssertEqual(backdrop.origin.x + ground.minX * backdrop.zoom, 0, accuracy: 0.01)
        XCTAssertEqual(backdrop.origin.y + ground.minY * backdrop.zoom, 0, accuracy: 0.01)
        XCTAssertEqual(ground.width * backdrop.zoom, size.width, accuracy: 0.01)
        XCTAssertEqual(ground.height * backdrop.zoom, size.height, accuracy: 0.01)
    }

    func testNoMachineStillGivesAGroundAndNoMap() {
        let empty = NetworkMap.build(NetworkMapInput(machines: [], sites: []))
        let backdrop = NetworkMapBackdrop(map: empty, size: CGSize(width: 1040, height: 760))
        XCTAssertEqual(backdrop.zoom, 1)
        XCTAssertEqual(backdrop.ground.size, CGSize(width: 1040, height: 760))
        XCTAssertTrue(backdrop.map.nodes.isEmpty)
    }

    func testAZeroSizeContainerDoesNotBreakTheLayout() {
        let backdrop = NetworkMapBackdrop(map: fleet, size: .zero)
        XCTAssertTrue(backdrop.zoom.isFinite)
        XCTAssertGreaterThan(backdrop.zoom, 0)
    }
}

final class NetworkMapGeometryScaleLimitTests: XCTestCase {
    func testACallerCanLowerTheLargestScale() {
        let map = NetworkMap.build(NetworkMapInput(machines: [
            .init(name: "main", location: "hostinger", hosts: [], isSelf: false, isLocalVM: false, hasCaddy: false,
                  workspaces: []),
        ], sites: []))
        XCTAssertEqual(NetworkMapGeometry(map: map, width: 4000).scale, NetworkMapGeometry.maximumScale)
        XCTAssertEqual(NetworkMapGeometry(map: map, width: 4000, maximumScale: 1.5).scale, 1.5)
    }
}
