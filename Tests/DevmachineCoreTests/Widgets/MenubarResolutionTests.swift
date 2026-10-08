import XCTest
@testable import DevmachineCore

final class MenubarResolutionTests: XCTestCase {
    private let menubar = DefaultStackBoard.make(surface: "menubar")
    private let panel = DefaultStackBoard.make(surface: "menubar-panel")

    private func ready(_ resolution: WidgetResolution?) -> ResolvedWidget? {
        if case let .ready(resolved)? = resolution { return resolved }
        return nil
    }

    private func command(
        _ name: String, fits: [String], view: String, every: String? = "60s", mode: String? = nil, parse: String? = nil
    ) -> CatalogWidget {
        var raw: [String: WidgetValue] = ["kind": .string("command"), "run": .string("uptime")]
        if let every { raw["every"] = .string(every) }
        if let mode { raw["mode"] = .string(mode) }
        if let parse { raw["parse"] = .string(parse) }
        var widget = CatalogWidget(
            name: name, fits: fits, source: CatalogSource(raw: .object(raw)), viewKind: view, sizes: ["small"],
            defaultSize: "small", places: [], surfaces: ["menubar", "menubar-panel"])
        widget.view = .object(["kind": .string(view)])
        return widget
    }

    private func board(_ surface: String, _ entries: [StackEntry]) -> StackBoard {
        StackBoard(surface: surface, entries: entries)
    }

    func testTheMenubarAppWidgetsResolveWithoutTheCatalog() throws {
        let expected = [
            "brand": ("app/brand", "app.brand"), "open-pull-requests": ("app/open-pull-requests", "number"),
            "pull-requests-panel": ("app/pull-requests-panel", "app.pull-requests-panel"),
            "usage-panel": ("app/usage-panel", "app.usage-panel"),
        ]
        for (entry, board) in menubar.entries.map({ ($0, menubar) }) + panel.entries.map({ ($0, panel) }) {
            let resolved = try XCTUnwrap(ready(StackResolution.resolve(entry, on: board, catalog: nil)), entry.id)
            XCTAssertEqual(resolved.provider, expected[entry.id]?.0, entry.id)
            XCTAssertEqual(resolved.viewKind, expected[entry.id]?.1, entry.id)
        }
    }

    func testTheMenubarWidgetsStayOutOfTheSidebars() {
        let names = StackGallery.entries(nil, surface: "context-sidebar").map(\.name)
        XCTAssertFalse(names.contains { $0.hasSuffix("/usage-panel") || $0.hasSuffix("/brand") })
        XCTAssertTrue(names.contains("devmachine-app/pull-requests-panel"))
        XCTAssertEqual(
            StackGallery.entries(nil, surface: "menubar").map(\.name),
            ["devmachine-app/brand", "devmachine-app/open-pull-requests"])
        XCTAssertEqual(
            StackGallery.entries(nil, surface: "menubar-panel").map(\.name),
            ["devmachine-app/pull-requests-panel", "devmachine-app/usage-panel"])
    }

    func testAWidgetWithNoViewIsRefusedInTheCLIsWords() {
        XCTAssertEqual(MenubarSlotRules.viewProblem(""), "a widget with no view cannot be drawn in the menu bar")
        XCTAssertEqual(MenubarSlotRules.viewProblem("gauge"), "the gauge view cannot be drawn in the menu bar")
        XCTAssertNil(MenubarSlotRules.viewProblem("text"))
    }

    func testOnlyAFullMenuBarSaysItIsFull() {
        var board = menubar
        XCTAssertNil(StackGallery.fullReason(board))
        board.entries.append(StackEntry(id: "third", type: "acme/third"))
        XCTAssertEqual(StackGallery.fullReason(board), "The menu bar holds 3 widgets")
        XCTAssertNil(StackGallery.fullReason(panel))
    }

    func testAnInlineStreamIsRefusedInTheMenuBar() throws {
        let text = """
            format: 1
            surface: menubar
            widgets:
              - id: tail
                title: Tail
                source: {kind: command, run: journalctl, args: [-f], mode: stream}
                view: {kind: text}

            """
        let board = try BoardCodec.decodeStack(text)
        let entry = try XCTUnwrap(board.entries.first)
        XCTAssertEqual(
            StackResolution.resolve(entry, on: board, catalog: CatalogFixtures.catalog([])),
            .refused(type: "tail", reason: "tail: a stream never ends, so it cannot run in the menu bar: use mode: poll"))
    }

