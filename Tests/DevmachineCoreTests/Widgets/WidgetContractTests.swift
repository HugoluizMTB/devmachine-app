import XCTest
@testable import DevmachineCore

final class WidgetContractTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/widget-contract-1.6.json")
        return try Data(contentsOf: url)
    }

    func testTheGoldenContractIsTheOneThisAppImplements() throws {
        let decoded = try JSONDecoder().decode(WidgetContract.self, from: fixture())
        XCTAssertEqual(decoded, WidgetContract.engine16)
        XCTAssertEqual(WidgetContract.current, WidgetContract.engine16)
        XCTAssertEqual(WidgetContract.current.engine, "1.6")
    }

    func testAPromptTakesItsHarnesssOwnPermissionModes() throws {
        let fields = try XCTUnwrap(WidgetContract.current.sources["prompt"]?.fields)
        let mode = try XCTUnwrap(fields["permission_mode"])
        XCTAssertEqual(mode.type, "enum-by-harness")
        XCTAssertFalse(mode.required)
        XCTAssertNil(mode.values)
        XCTAssertEqual(mode.byHarness?["claude"], ["manual", "dontAsk", "plan", "acceptEdits", "auto", "bypassPermissions"])
        XCTAssertEqual(mode.byHarness?["codex"],
                       ["read-only", "workspace-write", "danger-full-access", "approve-for-me", "dangerously-bypass-approvals-and-sandbox"])
        XCTAssertEqual(Set(mode.byHarness.map { Array($0.keys) } ?? []), Set(fields["harness"]?.values ?? []))
        XCTAssertEqual(mode.dangerous, ["bypassPermissions", "danger-full-access", "dangerously-bypass-approvals-and-sandbox"])
        for (kind, spec) in WidgetContract.current.sources where kind != "prompt" {
            XCTAssertNil(spec.fields["permission_mode"], kind)
        }
    }

    func testChoiceInputsAndTheirSources() {
        let contract = WidgetContract.current
        XCTAssertEqual(Set(contract.inputTypes.keys), ["string", "number", "boolean", "choice"])
        XCTAssertEqual(contract.inputTypes["choice"]?.fields?["from"]?.values, ["harnesses", "machines", "workspaces"])
        XCTAssertEqual(contract.inputTypes["choice"]?.fields?["many"]?.defaultValue, .bool(false))
        XCTAssertEqual(Set(contract.optionSources.keys), ["machines", "workspaces", "harnesses"])
        XCTAssertEqual(contract.optionSources["harnesses"]?.values, ["claude", "codex"])
        XCTAssertEqual(contract.optionSources["machines"]?.config, "machines")
        XCTAssertEqual(contract.entryOverrides["every"]?.type, "every")
        XCTAssertEqual(contract.entryOverrides["title"]?.type, "string")
    }

    func testMachinesTakeAListAndPullRequestsSitAnywhere() {
        let contract = WidgetContract.current
        XCTAssertEqual(contract.providers["app/machines"]?.args["machines"], .init(type: "list", required: false))
        XCTAssertEqual(contract.views["app.pull-requests-panel"]?.layouts, ["tabs", "canvas", "stack"])
    }

    func testTheMenuBarIsASlotAndItsPanelIsTabs() {
        let contract = WidgetContract.current
        XCTAssertEqual(contract.layout(of: "menubar"), "slot")
        XCTAssertEqual(contract.layout(of: "menubar-panel"), "tabs")
        XCTAssertEqual(contract.layout(of: "sidebar"), "stack")
        XCTAssertEqual(contract.layout(of: "nowhere"), "stack")
        for surface in ["menubar", "menubar-panel"] {
            XCTAssertEqual(contract.surfaces[surface]?.status, "available", surface)
            XCTAssertEqual(contract.surfaces[surface]?.context, [:], surface)
        }
        XCTAssertTrue(contract.layouts.contains("tabs"))
    }

    func testTheSlotAndTabsRules() {
        let contract = WidgetContract.current
        XCTAssertEqual(contract.slotMax, 3)
        XCTAssertEqual(Set(contract.slotEntry.forbids), ["frame", "size", "collapsed", "z", "minimized"])
        XCTAssertEqual(Set(contract.slotEntry.views), ["text", "number", "status", "app.brand"])
        XCTAssertEqual(contract.slotEntry.textMax, 24)
        XCTAssertEqual(contract.slotFloor, 30)
        XCTAssertEqual(Set(contract.tabsEntry.forbids), ["frame", "z", "minimized", "collapsed"])
        XCTAssertEqual(contract.tabsEntry.ignores, ["size"])
    }

    func testTheMenubarProvidersAndViews() {
        let contract = WidgetContract.current
        XCTAssertEqual(contract.providers["app/brand"]?.returns, ["mark": "string"])
        XCTAssertEqual(contract.providers["app/open-pull-requests"]?.returns, ["count": "number"])
        XCTAssertEqual(
            contract.providers["app/pull-requests-panel"]?.returns,
            ["pull_requests": "list", "owners": "list", "error": "string?"])
        XCTAssertEqual(contract.providers["app/usage-panel"]?.returns, ["harnesses": "list"])
        XCTAssertEqual(contract.requiredContext(ofProvider: "app/open-pull-requests"), [])
        XCTAssertTrue(contract.view("number", accepts: "app/open-pull-requests"))
        XCTAssertFalse(contract.view("text", accepts: "app/open-pull-requests"))
        XCTAssertTrue(contract.view("app.pull-requests-panel", accepts: "app/pull-requests-panel"))
        XCTAssertTrue(contract.view("app.brand", accepts: "app/brand"))
        XCTAssertTrue(contract.view("app.usage-panel", accepts: "app/usage-panel"))
        XCTAssertEqual(contract.views["app.brand"]?.layouts, ["slot"])
        XCTAssertEqual(contract.views["app.pull-requests-panel"]?.layouts, ["tabs", "canvas", "stack"])
        XCTAssertEqual(contract.views["app.usage-panel"]?.layouts, ["tabs"])
        XCTAssertEqual(contract.views["number"]?.fields?["hide_zero"], .init(type: "bool", defaultValue: .bool(false)))
    }

    func testPackageProvidersRunOnAMachineOrWorkspaceAndTakeTargetAndTimeout() {
        let contract = WidgetContract.current
        XCTAssertEqual(contract.packageProvider.name, "<package>/<command>")
        XCTAssertEqual(contract.packageProvider.reserved, ["app"])
        XCTAssertEqual(contract.packageProvider.targets, ["machine", "workspace"])
        XCTAssertEqual(contract.packageProvider.minEvery, "5s")
        XCTAssertEqual(contract.packageProviderFloor, 5)
        XCTAssertEqual(contract.packageProvider.returns, ["string", "number", "bool", "list", "object"])
        XCTAssertEqual(contract.packageProvider.optional, "?")
        XCTAssertEqual(contract.packageProvider.output, "json")
        XCTAssertEqual(contract.packageProvider.approval, "third-party")
        XCTAssertEqual(contract.packageProvider.trust, ["official", "local", "third-party"])
        let fields = contract.sources["provider"]?.fields ?? [:]
        XCTAssertEqual(Set(fields.keys), ["name", "with", "every", "target", "timeout"])
        XCTAssertEqual(fields["every"]?.type, "every")
        XCTAssertNil(fields["target"]?.defaultValue)
        XCTAssertEqual(fields["timeout"]?.defaultValue, .string("30s"))
        XCTAssertEqual(fields["timeout"]?.max, .string("10m"))
        XCTAssertFalse(contract.needsApproval("provider"))
    }

    func testBothSidebarsAreAvailableStacks() {
        let contract = WidgetContract.current
        for surface in ["sidebar", "context-sidebar"] {
            XCTAssertEqual(contract.surfaces[surface]?.layout, "stack", surface)
            XCTAssertEqual(contract.surfaces[surface]?.status, "available", surface)
        }
        XCTAssertEqual(contract.stackRow, 40)
        XCTAssertEqual(contract.stackEntry.forbids, ["frame", "z"])
        XCTAssertEqual(contract.stackEntry.size, "preset | auto")
        XCTAssertEqual(contract.stackEntry.collapsed, "bool")
    }

    func testTheSidebarProvidersSayWhichContextTheyNeed() {
        let contract = WidgetContract.current
        XCTAssertEqual(contract.requiredContext(ofProvider: "app/session-context"), ["session"])
        XCTAssertEqual(contract.requiredContext(ofProvider: "app/shortcuts"), ["session"])
        XCTAssertEqual(contract.requiredContext(ofProvider: "app/workspaces"), [])
        XCTAssertEqual(contract.requiredContext(ofProvider: "app/publish-port"), [])
        XCTAssertEqual(contract.requiredContext(ofProvider: "app/clock"), [])
        XCTAssertEqual(contract.requiredContext(ofProvider: "nope"), [])
        for name in ["app/workspaces", "app/session-context", "app/shortcuts", "app/publish-port"] {
            XCTAssertEqual(contract.minimumInterval(for: name), 5, name)
        }
    }

    func testTheNineSidebarViewsGrowInAStack() {
        let contract = WidgetContract.current
        let accepts = [
            "app.workspaces": "app/workspaces", "app.shortcuts": "app/shortcuts", "app.publish-port": "app/publish-port",
            "app.monitors": "app/session-context", "app.shells": "app/session-context",
            "app.sub-agents": "app/session-context", "app.todo": "app/session-context",
            "app.pull-requests": "app/session-context", "app.links": "app/session-context",
        ]
        for (view, provider) in accepts {
            XCTAssertEqual(contract.views[view]?.layouts, ["stack"], view)
            XCTAssertTrue(contract.viewGrows(view), view)
            XCTAssertTrue(contract.view(view, accepts: provider), view)
        }
        XCTAssertNil(contract.views["text"]?.layouts)
        XCTAssertFalse(contract.viewGrows("text"))
        XCTAssertFalse(contract.viewGrows("app.clock"))
        XCTAssertFalse(contract.viewGrows("nope"))
    }

    func testPresetsAreCellsOfTheUnit() {
        let contract = WidgetContract.current
        XCTAssertEqual(contract.unit, 80)
        XCTAssertEqual(contract.snap, 8)
        XCTAssertEqual(contract.presetCells("wide")?.columns, 8)
        XCTAssertEqual(contract.presetCells("wide")?.rows, 2)
        XCTAssertNil(contract.presetCells("huge"))
        XCTAssertEqual(WidgetContract.presetOrder, ["small", "medium", "large", "wide", "tall"])
    }

    func testEveryAppProviderAsksForAtLeastFiveSeconds() {
        for name in ["app/clock", "app/summary", "app/machines", "app/harness-usage"] {
            XCTAssertEqual(WidgetContract.current.minimumInterval(for: name), 5, name)
        }
        XCTAssertNil(WidgetContract.current.minimumInterval(for: "command"))
    }

    func testSourceMinimumsComeFromTheContract() {
        let contract = WidgetContract.current
        XCTAssertEqual(contract.minimumInterval(forSource: "command"), 5)
        XCTAssertEqual(contract.minimumInterval(forSource: "url"), 5)
        XCTAssertEqual(contract.minimumInterval(forSource: "session"), 2)
        XCTAssertEqual(contract.minimumInterval(forSource: "prompt"), 900)
        XCTAssertNil(contract.minimumInterval(forSource: "provider"))
    }

    func testOnlyCommandPromptAndSessionWaitForApproval() {
        let contract = WidgetContract.current
        XCTAssertEqual(contract.sourceKinds.filter(contract.needsApproval), ["command", "prompt", "session"])
    }

    func testAViewAcceptsATokenOrAWholeKind() {
        let contract = WidgetContract.current
        XCTAssertTrue(contract.view("app.clock", accepts: "app/clock"))
        XCTAssertFalse(contract.view("app.clock", accepts: "app/summary"))
        XCTAssertTrue(contract.view("web", accepts: "status", sourceKind: "url"))
        XCTAssertFalse(contract.view("web", accepts: "text", sourceKind: "command"))
        XCTAssertTrue(contract.view("terminal", accepts: nil, sourceKind: "session"))
        XCTAssertFalse(contract.view("text", accepts: nil, sourceKind: "session"))
        XCTAssertTrue(contract.view("markdown", accepts: "text", sourceKind: "command"))
        XCTAssertFalse(contract.view("gauge", accepts: "text", sourceKind: "command"))
    }

    func testFieldSchemasCarryDefaultsAndLimits() {
        let command = WidgetContract.current.sources["command"]
        XCTAssertEqual(command?.fields["timeout"]?.defaultValue, .string("30s"))
        XCTAssertEqual(command?.fields["timeout"]?.max, .string("10m"))
        XCTAssertEqual(command?.fields["keep"]?.max, .int(2000))
        XCTAssertEqual(WidgetContract.current.views["web"]?.fields?["zoom"]?.min, .double(0.5))
        XCTAssertEqual(WidgetContract.current.views["list"]?.fields?["item"]?.fields?["title"]?.defaultValue, .string("{{item}}"))
    }

    func testGoDurations() {
        XCTAssertEqual(GoDuration.seconds("60s"), 60)
        XCTAssertEqual(GoDuration.seconds("1m30s"), 90)
        XCTAssertEqual(GoDuration.seconds("500ms"), 0.5)
        XCTAssertEqual(GoDuration.seconds("1h"), 3600)
        XCTAssertEqual(GoDuration.seconds("15m"), 900)
        XCTAssertEqual(GoDuration.seconds("0"), 0)
        XCTAssertNil(GoDuration.seconds("5"))
        XCTAssertNil(GoDuration.seconds(""))
        XCTAssertNil(GoDuration.seconds("abc"))
    }
}
