import XCTest
@testable import DevmachineCore

final class LineRingTests: XCTestCase {
    func testKeepsOnlyTheNewestLines() {
        var ring = LineRing(capacity: 3)
        ring.append(contentsOf: ["a", "b"])
        ring.append(contentsOf: ["c", "d", "e"])
        XCTAssertEqual(ring.lines, ["c", "d", "e"])
    }

    func testAssemblesLinesAcrossChunks() {
        var assembler = LineAssembler()
        XCTAssertEqual(assembler.append(Data("one\ntw".utf8)), ["one"])
        XCTAssertEqual(assembler.append(Data("o\r\nthree".utf8)), ["two"])
        XCTAssertEqual(assembler.flush(), ["three"])
        XCTAssertEqual(assembler.flush(), [])
    }

    func testASplitMultibyteCharacterSurvives() {
        var assembler = LineAssembler()
        let bytes = Array("é\n".utf8)
        XCTAssertEqual(assembler.append(Data(bytes[0..<1])), [])
        XCTAssertEqual(assembler.append(Data(bytes[1...])), ["é"])
    }
}
