import XCTest
@testable import DevmachineCore

final class WidgetCatalogTests: XCTestCase {
    private let appendixJSON = #"""
        {
          "engine": "1.0",
          "packages_release": "v40",
          "widgets": [
            {
              "name": "claude-code/usage",
              "package": "claude-code",
              "widget": "usage",
              "origin": "release",
              "version": "v40",
              "path": "/Users/alice/.config/devmachine/cache/packages/v40/packages/claude-code/widgets/usage",
              "summary": "Coding-harness usage windows.",
              "requires_engine": ">= 1.0",
              "fits": ["canvas", "stack", "slot"],
              "context": {},
              "inputs": {"harness": {"type": "string", "default": "claude", "summary": "Which harness."}},
              "source": {"kind": "provider", "name": "app/harness-usage", "with": {"harness": "{{inputs.harness}}"}, "every": "60s"},
              "view": {"kind": "app.harness-usage"},
              "sizes": ["small", "medium", "wide"],
              "default_size": "medium",
              "places": ["home"],
              "surfaces": ["home"],
              "available": true,
              "unavailable_reason": ""
            }
          ],
          "problems": [
            {"path": "/Users/alice/.config/devmachine/packages/mine/widgets/bad/widget.yml", "message": "view.kind \"gauge\" needs engine 1.1"}
          ]
        }
        """#

    private func entry(_ type: String, with: [String: BoardScalar] = [:]) -> BoardWidget {
        BoardWidget(id: "w", type: type, with: with, frame: BoardFrame(x: 0, y: 0, w: 320, h: 160), size: "medium", z: 1)
    }

    func testDecodesTheSpecAppendix() throws {
        let catalog = try WidgetCatalog.decode(Data(appendixJSON.utf8))
        XCTAssertEqual(catalog.engine, "1.0")
        XCTAssertEqual(catalog.packagesRelease, "v40")
        XCTAssertEqual(catalog.problems.first?.message, "view.kind \"gauge\" needs engine 1.1")
        let usage = try XCTUnwrap(catalog.widget(named: "claude-code/usage"))
        XCTAssertEqual(usage.package, "claude-code")
        XCTAssertEqual(usage.widget, "usage")
        XCTAssertEqual(usage.origin, "release")
        XCTAssertEqual(usage.requiresEngine, ">= 1.0")
        XCTAssertEqual(usage.inputs["harness"]?.defaultValue, .string("claude"))
        XCTAssertEqual(usage.source.with, ["harness": "{{inputs.harness}}"])
        XCTAssertEqual(usage.viewKind, "app.harness-usage")
        XCTAssertEqual(usage.defaultSize, "medium")
        XCTAssertEqual(usage.surfaces, ["home"])
        XCTAssertTrue(usage.available)
    }

    func testDecodesTheRealCLIOutputAndEveryWidgetResolves() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/widgets-list-cli-0.9.0.json")
        let catalog = try WidgetCatalog.decode(Data(contentsOf: url))
        XCTAssertEqual(catalog.engine, WidgetContract.engine10.engine)
        XCTAssertEqual(catalog.problems, [])
        XCTAssertEqual(
            catalog.widgets.map(\.name),
            ["claude-code/usage", "codex/usage", "devmachine-app/clock", "devmachine-app/machines", "devmachine-app/summary"])
        let codex = try XCTUnwrap(catalog.widget(named: "codex/usage"))
        XCTAssertEqual(codex.origin, "local")
        XCTAssertEqual(codex.source.with, ["harness": "codex"])
        XCTAssertEqual(codex.surfaces, ["context-sidebar", "home", "sidebar"])
        for widget in catalog.widgets {
            XCTAssertTrue(widget.available, widget.name)
            guard case .ready = WidgetResolution.resolve(entry(widget.name), in: catalog) else {
                return XCTFail("\(widget.name) does not resolve in this app")
            }
        }
    }

    func testMissingOptionalListsReadAsEmpty() throws {
        let catalog = try WidgetCatalog.decode(Data(#"{"engine":"1.0","packages_release":"v40","widgets":[]}"#.utf8))
        XCTAssertEqual(catalog.problems, [])
    }

    func testGoNullsReadAsEmpty() throws {
        let json = #"""
            {"engine":"1.0","packages_release":"v40","problems":[],"widgets":[{
              "name":"acme/status","package":"acme","widget":"status","fits":null,"sizes":null,
              "inputs":{"repo":{"type":"string","default":null,"summary":""}},
              "source":{"kind":"provider","name":"app/clock","with":{},"every":"60s"},"view":{"kind":"app.clock"}}]}
            """#
        let status = try XCTUnwrap(WidgetCatalog.decode(Data(json.utf8)).widget(named: "acme/status"))
        XCTAssertEqual(status.fits, [])
        XCTAssertEqual(status.sizes, [])
        XCTAssertNil(status.inputs["repo"]?.defaultValue)
    }

    func testEngineConstraints() throws {
        let one = try XCTUnwrap(EngineVersion("1.0"))
        let eleven = try XCTUnwrap(EngineVersion("1.1"))
        XCTAssertTrue(try XCTUnwrap(EngineConstraint.parse(">= 1.0")).allows(one))
        XCTAssertFalse(try XCTUnwrap(EngineConstraint.parse(">= 1.1")).allows(one))
        XCTAssertTrue(try XCTUnwrap(EngineConstraint.parse(">=1.0, <2.0")).allows(eleven))
        XCTAssertTrue(try XCTUnwrap(EngineConstraint.parse("1.0")).allows(one))
        XCTAssertFalse(try XCTUnwrap(EngineConstraint.parse("1.0")).allows(eleven))
        XCTAssertNil(EngineConstraint.parse(">= one"))
        XCTAssertNil(EngineConstraint.parse(""))
    }

    func testTemplatesTakeTheBoardValueThenTheDefault() {
        let inputs = ["harness": CatalogInput(type: "string", defaultValue: .string("claude"), summary: "")]
        XCTAssertEqual(WidgetTemplate.resolve("{{inputs.harness}}", inputs: inputs, values: [:]), "claude")
        XCTAssertEqual(
            WidgetTemplate.resolve("{{ inputs.harness }}", inputs: inputs, values: ["harness": .string("codex")]), "codex")
        XCTAssertEqual(WidgetTemplate.resolve("{{context.repo}}", inputs: inputs, values: [:]), "")
        XCTAssertEqual(WidgetTemplate.resolve("fixed", inputs: inputs, values: [:]), "fixed")
    }

    func testAnAvailableWidgetResolvesWithItsArgumentsAndMinimum() {
        let catalog = CatalogFixtures.catalog([CatalogFixtures.usage(package: "codex", harness: "codex")])
        guard case let .ready(resolved) = WidgetResolution.resolve(entry("codex/usage"), in: catalog) else {
            return XCTFail("not ready")
        }
        XCTAssertEqual(resolved.provider, "app/harness-usage")
        XCTAssertEqual(resolved.viewKind, "app.harness-usage")
        XCTAssertEqual(resolved.arguments, ["harness": "codex"])
        XCTAssertEqual(resolved.every, 60)
        XCTAssertEqual(resolved.minimum, CanvasSize(w: 160, h: 160))
    }

    func testAnIntervalUnderTheProviderMinimumIsRaised() {
        var fast = CatalogFixtures.clock
        fast.source = CatalogSource(name: "app/clock", every: "1s")
        guard case let .ready(resolved) = WidgetResolution.resolve(
            entry("devmachine-app/clock"), in: CatalogFixtures.catalog([fast])) else { return XCTFail("not ready") }
        XCTAssertEqual(resolved.every, 5)
    }

    func testEveryPlaceholderHasItsReason() {
        var locked = CatalogFixtures.usage(package: "acme", harness: "acme")
        locked.available = false
        locked.unavailableReason = "add the package: devmachine packages add acme --machine <name>"
        var future = CatalogFixtures.clock
        future.requiresEngine = ">= 1.1"
        var gauge = CatalogFixtures.summary
        gauge.viewKind = "gauge"
        let catalog = CatalogFixtures.catalog([locked, future, gauge])

        XCTAssertEqual(
            WidgetResolution.resolve(entry("acme/usage"), in: catalog),
            .needsPackage(package: "acme", reason: "add the package: devmachine packages add acme --machine <name>"))
        XCTAssertEqual(WidgetResolution.resolve(entry("github-prs/open"), in: catalog), .notFound(type: "github-prs/open"))
        XCTAssertEqual(
            WidgetResolution.resolve(entry("devmachine-app/clock"), in: catalog),
            .needsNewerApp(type: "devmachine-app/clock", reason: "it needs engine >= 1.1; this app implements 1.0"))
        XCTAssertEqual(
            WidgetResolution.resolve(entry("devmachine-app/summary"), in: catalog),
            .needsNewerApp(type: "devmachine-app/summary", reason: "this app has no view gauge for app/summary"))
    }

    func testPlaceholderCopy() {
        XCTAssertEqual(WidgetResolutionCopy.title(.needsPackage(package: "acme", reason: "")), "Needs the acme package")
        XCTAssertEqual(
            WidgetResolutionCopy.detail(.needsPackage(package: "acme", reason: ""), release: "v39"),
            "Add the acme package to a machine, then sync.")
        XCTAssertEqual(WidgetResolutionCopy.title(.notFound(type: "acme/x")), "Widget not found")
        XCTAssertEqual(
            WidgetResolutionCopy.detail(.notFound(type: "acme/x"), release: "v39"),
            "acme/x is not in packages release v39 or in your own packages folder.")
    }

    func testTitlesAndGallery() {
        XCTAssertEqual(WidgetTitle.make(type: "devmachine-app/clock"), "Clock")
        XCTAssertEqual(WidgetTitle.make(type: "github/open-prs"), "Open PRs")
        var locked = CatalogFixtures.usage(package: "acme", harness: "acme")
        locked.available = false
        var sidebarOnly = CatalogFixtures.summary
        sidebarOnly.surfaces = ["sidebar"]
        let catalog = CatalogFixtures.catalog([locked, CatalogFixtures.machines, sidebarOnly, CatalogFixtures.clock])
        XCTAssertEqual(
            WidgetGallery.entries(catalog, surface: "home").map(\.name),
            ["devmachine-app/clock", "devmachine-app/machines", "acme/usage"])
    }

    func testWidgetsThatShareANameTakeTheirPackagesName() {
        let catalog = CatalogFixtures.catalog([
            CatalogFixtures.usage(package: "claude-code", harness: "claude"),
            CatalogFixtures.usage(package: "codex", harness: "codex"),
            CatalogFixtures.clock,
        ])
        XCTAssertEqual(WidgetTitle.make(type: "claude-code/usage", in: catalog), "Claude Code usage")
        XCTAssertEqual(WidgetTitle.make(type: "codex/usage", in: catalog), "Codex usage")
        XCTAssertEqual(WidgetTitle.make(type: "devmachine-app/clock", in: catalog), "Clock")
        XCTAssertEqual(WidgetTitle.make(type: "claude-code/usage", in: nil), "Usage")
    }

    func testAPackagesDisplayNameKeepsKnownAcronyms() {
        XCTAssertEqual(WidgetTitle.displayName(package: "claude-code"), "Claude Code")
        XCTAssertEqual(WidgetTitle.displayName(package: "ssh_hardening"), "Ssh Hardening")
        XCTAssertEqual(WidgetTitle.displayName(package: "acme-cli"), "Acme CLI")
        XCTAssertEqual(WidgetTitle.displayName(package: "acme-api-prs"), "Acme API PRs")
    }

    func testTheGalleryHintSplitsTheCommandFromTheAdvice() {
        XCTAssertEqual(
            WidgetGallery.hint("add the package: devmachine packages add acme --machine <name>"),
            WidgetGallery.UnavailableHint(
                advice: "add the package", command: "devmachine packages add acme --machine <name>"))
        XCTAssertEqual(
            WidgetGallery.hint("sync to install the package: devmachine sync"),
            WidgetGallery.UnavailableHint(advice: "sync to install the package", command: "devmachine sync"))
        XCTAssertEqual(
            WidgetGallery.hint("needs a newer app"), WidgetGallery.UnavailableHint(advice: "needs a newer app", command: nil))
        XCTAssertEqual(WidgetGallery.hint(""), WidgetGallery.UnavailableHint(advice: "", command: nil))
    }

    func testAPackageNameWithAnUnderscoreKeepsItWhole() {
        let status = CatalogWidget(
            name: "ssh_hardening/status", source: CatalogSource(name: "ssh_hardening/status", every: "60s"),
            viewKind: "app.summary", sizes: ["small"], defaultSize: "small", available: false)
        XCTAssertEqual(status.package, "ssh_hardening")
        XCTAssertEqual(status.widget, "status")
        XCTAssertEqual(WidgetTitle.make(type: status.name), "Status")
        XCTAssertEqual(
            WidgetResolution.resolve(entry("ssh_hardening/status"), in: CatalogFixtures.catalog([status])),
            .needsPackage(package: "ssh_hardening", reason: ""))
    }
}
