import XCTest
@testable import DevmachineCore

final class EntryOverrideTests: XCTestCase {
    private let machines = CatalogWidget(
        name: "devmachine-app/machines", fits: ["canvas", "stack"],
        inputs: ["machines": CatalogInput(type: "choice", defaultValue: nil, summary: "Machines to show.", from: "machines", many: true)],
        source: CatalogSource(name: "app/machines", with: ["machines": "{{inputs.machines}}"], every: "90s"),
        viewKind: "app.machines", sizes: ["medium", "large"], defaultSize: "large")
    private let usage = CatalogWidget(
        name: "devmachine-app/usage", fits: ["canvas", "stack"],
        inputs: ["harness": CatalogInput(type: "choice", defaultValue: nil, summary: "Harness.", from: "harnesses")],
        source: CatalogSource(name: "app/harness-usage", with: ["harness": "{{inputs.harness}}"], every: "60s"),
        viewKind: "app.harness-usage", sizes: ["medium", "large"], defaultSize: "large")
    private let disk = CatalogWidget(
        name: "acme/disk", fits: ["canvas", "stack", "slot"],
        source: CatalogSource(raw: .object(["kind": .string("command"), "run": .string("df"), "every": .string("60s")])),
        viewKind: "text", sizes: ["medium"], defaultSize: "medium", origin: "local")
    private let tail = CatalogWidget(
        name: "acme/tail", fits: ["canvas", "stack"],
        source: CatalogSource(raw: .object([
            "kind": .string("command"), "run": .string("tail"), "args": .list([.string("-f"), .string("/var/log/x")]),
            "mode": .string("stream"),
        ])),
        viewKind: "text", sizes: ["medium"], defaultSize: "medium", origin: "local")

    private var catalog: WidgetCatalog {
        WidgetCatalog(engine: "1.5", packagesRelease: "2026.10.07", widgets: [machines, usage, disk, tail])
    }

    private func entry(
        _ type: String, with: [String: BoardScalar] = [:], title: String? = nil, every: String? = nil
    ) -> BoardWidget {
        BoardWidget(
            id: "w", type: type, with: with, frame: BoardFrame(x: 0, y: 0, w: 320, h: 160), size: "medium", z: 1,
            titleOverride: title, everyOverride: every)
    }

    private func ready(_ widget: BoardWidget) throws -> ResolvedWidget {
        let resolution = WidgetResolution.resolve(widget, in: catalog)
        guard case let .ready(resolved) = resolution else {
            XCTFail("not ready: \(resolution)")
            throw CancellationError()
        }
        return resolved
    }

    func testAManyInputReachesTheProviderAsAList() throws {
        let resolved = try ready(entry("devmachine-app/machines", with: ["machines": .list(["main", "here"])]))
        XCTAssertEqual(resolved.listArguments["machines"], ["main", "here"])
        XCTAssertEqual(resolved.arguments["machines"], "main,here")
        XCTAssertEqual(try ready(entry("devmachine-app/machines")).listArguments["machines"], [])
    }

    func testAScalarForAManyInputIsRefused() {
        XCTAssertEqual(
            WidgetResolution.resolve(entry("devmachine-app/machines", with: ["machines": .string("main")]), in: catalog),
            .refused(
                type: "devmachine-app/machines",
                reason: "w: input \"machines\" takes a list of names, written [a, b], and main is not one"))
    }

    func testAListForASingleInputIsRefused() {
        XCTAssertEqual(
            WidgetResolution.resolve(entry("devmachine-app/usage", with: ["harness": .list(["claude"])]), in: catalog),
            .refused(type: "devmachine-app/usage", reason: "w: input \"harness\" takes one name, and [claude] is not one"))
    }

    func testATitleOverrideIsTheTitle() throws {
        XCTAssertEqual(try ready(entry("devmachine-app/machines", title: "Servers")).title, "Servers")
        XCTAssertNil(try ready(entry("devmachine-app/machines")).title)
    }

    func testEveryOverridesAProviderAndASourceWidget() throws {
        XCTAssertEqual(try ready(entry("devmachine-app/machines", every: "2m")).every, 120)
        XCTAssertEqual(try ready(entry("acme/disk", every: "10m")).source?.every, .interval(600))
        XCTAssertEqual(try ready(entry("acme/disk", every: "manual")).source?.every, .manual)
    }