    func testAStreamRunsInAPopoverTab() throws {
        let stream = command("acme/tail", fits: ["tabs"], view: "text", every: nil, mode: "stream")
        let entry = StackEntry(id: "tail", type: stream.name)
        let resolved = try XCTUnwrap(ready(StackResolution.resolve(
            entry, on: board("menubar-panel", [entry]), catalog: CatalogFixtures.catalog([stream]))))
        XCTAssertEqual(resolved.source?.every, .continuous)
    }

    func testTheViewIsCheckedBeforeTheContextAsTheCLIDoes() {
        var gauge = command("acme/cpu", fits: ["slot"], view: "gauge", parse: "number")
        gauge.context = ["selected": "required"]
        let entry = StackEntry(id: "cpu", type: gauge.name)
        XCTAssertEqual(
            StackResolution.resolve(entry, on: board("menubar", [entry]), catalog: CatalogFixtures.catalog([gauge])),
            .refused(type: "acme/cpu", reason: "cpu: the gauge view cannot be drawn in the menu bar"))
    }

    func testAViewTheMenuBarCannotDrawIsRefused() {
        let gauge = command("acme/cpu", fits: ["slot"], view: "gauge", parse: "number")
        let entry = StackEntry(id: "cpu", type: gauge.name)
        XCTAssertEqual(
            StackResolution.resolve(entry, on: board("menubar", [entry]), catalog: CatalogFixtures.catalog([gauge])),
            .refused(type: "acme/cpu", reason: "cpu: the gauge view cannot be drawn in the menu bar"))
    }

    func testTheOpenPullRequestCountHidesAtZero() throws {
        let entry = menubar.entries[1]
        let resolved = try XCTUnwrap(ready(StackResolution.resolve(entry, on: menubar, catalog: nil)))
        XCTAssertEqual(resolved.widget.view["hide_zero"], .bool(true))
    }

    func testAWidgetThatDoesNotFitTheMenubarKeepsItsPlace() {
        let stackOnly = command("acme/load", fits: ["stack"], view: "text")
        let entry = StackEntry(id: "load", type: stackOnly.name)
        XCTAssertEqual(
            StackResolution.resolve(entry, on: board("menubar", [entry]), catalog: CatalogFixtures.catalog([stackOnly])),
            .refused(type: "acme/load", reason: "acme/load does not fit the menubar area: its fits has no slot"))
    }

    func testASlotWidgetBelowThirtySecondsIsRaised() throws {
        let fast = command("acme/load", fits: ["slot", "tabs"], view: "text", every: "5s")
        let entry = StackEntry(id: "load", type: fast.name)
        let resolved = try XCTUnwrap(ready(StackResolution.resolve(
            entry, on: board("menubar", [entry]), catalog: CatalogFixtures.catalog([fast]))))
        XCTAssertEqual(resolved.source?.every, .interval(30))
        XCTAssertEqual(resolved.every, 30)
        let inPanel = try XCTUnwrap(ready(StackResolution.resolve(
            entry, on: board("menubar-panel", [entry]), catalog: CatalogFixtures.catalog([fast]))))
        XCTAssertEqual(inPanel.source?.every, .interval(5))
    }

    func testAStreamCannotRunInTheMenuBar() {
        let stream = command("acme/tail", fits: ["slot"], view: "text", every: nil, mode: "stream")
        let entry = StackEntry(id: "tail", type: stream.name)
        XCTAssertEqual(
            StackResolution.resolve(entry, on: board("menubar", [entry]), catalog: CatalogFixtures.catalog([stream])),
            .refused(type: "acme/tail", reason: "tail: a stream never ends, so it cannot run in the menu bar: use mode: poll"))
    }

