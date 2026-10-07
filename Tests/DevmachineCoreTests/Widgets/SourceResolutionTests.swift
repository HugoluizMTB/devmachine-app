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
        guard case let .command(written) = source.source else { return XCTFail() }
        XCTAssertEqual(written.target, .machine("{{inputs.machine}}"))
        guard case let .command(command) = try source.resolved(context: [:]) else { return XCTFail() }
        XCTAssertEqual(command.target, .machine("sandbox"))
        XCTAssertFalse(source.needsApproval)
        XCTAssertEqual(source.package, "mine")
        XCTAssertEqual(source.packagePath, "/Users/alice/.config/devmachine/packages/mine")
        XCTAssertEqual(source.view.tail, 20)
        XCTAssertEqual(resolved.viewKind, "text")
        XCTAssertEqual(resolved.provider, "")
    }

    func testAnInputDefaultFillsATemplate() throws {
        let resolved = try XCTUnwrap(ready(WidgetResolution.resolve(entry("mine/disk"), in: catalog())))
        guard case let .command(command)? = try resolved.source?.resolved(context: [:]) else { return XCTFail() }
        XCTAssertEqual(command.target, .machine("main"))
        XCTAssertEqual(resolved.source?.inputs, ["machine": "main"])
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
        XCTAssertEqual(
            try ApprovalSubject.hash(for: XCTUnwrap(disk.source), context: [:]),
            try ApprovalSubject.hash(board.widgets[0].inline!.source, values: .none))
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

    private func catalog(with widget: CatalogWidget) -> WidgetCatalog {
        WidgetCatalog(engine: "1.1", packagesRelease: "v40", widgets: [widget])
    }

    private func packageCommand(_ raw: [String: WidgetValue], context: [String: String] = [:]) -> CatalogWidget {
        CatalogWidget(
            name: "mine/probe", requiresEngine: ">= 1.1", context: context,
            inputs: [
                "token": CatalogInput(type: "string", defaultValue: nil, summary: ""),
                "path": CatalogInput(type: "string", defaultValue: .string("/"), summary: ""),
            ],
            source: CatalogSource(raw: .object(raw.merging(["every": .string("60s")]) { given, _ in given })),
            viewKind: "text", sizes: ["medium"], defaultSize: "medium",
            packagePath: "/Users/alice/.config/devmachine/packages/mine")
    }

    func testAValueThatLooksLikeATemplateStaysLiteral() throws {
        let widget = packageCommand([
            "kind": .string("command"), "run": .string("df"),
            "args": .list([.string("{{inputs.path}}"), .string("{{inputs.token}}")]),
        ])
        let entry = entry("mine/probe", with: ["path": .string("{{inputs.token}}"), "token": .string("secret")])
        let source = try XCTUnwrap(ready(WidgetResolution.resolve(entry, in: catalog(with: widget)))?.source)
        XCTAssertEqual(try source.command(context: [:]), .argv(["df", "{{inputs.token}}", "secret"]))
        guard case let .command(shown) = try source.resolved(context: [:]) else { return XCTFail() }
        XCTAssertEqual(shown.args, ["{{inputs.token}}", "secret"])
    }

    func testAContextChangeChangesTheApprovalHash() throws {
        let board = try BoardCodec.decode("""
            format: 1
            surface: context-sidebar
            widgets:
              - id: repo
                title: Repo
                source: {kind: command, run: git, args: [log, "{{context.branch}}"], every: 60s}
                view: {kind: text}
                frame: {x: 24, y: 24, w: 320, h: 160}
            """)
        let source = try XCTUnwrap(ready(WidgetResolution.resolveInline(board.widgets[0]))?.source)
        let main = try ApprovalSubject.hash(for: source, context: ["branch": "main"])
        let other = try ApprovalSubject.hash(for: source, context: ["branch": "other"])
        XCTAssertNotNil(main)
        XCTAssertNotEqual(main, other)
        XCTAssertEqual(try source.command(context: ["branch": "other"]), .argv(["git", "log", "other"]))
    }

    func testUndeclaredInputsAndContextNeverReachTheShell() throws {
        let widget = packageCommand(
            ["kind": .string("command"), "run": .string("echo \"$DM_INPUT_TOKEN\""), "shell": .bool(true)],
            context: ["branch": "string"])
        let entry = entry("mine/probe", with: ["token": .string("t"), "evil": .string("x")])
        let source = try XCTUnwrap(ready(WidgetResolution.resolve(entry, in: catalog(with: widget)))?.source)
        XCTAssertEqual(source.inputs, ["token": "t", "path": "/"])
        guard case let .shell(_, environment) = try source.command(context: ["branch": "main", "secret": "s"]) else {
            return XCTFail()
        }
        XCTAssertEqual(environment, ["DM_INPUT_TOKEN": "t", "DM_INPUT_PATH": "/", "DM_CONTEXT_BRANCH": "main"])
    }

    func testHomeGivesNoContextSoATemplateOfItIsEmptyInTheHashAndTheRun() throws {
        let widget = packageCommand(
            ["kind": .string("command"), "run": .string("git"), "args": .list([.string("{{context.branch}}")])],
            context: ["branch": "string"])
        let source = try XCTUnwrap(ready(WidgetResolution.resolve(entry("mine/probe"), in: catalog(with: widget)))?.source)
        XCTAssertEqual(try source.command(context: [:]), .argv(["git", ""]))
        guard case var .command(expected) = source.source else { return XCTFail() }
        expected.args = [""]
        XCTAssertEqual(try ApprovalSubject.hash(for: source, context: [:]), ApprovalSubject.hash(.command(expected)))
    }

    private func catalog13(replacing old: String = "", with new: String = "") throws -> WidgetCatalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/widgets-list-engine-1.3.json")
        let text = try String(contentsOf: url, encoding: .utf8)
        return try WidgetCatalog.decode(Data((old.isEmpty ? text : text.replacingOccurrences(of: old, with: new)).utf8))
    }

    private func inline(
        _ source: [String: WidgetValue],
        view: [String: WidgetValue] = ["kind": .string("number"), "value": .string("{{json.load}}")]
    ) throws -> BoardWidget {
        let text = """
            format: 1
            surface: home
            widgets:
              - id: load
                title: Load
                source: \(WidgetValue.object(source).canonicalJSON)
                view: \(WidgetValue.object(view).canonicalJSON)
                frame: {x: 0, y: 0, w: 320, h: 160}
            """
        return try XCTUnwrap(BoardCodec.decode(text).widgets.first)
    }

    func testAnOfficialPackageProviderResolvesAsASourceThatNeedsNoApproval() throws {
        let resolved = try XCTUnwrap(ready(WidgetResolution.resolve(entry("devmachine-app/machine-stats"), in: catalog13())))
        let source = try XCTUnwrap(resolved.source)
        guard case let .packageProvider(provider) = source.source else { return XCTFail("\(source.source)") }
        XCTAssertEqual(provider.name, "devmachine-app/stats")
        XCTAssertEqual(provider.returns["cpu"], "number")
        XCTAssertEqual(provider.target, .machine("{{inputs.machine}}"))
        XCTAssertEqual(resolved.provider, "")
        XCTAssertEqual(resolved.viewKind, "gauge")
        XCTAssertFalse(source.needsApproval)
        XCTAssertEqual(source.trust, .official)
        XCTAssertNil(source.packageCommit)
        guard case let .packageProvider(filled) = try source.resolved(context: [:]) else { return XCTFail() }
        XCTAssertEqual(filled.target, .machine("main"))
    }

    func testAThirdPartyCodeWidgetWaitsAndAnOfficialOneDoesNot() throws {
        let catalog = try catalog13()
        for name in ["acme-tools/load", "acme-tools/disk"] {
            let source = try XCTUnwrap(ready(WidgetResolution.resolve(entry(name), in: catalog))?.source, name)
            XCTAssertTrue(source.needsApproval, name)
            XCTAssertEqual(source.trust, .thirdParty, name)
            XCTAssertEqual(source.packageCommit, "1111111111111111111111111111111111111111", name)
            XCTAssertEqual(source.packageSourceURL, "https://example.com/acme/acme-tools.git", name)
        }
        let health = try XCTUnwrap(ready(WidgetResolution.resolve(entry("acme-tools/health"), in: catalog))?.source)
        XCTAssertFalse(health.needsApproval)
        let mine = try XCTUnwrap(ready(WidgetResolution.resolve(entry("mine/uptime"), in: catalog))?.source)
        XCTAssertFalse(mine.needsApproval)
        XCTAssertNil(mine.packageCommit)
    }

    func testATrustThisAppDoesNotKnowWaitsLikeAThirdPartyOne() throws {
        let catalog = try catalog13(
            replacing: "\"origin\": \"local\", \"trust\": \"local\"", with: "\"origin\": \"local\", \"trust\": \"verified\"")
        let mine = try XCTUnwrap(ready(WidgetResolution.resolve(entry("mine/uptime"), in: catalog))?.source)
        XCTAssertEqual(mine.trust, .thirdParty)
        XCTAssertTrue(mine.needsApproval)
        XCTAssertEqual(mine.packageCommit, "")
    }

    func testAThirdPartyWidgetOfAnAppProviderStaysAnAppJob() throws {
        let widget = CatalogWidget(
            name: "acme-tools/clock", requiresEngine: ">= 1.1",
            source: CatalogSource(raw: .object(["kind": .string("provider"), "name": .string("app/clock"), "every": .string("60s")])),
            viewKind: "app.clock", sizes: ["medium"], defaultSize: "medium", trust: .thirdParty)
        let resolved = try XCTUnwrap(ready(WidgetResolution.resolve(entry("acme-tools/clock"), in: catalog(with: widget))))
        XCTAssertEqual(resolved.provider, "app/clock")
        XCTAssertNil(resolved.source)
    }

    func testAnInlinePackageProviderAlwaysWaits() throws {
        let widget = try inline([
            "kind": .string("provider"), "name": .string("devmachine-app/stats"),
            "target": .object(["machine": .string("main")]), "every": .string("60s"),
        ], view: ["kind": .string("gauge"), "value": .string("{{json.cpu}}")])
        for catalog in [nil, try catalog13()] {
            let source = try XCTUnwrap(ready(WidgetResolution.resolveInline(widget, catalog: catalog))?.source)
            XCTAssertTrue(source.needsApproval)
            XCTAssertNil(source.packageCommit)
        }
        let catalog = try catalog13()
        let withCatalog = try XCTUnwrap(ready(WidgetResolution.resolveInline(widget, catalog: catalog))?.source)
        guard case let .packageProvider(provider) = withCatalog.source else { return XCTFail() }
        XCTAssertEqual(provider.returns["disk"], "number")
        XCTAssertEqual(WidgetResolution.resolve(widget, in: catalog), WidgetResolution.resolveInline(widget, catalog: catalog))
    }

    func testAnInlinePackageProviderTheCatalogDoesNotKnowIsRefused() throws {
        let catalog = try catalog13()
        let ghost = try inline(["kind": .string("provider"), "name": .string("ghost/load"),
                                "target": .object(["machine": .string("main")]), "every": .string("60s")])
        XCTAssertEqual(
            WidgetResolution.resolveInline(ghost, catalog: catalog),
            .refused(type: "load", reason: "source.name ghost/load: no package ghost in the release or your own packages"))
        let nope = try inline(["kind": .string("provider"), "name": .string("acme-tools/nope"),
                               "target": .object(["machine": .string("main")]), "every": .string("60s")])
        XCTAssertEqual(
            WidgetResolution.resolveInline(nope, catalog: catalog),
            .refused(type: "load", reason: "source.name acme-tools/nope: acme-tools has no provider nope; its providers: load"))
        let fast = try inline(["kind": .string("provider"), "name": .string("acme-tools/load"),
                               "target": .object(["machine": .string("main")]), "every": .string("5s")])
        XCTAssertEqual(WidgetResolution.resolveInline(fast, catalog: catalog),
                       .refused(type: "load", reason: "source.every 5s is below the acme-tools/load minimum of 10s"))
        guard case .ready = WidgetResolution.resolveInline(ghost) else { return XCTFail("no catalog yet must not refuse") }
    }
}
