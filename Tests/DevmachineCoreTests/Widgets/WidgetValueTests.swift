import XCTest
@testable import DevmachineCore

final class WidgetValueTests: XCTestCase {
    func testDecodesEveryJSONKind() throws {
        let json = #"{"s":"x","i":3,"d":0.5,"b":true,"l":[1,"a"],"o":{"k":null}}"#
        let value = try JSONDecoder().decode(WidgetValue.self, from: Data(json.utf8))
        XCTAssertEqual(value, .object([
            "s": .string("x"), "i": .int(3), "d": .double(0.5), "b": .bool(true),
            "l": .list([.int(1), .string("a")]), "o": .object(["k": .null]),
        ]))
    }

    func testCanonicalJSONSortsKeysAndEscapes() {
        let value = WidgetValue.object([
            "b": .list([.string("x; rm -rf ~"), .string("a\"b\\c\n")]), "a": .bool(false), "c": .int(7),
        ])
        XCTAssertEqual(value.canonicalJSON, #"{"a":false,"b":["x; rm -rf ~","a\"b\\c\n"],"c":7}"#)
    }

    func testTextIsWhatATemplateSees() {
        XCTAssertEqual(WidgetValue.string("x").text, "x")
        XCTAssertEqual(WidgetValue.int(8080).text, "8080")
        XCTAssertEqual(WidgetValue.double(1.5).text, "1.5")
        XCTAssertEqual(WidgetValue.bool(true).text, "true")
        XCTAssertEqual(WidgetValue.null.text, "")
    }

    func testNumberReadsIntsDoublesAndNumericText() {
        XCTAssertEqual(WidgetValue.int(3).number, 3)
        XCTAssertEqual(WidgetValue.double(0.5).number, 0.5)
        XCTAssertEqual(WidgetValue.string(" 42 ").number, 42)
        XCTAssertNil(WidgetValue.string("abc").number)
        XCTAssertNil(WidgetValue.bool(true).number)
    }
}
