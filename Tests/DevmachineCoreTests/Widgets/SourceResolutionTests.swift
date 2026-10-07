import XCTest
@testable import DevmachineCore

final class SourceResolutionTests: XCTestCase {
    private func catalog() throws -> WidgetCatalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/widgets-list-engine-1.1.json")
        return try WidgetCatalog.decode(Data(contentsOf: url))
    }

    private func entry(_ type: String, with: [String: BoardScalar] = [:]) -> BoardWidget {
        BoardWidget(id: "w", type: type, with: with, frame: BoardFrame(x: 0, y: 0, w: 320, h: 160), size: "medium", z: 1)
    }

    private func ready(_ resolution: WidgetResolution) -> ResolvedWidget? {
        guard case let .ready(resolved) = resolution else { return nil }
        return resolved
    }

    func testAPackageCommandFillsItsInputsAndNeedsNoApproval() throws {
        let resolved = try XCTUnwrap(ready(WidgetResolution.resolve(entry("mine/disk", with: ["machine": .string("sandbox")]), in: catalog())))
        let source = try XCTUnwrap(resolved.source)
        guard case let .command(command) = source.source else { return XCTFail() }
        XCTAssertEqual(command.target, .machine("sandbox"))
        XCTAssertFalse(source.needsApproval)
        XCTAssertNil(source.approvalHash)
        XCTAssertEqual(source.package, "mine")
        XCTAssertEqual(source.packagePath, "/Users/alice/.config/devmachine/packages/mine")
        XCTAssertEqual(source.view.tail, 20)
        XCTAssertEqual(resolved.viewKind, "text")
        XCTAssertEqual(resolved.provider, "")
    }

    func testAnInputDefaultFillsATemplate() throws {
        let resolved = try XCTUnwrap(ready(WidgetResolution.resolve(entry("mine/disk"), in: catalog())))
        guard case let .command(command)? = resolved.source?.source else { return XCTFail() }
        XCTAssertEqual(command.target, .machine("main"))
    }

    func testEverySourceKindResolves() throws {
        let catalog = try catalog()
        for name in ["mine/log", "mine/health", "mine/today", "mine/screen"] {
            XCTAssertNotNil(ready(WidgetResolution.resolve(entry(name), in: catalog))?.source, name)
        }
        XCTAssertEqual(ready(WidgetResolution.resolve(entry("mine/log"), in: catalog))?.source?.every, .continuous)
        XCTAssertEqual(ready(WidgetResolution.resolve(entry("mine/today"), in: catalog))?.source?.every, .manual)
    }

    func testACatalogEveryBelowTheMinimumIsRaised() throws {
        var catalog = try catalog()
        var widgets = catalog.widgets
        var raw = widgets[0].source.raw.object ?? [:]
        raw["every"] = .string("1s")
        widgets[0].source = CatalogSource(raw: .object(raw))
        catalog = WidgetCatalog(engine: "1.1", packagesRelease: "v40", widgets: widgets)
        XCTAssertEqual(ready(WidgetResolution.resolve(entry("mine/disk"), in: catalog))?.source?.every, .interval(5))
    }

    func testASourceThisAppCannotReadAsksForANewerApp() throws {
        var catalog = try catalog()
        var widgets = catalog.widgets
        widgets[0].source = CatalogSource(raw: .object(["kind": .string("magic")]))
        catalog = WidgetCatalog(engine: "1.1", packagesRelease: "v40", widgets: widgets)
        guard case let .needsNewerApp(_, reason) = WidgetResolution.resolve(entry("mine/disk"), in: catalog) else {
            return XCTFail()
        }
        XCTAssertTrue(reason.contains("magic"), reason)
    }

    func testAReadyWidgetTakesItsOwnTitleBeforeTheTypeName() throws {
        var resolved = try XCTUnwrap(ready(WidgetResolution.resolve(entry("mine/disk"), in: catalog())))
        XCTAssertEqual(WidgetResolutionCopy.title(.ready(resolved)), "Disk")
        resolved.title = "Root disk"
        XCTAssertEqual(WidgetResolutionCopy.title(.ready(resolved)), "Root disk")
    }

    func testAnInlineCommandWaitsForApprovalAndResolvesWithoutACatalog() throws {
        let board = try BoardCodec.decode("""
            format: 1
            surface: home
            widgets:
              - id: disk
                title: Disk
                source: {kind: command, run: df, every: 60s}
                view: {kind: text}
                sizes: [medium]
                frame: {x: 24, y: 24, w: 320, h: 160}
              - id: site
                title: Site
                source: {kind: url, url: "https://example.com", every: 30s}
                view: {kind: status}
                frame: {x: 24, y: 200, w: 160, h: 160}
            """)
        let disk = try XCTUnwrap(ready(WidgetResolution.resolveInline(board.widgets[0])))
        XCTAssertEqual(disk.source?.needsApproval, true)
        XCTAssertEqual(disk.source?.approvalHash, ApprovalSubject.hash(board.widgets[0].inline!.source))
        XCTAssertNil(disk.source?.package)
        XCTAssertEqual(disk.title, "Disk")
        XCTAssertEqual(disk.widget.sizes, ["medium"])
        let site = try XCTUnwrap(ready(WidgetResolution.resolveInline(board.widgets[1])))
        XCTAssertEqual(site.source?.needsApproval, false)
        XCTAssertEqual(site.widget.sizes, WidgetContract.presetOrder)
    }

    func testAnInlineProviderBecomesAProviderJob() throws {
        let board = try BoardCodec.decode("""
            format: 1
            surface: home
            widgets:
              - id: clock
                title: Clock
                source: {kind: provider, name: app/clock, every: 60s}
                view: {kind: app.clock}
                frame: {x: 24, y: 24, w: 320, h: 160}
            """)
        let clock = try XCTUnwrap(ready(WidgetResolution.resolveInline(board.widgets[0])))
        XCTAssertEqual(clock.provider, "app/clock")
        XCTAssertNil(clock.source)
        XCTAssertEqual(clock.every, 60)
    }

    func testResolvingAgainstACatalogHandsAnInlineEntryToItsOwnSourceAndTitle() throws {
        let board = try BoardCodec.decode("""
            format: 1
            surface: home
            widgets:
              - id: disk
                title: Root disk
                source: {kind: command, run: df, every: 60s}
                view: {kind: text}
                frame: {x: 24, y: 24, w: 320, h: 160}
            """)
        XCTAssertEqual(board.widgets[0].type, "")
        let resolution = WidgetResolution.resolve(board.widgets[0], in: try catalog())
        XCTAssertEqual(resolution, WidgetResolution.resolveInline(board.widgets[0]))
        XCTAssertEqual(WidgetResolutionCopy.title(resolution), "Root disk")
    }

    func testATypedEntryHasNoInlineResolution() {
        XCTAssertEqual(WidgetResolution.resolveInline(entry("mine/disk")), .notFound(type: "mine/disk"))
    }
}
