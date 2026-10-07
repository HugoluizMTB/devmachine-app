import XCTest
@testable import DevmachineCore

final class WidgetViewModelsTests: XCTestCase {
    func testOnlyLargeFramesAreFull() {
        let sizes = WidgetContract.presetOrder.map { ($0, CanvasLayout.presetSize($0)!) }
        let full = sizes.filter { WidgetDensity.of(width: Double($0.1.w), height: Double($0.1.h)) == .full }.map(\.0)
        XCTAssertEqual(full, ["large"])
    }

    func testNumberFormats() {
        XCTAssertEqual(NumberText.format(42, format: .plain, unit: "GB"), "42 GB")
        XCTAssertEqual(NumberText.format(3.14159, format: .plain, unit: nil), "3.14")
        XCTAssertEqual(NumberText.format(71.5, format: .percent, unit: nil), "71.5%")
        XCTAssertEqual(NumberText.format(1536, format: .bytes, unit: nil), "1.5 KB")
        XCTAssertEqual(NumberText.format(3_221_225_472, format: .bytes, unit: nil), "3 GB")
        XCTAssertEqual(NumberText.format(3725, format: .duration, unit: nil), "1h 2m")
        XCTAssertEqual(NumberText.format(42, format: .duration, unit: nil), "42s")
        XCTAssertEqual(NumberText.format(1234567, format: .plain, unit: nil), "1234567")
    }

    func testNumbersComeOutOfEveryOutput() throws {
        var view = WidgetView(kind: "gauge")
        XCTAssertEqual(try ValueExtraction.number(from: .number(7), view: view), 7)
        view.value = "{{json.disk.used}}"
        XCTAssertEqual(try ValueExtraction.number(from: .json(.object(["disk": .object(["used": .string("71")])])), view: view), 71)
        XCTAssertThrowsError(try ValueExtraction.number(from: .json(.object([:])), view: view)) { error in
            XCTAssertEqual(error as? ValueError, ValueError(message: "{{json.disk.used}} found nothing in the answer"))
        }
        XCTAssertThrowsError(try ValueExtraction.number(from: .json(.object(["disk": .object(["used": .bool(true)])])), view: view))
    }

    func testGaugeLevels() {
        var view = WidgetView(kind: "gauge")
        view.warn = 80
        view.crit = 95
        view.unit = "%"
        XCTAssertEqual(GaugeModel(value: 50, view: view), GaugeModel(fraction: 0.5, level: .ok, label: "50 %"))
        XCTAssertEqual(GaugeModel(value: 85, view: view).level, .warn)
        XCTAssertEqual(GaugeModel(value: 120, view: view).fraction, 1)
        XCTAssertEqual(GaugeModel(value: 120, view: view).level, .bad)
    }

    func testStatusLevels() throws {
        var view = WidgetView(kind: "status")
        XCTAssertEqual(try StatusModel.make(output: .status(code: 200, latency: 0.084), view: view),
                       StatusModel(level: .ok, label: "200 · 84 ms"))
        XCTAssertEqual(try StatusModel.make(output: .status(code: 503, latency: 1.2), view: view).level, .bad)
        view.okRule = StatusRule.parse("< 300")
        view.warnRule = StatusRule.parse("< 500")
        XCTAssertEqual(try StatusModel.make(output: .status(code: 404, latency: 0.1), view: view).level, .warn)
        var text = WidgetView(kind: "status")
        text.okRule = StatusRule.parse("== \"ok\"")
        XCTAssertEqual(try StatusModel.make(output: .text("ok"), view: text), StatusModel(level: .ok, label: "ok"))
        XCTAssertEqual(try StatusModel.make(output: .text("down"), view: text).level, .bad)
        XCTAssertEqual(try StatusModel.make(output: .text("hello"), view: WidgetView(kind: "status")).level, .neutral)
    }

    func testListItemsFromLinesAndJSON() throws {
        XCTAssertEqual(try ListModel.items(output: .lines(["a", "b"]), template: ListItemTemplate()).map(\.title), ["a", "b"])
        let json = SourceOutput.json(.list([
            .object(["name": .string("api"), "state": .string("up"), "url": .string("https://example.com/api")]),
        ]))
        let items = try ListModel.items(output: json, template: ListItemTemplate(
            title: "{{item.name}}", subtitle: nil, status: "{{item.state}}", link: "{{item.url}}"))
        XCTAssertEqual(items, [ListItem(id: 0, title: "api", subtitle: nil, status: "up", link: URL(string: "https://example.com/api"))])
        XCTAssertThrowsError(try ListModel.items(output: .json(.object([:])), template: ListItemTemplate()))
    }

    func testListItemPathsAreDotsIntoNestedValues() throws {
        let json = SourceOutput.json(.list([
            .object(["owner": .object(["names": .list([.string("alice"), .string("bob")])])]),
        ]))
        let items = try ListModel.items(output: json, template: ListItemTemplate(title: "{{ item.owner.names.1 }}"))
        XCTAssertEqual(items.map(\.title), ["bob"])
    }

    func testAListLinkMustBeAWebAddress() throws {
        let items = try ListModel.items(output: .lines(["file:///etc/passwd"]),
                                        template: ListItemTemplate(title: "{{item}}", link: "{{item}}"))
        XCTAssertNil(items.first?.link)
    }

    func testTextTail() {
        XCTAssertEqual(TextTail.lines(of: "a\nb\nc", tail: 2), ["b", "c"])
        XCTAssertEqual(TextTail.lines(of: "a\nb", tail: nil), ["a", "b"])
    }
}
