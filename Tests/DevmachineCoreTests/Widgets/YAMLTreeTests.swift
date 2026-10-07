import XCTest
import Yams
@testable import DevmachineCore

final class YAMLTreeTests: XCTestCase {
    private func tree(_ text: String) throws -> YAMLTree {
        try YAMLTree(node: XCTUnwrap(try Yams.compose(yaml: text)), text: text)
    }

    func testValuesFollowYAMLScalarRules() throws {
        let value = try tree("{a: 1, b: '1', c: true, d: 1.5, e: x y, f: [p, \"q\"], g: null}").value
        XCTAssertEqual(value, .object([
            "a": .int(1), "b": .string("1"), "c": .bool(true), "d": .double(1.5), "e": .string("x y"),
            "f": .list([.string("p"), .string("q")]), "g": .null,
        ]))
    }

    func testLinesOfNestedFields() throws {
        let source = try tree("kind: command\nrun: df\nargs:\n  - -h\n  - /\nevery: 60s\n")
        XCTAssertEqual(source.line(at: ["every"]), 6)
        XCTAssertEqual(source.line(at: ["args", "1"]), 5)
        XCTAssertEqual(source.line(at: ["missing"]), nil)
    }

    func testEmitKeepsEachStyle() throws {
        let source = try tree("kind: command\nrun: df\nargs: [-h, 'x; y', \"a\\tb\"]\ntarget: {workspace: alice}\n")
        XCTAssertEqual(source.emit(key: "source", indent: 4), [
            "    source:",
            "      kind: command",
            "      run: df",
            "      args: [-h, 'x; y', \"a\\tb\"]",
            "      target: {workspace: alice}",
        ])
        XCTAssertEqual(try tree("{kind: text, tail: 20}").emit(key: "view", indent: 4), ["    view: {kind: text, tail: 20}"])
    }

    func testABlockScalarComesBackDoubleQuoted() throws {
        let prompt = try tree("prompt: |\n  line one\n  line two\n")
        XCTAssertEqual(prompt.emit(key: "source", indent: 0), ["source:", "  prompt: \"line one\\nline two\\n\""])
    }

    func testAnAliasIsAProblem() {
        XCTAssertThrowsError(try tree("a: &x 1\nb: *x\n"))
    }

    func testATaggedFlowCollectionStaysFlow() throws {
        XCTAssertEqual(try tree("args: !!seq [-h, /]\n").emit(key: "source", indent: 0), ["source:", "  args: [-h, /]"])
    }

    func testAnAliasToANodeOutsideIsAProblem() throws {
        let text = "keep: &args [-h]\nsource:\n  run: df\n  args: *args\n"
        let root = try XCTUnwrap(try Yams.compose(yaml: text))
        let source = try XCTUnwrap(root["source"])
        XCTAssertThrowsError(try YAMLTree(node: source, text: text))
    }

    func testPlainScalarsResolveLikeYAMLv3() throws {
        let value = try tree("""
            {a: True, b: FALSE, c: Null, d: ~, e: 0x10, f: 1_000, g: 0o17, h: -0b11, i: 0777, j: +5, k: .5, \
            l: .INF, m: 08, n: yes, o: 1e3, p: 2001-12-14}
            """).value
        XCTAssertEqual(value, .object([
            "a": .bool(true), "b": .bool(false), "c": .null, "d": .null, "e": .int(16), "f": .int(1000), "g": .int(15),
            "h": .int(-3), "i": .int(511), "j": .int(5), "k": .double(0.5), "l": .double(.infinity), "m": .double(8),
            "n": .string("yes"), "o": .double(1000), "p": .string("2001-12-14"),
        ]))
    }

    func testARepeatedKeyIsAProblem() {
        XCTAssertThrowsError(try tree("1: a\n!!str 1: b\n")) { error in
            XCTAssertEqual(error as? BoardProblem, BoardProblem(line: 2, message: "\"1\" appears twice"))
        }
    }

    func testAnAliasAsAKeyIsAProblem() throws {
        let text = "a: &x k\nb:\n  run: df\n  *x : 1\n"
        let source = try XCTUnwrap(try Yams.compose(yaml: text)?["b"])
        XCTAssertThrowsError(try YAMLTree(node: source, text: text)) { error in
            XCTAssertEqual((error as? BoardProblem)?.line, 1)
        }
    }

    func testAScalarWithALineBreakIsNeverWrittenRawInsideQuotesOrPlain() throws {
        let source = try tree("a: 'one\n\n  two'\nb: one\n\n  two\nc: 'it''s'\n")
        XCTAssertEqual(source.emit(key: "source", indent: 0), [
            "source:", "  a: \"one\\ntwo\"", "  b: \"one\\ntwo\"", "  c: 'it''s'",
        ])
    }

    func testLinesBreakWhereLibYAMLBreaksThem() throws {
        let text = "x: 1\r\nsource: {a: [1]}\rview: {b: 2}\u{85}tail: [3]\u{2028}more: {c: 4}\u{2029}last: [5]\n"
        let root = try XCTUnwrap(try Yams.compose(yaml: text))
        let lines = YAMLTree.SourceLines(text)
        for key in ["source", "view", "tail", "more", "last"] {
            let node = try XCTUnwrap(root[key])
            let emitted = try YAMLTree(node: node, lines: lines).emit(key: key, indent: 0)
            XCTAssertEqual(emitted.count, 1, "\(key): \(emitted)")
        }
    }
}