    func testManualOnAProviderWidgetIsRefused() {
        XCTAssertEqual(
            WidgetResolution.resolve(entry("devmachine-app/machines", every: "manual"), in: catalog),
            .refused(
                type: "devmachine-app/machines",
                reason: "w: every manual: devmachine-app/machines reads a provider, which runs on a schedule: write a duration like 60s"))
    }

    func testAListForAPlainInputIsRefused() {
        let labelled = CatalogWidget(
            name: "acme/label", fits: ["canvas"], inputs: ["label": CatalogInput(type: "string", defaultValue: nil, summary: "")],
            source: CatalogSource(name: "app/machines", every: "90s"), viewKind: "app.machines", sizes: ["medium"],
            defaultSize: "medium")
        let catalog = WidgetCatalog(engine: "1.5", packagesRelease: "r", widgets: [labelled])
        XCTAssertEqual(
            WidgetResolution.resolve(entry("acme/label", with: ["label": .list(["a", "b"])]), in: catalog),
            .refused(type: "acme/label", reason: "w: input \"label\" is a string, and [a, b] is not"))
    }

    func testANonDurationEveryIsRefusedWithTheWordingOfItsKind() {
        XCTAssertEqual(
            WidgetResolution.resolve(entry("devmachine-app/machines", every: "often"), in: catalog),
            .refused(
                type: "devmachine-app/machines", reason: "w: every \"often\" is not a duration: write it like 60s or 5m"))
        XCTAssertEqual(
            WidgetResolution.resolve(entry("acme/disk", every: "often"), in: catalog),
            .refused(
                type: "acme/disk",
                reason: "w: every \"often\" is neither a duration nor manual: write it like 60s, 5m or manual"))
    }

    func testANumberForAManyInputIsRefused() {
        XCTAssertEqual(
            WidgetResolution.resolve(entry("devmachine-app/machines", with: ["machines": .int(3)]), in: catalog),
            .refused(
                type: "devmachine-app/machines",
                reason: "w: input \"machines\" takes a list of names, written [a, b], and 3 is not one"))
    }

    func testEveryBelowTheFloorIsRefused() {
        XCTAssertEqual(
            WidgetResolution.resolve(entry("acme/disk", every: "2s"), in: catalog),
            .refused(type: "acme/disk", reason: "w: every 2s is below acme/disk's minimum of 5s"))
        XCTAssertEqual(
            WidgetResolution.resolve(entry("devmachine-app/machines", every: "1s"), in: catalog),
            .refused(type: "devmachine-app/machines", reason: "w: every 1s is below devmachine-app/machines's minimum of 5s"))
    }

    func testAStreamTakesNoEvery() {
        XCTAssertEqual(
            WidgetResolution.resolve(entry("acme/tail", every: "60s"), in: catalog),
            .refused(type: "acme/tail", reason: "w: a stream runs while the widget is on screen, so it takes no every"))
    }

    func testEveryDoesNotChangeTheApprovalHash() throws {
        let plain = try XCTUnwrap(try ready(entry("acme/disk")).source)
        let slower = try XCTUnwrap(try ready(entry("acme/disk", every: "10m")).source)
        XCTAssertEqual(try ApprovalSubject.hash(for: plain, context: [:]), try ApprovalSubject.hash(for: slower, context: [:]))
    }

    func testAStackEntryGetsTheSameRules() {
        let board = StackBoard(surface: "sidebar", entries: [
            StackEntry(id: "w", type: "devmachine-app/machines", with: ["machines": .string("main")]),
        ])
        guard case let .refused(_, reason)? = StackResolution.resolve(board.entries[0], on: board, catalog: catalog) else {
            return XCTFail("expected a refusal")
        }
        XCTAssertEqual(reason, "w: input \"machines\" takes a list of names, written [a, b], and main is not one")
    }

    func testTheMenuBarFloorStillWinsOverAShorterEvery() {
        let board = StackBoard(surface: "menubar", entries: [StackEntry(id: "w", type: "acme/disk", everyOverride: "10s")])
        guard case let .ready(resolved)? = StackResolution.resolve(board.entries[0], on: board, catalog: catalog) else {
            return XCTFail("expected ready")
        }
        XCTAssertEqual(resolved.source?.every, .interval(30))
    }
}
