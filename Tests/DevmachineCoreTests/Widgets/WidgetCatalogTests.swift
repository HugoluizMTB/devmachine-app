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
        XCTAssertEqual(catalog.engine, "1.0")
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
        XCTAssertEqual(resolved.minimum, CanvasSize(w: 160, h: 40))
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
        future.requiresEngine = ">= 1.9"
        var gauge = CatalogFixtures.summary
        gauge.viewKind = "gauge"
        let catalog = CatalogFixtures.catalog([locked, future, gauge])

        XCTAssertEqual(
            WidgetResolution.resolve(entry("acme/usage"), in: catalog),
            .needsPackage(package: "acme", reason: "add the package: devmachine packages add acme --machine <name>"))
        XCTAssertEqual(WidgetResolution.resolve(entry("github-prs/open"), in: catalog), .notFound(type: "github-prs/open"))
        XCTAssertEqual(
            WidgetResolution.resolve(entry("devmachine-app/clock"), in: catalog),
            .needsNewerApp(type: "devmachine-app/clock", reason: "it needs engine >= 1.9; this app implements 1.8"))
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

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    func testDecodesEveryEngine11Source() throws {
        let catalog = try WidgetCatalog.decode(fixture("widgets-list-engine-1.1.json"))
        XCTAssertEqual(catalog.widgets.map(\.source.kind), ["command", "command", "url", "prompt", "session"])
        let disk = try XCTUnwrap(catalog.widget(named: "mine/disk"))
        XCTAssertEqual(disk.source.name, "")
        XCTAssertEqual(disk.source.raw["run"], .string("df"))
        XCTAssertEqual(disk.view, .object(["kind": .string("text"), "tail": .int(20)]))
        XCTAssertEqual(disk.viewKind, "text")
        XCTAssertEqual(disk.packagePath, "/Users/alice/.config/devmachine/packages/mine")
    }

    func testTheEngine10CatalogStillDecodes() throws {
        let catalog = try WidgetCatalog.decode(fixture("widgets-list-cli-0.9.0.json"))
        XCTAssertFalse(catalog.widgets.isEmpty)
        XCTAssertTrue(catalog.widgets.allSatisfy { $0.source.kind == "provider" && !$0.source.name.isEmpty })
    }

    func testSingleIsReadAndDefaultsToFalse() throws {
        let json = #"""
        {"engine": "1.2", "packages_release": "2026.10.07", "widgets": [
          {"name": "devmachine-app/workspaces", "package": "devmachine-app", "widget": "workspaces",
           "single": true, "fits": ["stack"], "source": {"kind": "provider", "name": "app/workspaces", "every": "5s"},
           "view": {"kind": "app.workspaces"}, "surfaces": ["sidebar", "context-sidebar"], "available": true},
          {"name": "devmachine-app/links", "package": "devmachine-app", "widget": "links",
           "fits": ["stack"], "source": {"kind": "provider", "name": "app/session-context", "every": "5s"},
           "view": {"kind": "app.links"}, "surfaces": ["context-sidebar"], "available": true}]}
        """#
        let catalog = try WidgetCatalog.decode(Data(json.utf8))
        XCTAssertEqual(catalog.widget(named: "devmachine-app/workspaces")?.single, true)
        XCTAssertEqual(catalog.widget(named: "devmachine-app/links")?.single, false)
        XCTAssertFalse(CatalogWidget.inline(id: "a", title: "A", sizes: [], fits: [], viewKind: "text").single)
    }

    private func catalog(_ name: String) throws -> WidgetCatalog {
        try WidgetCatalog.decode(fixture(name))
    }

    func testEachWidgetSaysWhereItsCodeComesFrom() throws {
        let catalog = try catalog("widgets-list-engine-1.3.json")
        XCTAssertEqual(catalog.widget(named: "devmachine-app/machine-stats")?.trust, .official)
        XCTAssertEqual(catalog.widget(named: "mine/uptime")?.trust, .local)
        let load = try XCTUnwrap(catalog.widget(named: "acme-tools/load"))
        XCTAssertEqual(load.trust, .thirdParty)
        XCTAssertEqual(load.packageSource, CatalogPackageSource(
            url: "https://example.com/acme/acme-tools.git", ref: "v1.2.0",
            commit: "1111111111111111111111111111111111111111"))
        XCTAssertNil(catalog.widget(named: "mine/uptime")?.packageSource)
    }

    func testAPackageProviderWidgetCarriesItsProvidersSpec() throws {
        let catalog = try catalog("widgets-list-engine-1.3.json")
        XCTAssertEqual(catalog.widget(named: "acme-tools/load")?.packageProvider,
                       PackageProviderSpec(returns: ["load": "number"], minEvery: "10s"))
        XCTAssertNil(catalog.widget(named: "acme-tools/disk")?.packageProvider)
        XCTAssertEqual(catalog.providers?.map(\.name), ["acme-tools/load", "devmachine-app/stats"])
        XCTAssertEqual(catalog.providers?.first?.spec, PackageProviderSpec(returns: ["load": "number"], minEvery: "10s"))
    }

    func testTheIndexIsCompleteOnlyWhenTheCLIListedEveryProvider() throws {
        let index = try catalog("widgets-list-engine-1.3.json").packageProviderIndex
        XCTAssertTrue(index.isComplete)
        XCTAssertEqual(try index.spec(for: "devmachine-app/stats")?.minEvery, "30s")
        XCTAssertTrue(index.packages.isSuperset(of: ["acme-tools", "devmachine-app", "mine"]))
        XCTAssertThrowsError(try index.spec(for: "ghost/load"))
        XCTAssertThrowsError(try index.spec(for: "mine/load"))

        let older = try catalog("widgets-list-engine-1.1.json").packageProviderIndex
        XCTAssertFalse(older.isComplete)
        XCTAssertNil(try older.spec(for: "ghost/load"))
    }

    func testAThirdPartyProviderEntryCarriesItsPackageSource() throws {
        let provider = try XCTUnwrap(catalog("widgets-list-engine-1.3.json").providers?.first { $0.name == "acme-tools/load" })
        XCTAssertEqual(provider.trust, .thirdParty)
        XCTAssertEqual(provider.packageSource, CatalogPackageSource(
            url: "https://example.com/acme/acme-tools.git", ref: "v1.2.0", commit: String(repeating: "1", count: 40)))
        let official = try XCTUnwrap(catalog("widgets-list-engine-1.3.json").providers?.first { $0.name == "devmachine-app/stats" })
        XCTAssertNil(official.packageSource)
    }

    func testAnEmptyProviderListStillMakesTheIndexComplete() throws {
        let json = #"{"engine": "1.3", "packages_release": "v41", "providers": {}, "widgets": []}"#
        let catalog = try WidgetCatalog.decode(Data(json.utf8))
        XCTAssertEqual(catalog.providers, [])
        XCTAssertTrue(catalog.packageProviderIndex.isComplete)
    }

    private func decodedTrust(_ extra: String, origin: String = "release") throws -> WidgetTrust? {
        let json = """
        {"engine": "1.3", "widgets": [{"name": "acme-tools/disk", "package": "acme-tools", "widget": "disk",
          "origin": "\(origin)"\(extra), "source": {"kind": "url", "url": "https://example.com", "every": "60s"},
          "view": {"kind": "status"}}]}
        """
        return try WidgetCatalog.decode(Data(json.utf8)).widgets.first?.trust
    }

    func testATrustThatDoesNotReadIsThirdParty() throws {
        for value in [#""community""#, #""""#, "42", "{}", "null"] {
            XCTAssertEqual(try decodedTrust(#", "trust": \#(value)"#), .thirdParty, value)
        }
    }

    func testAPackageSourceWithoutTrustIsThirdParty() throws {
        let source = #", "package_source": {"url": "https://example.com/acme/acme-tools.git", "ref": "v1", "commit": "2222222222222222222222222222222222222222"}"#
        XCTAssertEqual(try decodedTrust(source), .thirdParty)
        XCTAssertEqual(try decodedTrust(source, origin: "local"), .thirdParty)
        XCTAssertEqual(try decodedTrust(#", "package_source": "broken""#), .thirdParty)
        XCTAssertEqual(try decodedTrust(""), .official)
        XCTAssertEqual(try decodedTrust("", origin: "local"), .local)
    }

    func testAMalformedWidgetProviderSpecReadsNilAndThirdParty() throws {
        let json = #"""
        {"engine": "1.3", "widgets": [{"name": "devmachine-app/machine-stats", "package": "devmachine-app",
          "widget": "machine-stats", "origin": "release", "trust": "official", "provider": {"returns": 42},
          "source": {"kind": "provider", "name": "devmachine-app/stats", "every": "60s"}, "view": {"kind": "gauge"}}]}
        """#
        let widget = try XCTUnwrap(WidgetCatalog.decode(Data(json.utf8)).widgets.first)
        XCTAssertNil(widget.packageProvider)
        XCTAssertEqual(widget.trust, .thirdParty)
    }

    func testAMalformedProviderIsLeftOutAndTheRestRead() throws {
        let json = #"""
        {"engine": "1.3", "packages_release": "v41", "widgets": [], "providers": {
          "mine/load": {"package": "mine", "command": "load", "returns": {"load": "number"}, "min_every": "10s"},
          "mine/broken": {"returns": 42, "min_every": "10s"},
          "mine/text": "not an object"}}
        """#
        let catalog = try WidgetCatalog.decode(Data(json.utf8))
        XCTAssertEqual(catalog.providers?.map(\.name), ["mine/load"])
        XCTAssertTrue(catalog.packageProviderIndex.isComplete)
    }

    func testAGoNullReturnsAndAMissingOriginFileStillDecode() throws {
        let json = #"""
        {"engine": "1.3", "providers": {"mine/load": {"package": "mine", "command": "load", "returns": null, "min_every": ""}},
         "widgets": [{"name": "acme-tools/disk", "package": "acme-tools", "widget": "disk", "origin": "local",
           "trust": "third-party", "source": {"kind": "url", "url": "https://example.com", "every": "60s"},
           "view": {"kind": "status"}}]}
        """#
        let catalog = try WidgetCatalog.decode(Data(json.utf8))
        XCTAssertEqual(catalog.providers?.first?.spec, PackageProviderSpec(returns: [:], minEvery: ""))
        let disk = try XCTUnwrap(catalog.widget(named: "acme-tools/disk"))
        XCTAssertEqual(disk.trust, .thirdParty)
        XCTAssertNil(disk.packageSource)
    }

    func testTrustFallsBackByOriginAndAnUnknownWordIsThirdParty() throws {
        let older = try catalog("widgets-list-engine-1.1.json")
        XCTAssertTrue(older.widgets.allSatisfy { $0.trust == .local })
        XCTAssertEqual(WidgetTrust.read(nil, origin: "release"), .official)
        XCTAssertEqual(WidgetTrust.read(nil, origin: "local"), .local)
        XCTAssertEqual(WidgetTrust.read("official", origin: "local"), .official)
        XCTAssertEqual(WidgetTrust.read("third-party", origin: "release"), .thirdParty)
        XCTAssertEqual(WidgetTrust.read("community", origin: "release"), .thirdParty)
        XCTAssertEqual(CatalogFixtures.clock.trust, .official)
        XCTAssertEqual(CatalogWidget.inline(id: "a", title: "A", sizes: [], fits: [], viewKind: "text").trust, .local)
    }

    func testAChoiceInputReadsItsSourceAndAListDefault() throws {
        let json = """
            {"type": "choice", "from": "machines", "many": true, "default": [], "summary": "Machines to show."}
            """
        let input = try JSONDecoder().decode(CatalogInput.self, from: Data(json.utf8))
        XCTAssertTrue(input.isChoice)
        XCTAssertEqual(input.from, "machines")
        XCTAssertTrue(input.many)
        XCTAssertEqual(input.defaultValue, .list([]))
        let plain = try JSONDecoder().decode(CatalogInput.self, from: Data(#"{"type": "string"}"#.utf8))
        XCTAssertFalse(plain.isChoice)
        XCTAssertNil(plain.from)
        XCTAssertFalse(plain.many)
    }
}
