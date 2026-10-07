import XCTest
@testable import DevmachineCore

final class OutputParserTests: XCTestCase {
    private func parse(_ text: String, _ mode: ParseMode) throws -> SourceOutput {
        try OutputParser.parse(Data(text.utf8), as: mode)
    }

    private let root = WidgetValue.object([
        "disk": .object(["used": .int(71), "free-gb": .double(12.5)]),
        "items": .list([.object(["name": .string("a")]), .object(["name": .string("b")])]),
    ])

    func testTextDropsOnlyTrailingNewlines() throws {
        XCTAssertEqual(try parse("  a\nb\n\n", .text), .text("  a\nb"))
        XCTAssertEqual(try parse("a\r\n\r\n", .text), .text("a"))
    }

    func testLinesSplitAndDropTheLastEmptyOne() throws {
        XCTAssertEqual(try parse("a\r\nb\n\nc\n", .lines), .lines(["a", "b", "", "c"]))
        XCTAssertEqual(try parse("", .lines), .lines([]))
    }

    func testNumberIsTheWholeTrimmedOutput() throws {
        XCTAssertEqual(try parse(" 42.5\n", .number), .number(42.5))
        XCTAssertThrowsError(try parse("42 GB", .number)) { error in
            XCTAssertEqual(error as? OutputParseError, OutputParseError(message: "expected a number, got \"42 GB\""))
        }
        XCTAssertThrowsError(try parse("", .number))
        XCTAssertThrowsError(try parse("nan", .number))
        XCTAssertThrowsError(try parse("inf", .number))
    }

    func testJSON() throws {
        XCTAssertEqual(try parse(#"{"used": 71, "items": [{"name": "a"}]}"#, .json),
                       .json(.object(["used": .int(71), "items": .list([.object(["name": .string("a")])])])))
        XCTAssertThrowsError(try parse("{nope", .json)) { error in
            XCTAssertTrue((error as? OutputParseError)?.message.hasPrefix("not valid JSON") ?? false)
        }
    }

    func testANSIKeepsTheEscapes() throws {
        XCTAssertEqual(try parse("\u{1B}[31mred\u{1B}[0m\n", .ansi), .ansi("\u{1B}[31mred\u{1B}[0m"))
    }

    func testStatusNeverComesFromBytes() {
        XCTAssertThrowsError(try parse("200", .status))
    }

    func testInvalidUTF8IsReplacedNotFatal() throws {
        XCTAssertEqual(try OutputParser.parse(Data([0x61, 0xFF, 0x62]), as: .text), .text("a\u{FFFD}b"))
    }

    func testOutputOverTheLimitIsAnError() {
        let data = Data(repeating: 0x61, count: OutputParser.maxBytes + 1)
        XCTAssertThrowsError(try OutputParser.parse(data, as: .text)) { error in
            XCTAssertEqual(error as? OutputParseError, OutputParseError(message: "printed more than 1 MB"))
        }
        XCTAssertNoThrow(try OutputParser.parse(Data(repeating: 0x61, count: OutputParser.maxBytes), as: .text))
    }

    func testJSONPaths() {
        XCTAssertEqual(JSONPath.value("disk.used", in: root), .int(71))
        XCTAssertEqual(JSONPath.value("disk.free-gb", in: root), .double(12.5))
        XCTAssertEqual(JSONPath.value("items.1.name", in: root), .string("b"))
        XCTAssertEqual(JSONPath.value("items.0.name", in: root), .string("a"))
        XCTAssertNil(JSONPath.value("items[1].name", in: root))
        XCTAssertNil(JSONPath.value("items.5.name", in: root))
        XCTAssertNil(JSONPath.value("disk.free", in: root))
        XCTAssertNil(JSONPath.value("disk.used.more", in: root))
        XCTAssertEqual(JSONPath.path(of: "{{ json.disk.used }}"), "disk.used")
        XCTAssertNil(JSONPath.path(of: "{{json.items[0].name}}"))
        XCTAssertNil(JSONPath.path(of: "{{inputs.a}}"))
    }

    func testResolveKeepsAWholeTemplateTypedAndFillsText() {
        XCTAssertEqual(JSONPath.resolve("{{json.disk.used}}", in: root), .int(71))
        XCTAssertEqual(JSONPath.resolve(" {{ json.disk.used }} ", in: root), .int(71))
        XCTAssertEqual(JSONPath.resolve("{{json.disk.used}}%", in: root), .string("71%"))
        XCTAssertEqual(JSONPath.resolve("{{json.items.0.name}} and {{json.items.1.name}}", in: root),
                       .string("a and b"))
        XCTAssertNil(JSONPath.resolve("{{json.disk.free}} GB", in: root))
        XCTAssertNil(JSONPath.resolve("{{json.disk.free}}", in: root))
    }

    func testValueProblemsMatchTheCLI() {
        XCTAssertNil(JSONPath.problem(in: "{{json.used}}"))
        XCTAssertNil(JSONPath.problem(in: "{{json.disk.used}} of {{ json.disk.total }}"))
        XCTAssertNil(JSONPath.problem(in: "{{json.items.0.free-gb}} GB"))
        XCTAssertEqual(JSONPath.problem(in: "used"),
                       #"view.value "used" names no field: write it like "{{json.used}}""#)
        XCTAssertEqual(JSONPath.problem(in: "{{json.a}} {{inputs.a}}"),
                       "template {{inputs.a}} in view.value names json.<path>, like {{json.disk.used}}")
        XCTAssertEqual(JSONPath.problem(in: "{{json.items[0].name}}"),
                       "template {{json.items[0].name}} in view.value names json.<path>, like {{json.disk.used}}")
        XCTAssertEqual(JSONPath.problem(in: "{{json}}"),
                       "template {{json}} in view.value names json.<path>, like {{json.disk.used}}")
    }
}