    func testAnInlineSlotWidgetIsRaisedToo() throws {
        let text = "format: 1\nsurface: menubar\nwidgets:\n  - id: up\n    title: Up\n    source: {kind: url, url: https://example.com, every: 5s}\n    view: {kind: status}\n"
        let slots = try BoardCodec.decodeStack(text)
        let resolved = try XCTUnwrap(ready(StackResolution.resolve(slots.entries[0], on: slots, catalog: nil)))
        XCTAssertEqual(resolved.source?.every, .interval(30))
    }

    func testATabIgnoresItsSize() {
        let log = command("acme/log", fits: ["tabs"], view: "text")
        let entry = StackEntry(id: "log", type: log.name, size: .preset("large"))
        XCTAssertNotNil(ready(StackResolution.resolve(
            entry, on: board("menubar-panel", [entry]), catalog: CatalogFixtures.catalog([log]))))
    }

    func testAMenubarWidgetNeedingContextIsRefused() {
        var here = command("acme/here", fits: ["slot"], view: "text")
        here.context = ["session": "required"]
        let entry = StackEntry(id: "here", type: here.name)
        XCTAssertEqual(
            StackResolution.resolve(entry, on: board("menubar", [entry]), catalog: CatalogFixtures.catalog([here])),
            .refused(type: "acme/here", reason: "acme/here needs context.session, which the menubar area does not give"))
    }

    func testTheGalleryOffersOnlySlotViewsAndBlocksAFourth() {
        let gauge = command("acme/cpu", fits: ["slot"], view: "gauge")
        let text = command("acme/load", fits: ["slot"], view: "text")
        let names = StackGallery.entries(CatalogFixtures.catalog([gauge, text]), surface: "menubar").map(\.name)
        XCTAssertTrue(names.contains("acme/load"))
        XCTAssertFalse(names.contains("acme/cpu"))
        let full = board("menubar", ["a", "b", "c"].map { StackEntry(id: $0, type: "acme/\($0)") })
        XCTAssertTrue(StackGallery.isFull(full))
        XCTAssertEqual(StackGallery.blockedReason(for: text, on: full), "The menu bar holds 3 widgets")
        XCTAssertNil(StackGallery.blockedReason(for: text, on: menubar))
    }

    func testPlacementsNeverMakeAFourthSlot() {
        var load = command("acme/load", fits: ["slot"], view: "text")
        load.places = ["menubar"]
        let full = board("menubar", ["a", "b", "c"].map { StackEntry(id: $0, type: "acme/\($0)") })
        let result = StackPlacer.place(on: full, catalog: CatalogFixtures.catalog([load]), placements: WidgetPlacements())
        XCTAssertEqual(result.board, full)
        XCTAssertTrue(result.placements.contains("acme/load", on: "menubar"))
        let roomy = StackPlacer.place(on: menubar, catalog: CatalogFixtures.catalog([load]), placements: WidgetPlacements())
        XCTAssertEqual(roomy.board.entries.map(\.id), ["brand", "open-pull-requests", "load"])
    }

    func testANewSlotOrTabEntryIsWrittenWithoutASize() {
        let load = command("acme/load", fits: ["slot", "tabs", "stack"], view: "text")
        XCTAssertNil(StackPlacer.newEntry(of: load, on: menubar).size)
        XCTAssertNil(StackPlacer.newEntry(of: load, on: panel).size)
        XCTAssertEqual(
            StackPlacer.newEntry(of: load, on: DefaultStackBoard.make(surface: "sidebar")).size, .auto)
        let dial = command("acme/dial", fits: ["slot", "tabs", "stack"], view: "gauge")
        XCTAssertEqual(
            StackPlacer.newEntry(of: dial, on: DefaultStackBoard.make(surface: "sidebar")).size, .preset("small"))
    }

    func testTabTitlesAreTodaysForTheBuiltIns() {
        XCTAssertEqual(MenubarTitles.title(panel.entries[0], resolution: nil, catalog: nil), "Pull Requests")
        XCTAssertEqual(MenubarTitles.title(panel.entries[1], resolution: nil, catalog: nil), "Usage")
        let missing = StackEntry(id: "x", type: "acme/x")
        XCTAssertEqual(
            MenubarTitles.title(missing, resolution: .notFound(type: "acme/x"), catalog: nil),
            WidgetResolutionCopy.title(.notFound(type: "acme/x")))
    }
}
