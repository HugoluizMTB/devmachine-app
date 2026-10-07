import XCTest
import DevmachineCore
@testable import DevmachineApp

/// Runs the real CLI named by `DEVMACHINE_WIDGETS_E2E` against an empty temp
/// configuration with a copy of the packages checkout's `devmachine-app`
/// package (`DEVMACHINE_WIDGETS_PACKAGES`). Skipped otherwise.
final class WidgetCatalogLiveTests: XCTestCase {
    func testTheRealCatalogDecodesAndHasTheHomeWidgets() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let binary = environment["DEVMACHINE_WIDGETS_E2E"], !binary.isEmpty else {
            throw XCTSkip("set DEVMACHINE_WIDGETS_E2E to a devmachine binary")
        }
        let config = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetCatalogLiveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: config) }
        let packages = config.appendingPathComponent("packages")
        try FileManager.default.createDirectory(at: packages, withIntermediateDirectories: true)
        if let checkout = environment["DEVMACHINE_WIDGETS_PACKAGES"], !checkout.isEmpty {
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: checkout).appendingPathComponent("devmachine-app"),
                to: packages.appendingPathComponent("devmachine-app"))
        }
        var processEnvironment = environment
        processEnvironment["DEVMACHINE_CONFIG"] = config.path
        let cli = DevmachineCLI(executable: binary, processEnvironment: processEnvironment)
        let catalog = try WidgetCatalog.decode(cli.widgetsList())
        XCTAssertEqual(catalog.engine, WidgetContract.engine10.engine)
        if environment["DEVMACHINE_WIDGETS_PACKAGES"] != nil {
            for name in ["devmachine-app/clock", "devmachine-app/summary", "devmachine-app/machines"] {
                let widget = try XCTUnwrap(catalog.widget(named: name), name)
                XCTAssertTrue(widget.available, name)
                XCTAssertTrue(widget.surfaces.contains("home"), name)
                guard case .ready = WidgetResolution.resolve(
                    BoardWidget(id: "w", type: name, frame: BoardFrame(x: 0, y: 0, w: 320, h: 160), size: "medium", z: 1),
                    in: catalog) else { return XCTFail("\(name) does not resolve in this app") }
            }
        }
    }
}
