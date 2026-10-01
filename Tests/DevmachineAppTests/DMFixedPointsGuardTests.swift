import XCTest

/// A component sizes itself from `DMMetrics`, so a bigger text size never
/// spills out of it. This fails on any new fixed point in `Components/`.
final class DMFixedPointsGuardTests: XCTestCase {
    private static let tokenFiles: Set<String> = ["DMTokens.swift", "DMMetrics.swift"]

    func testNoComponentLaysOutWithAFixedPoint() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/DevmachineApp/Components")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && !Self.tokenFiles.contains($0.lastPathComponent) }
        XCTAssertFalse(files.isEmpty)

        var found: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where !Self.fixedPoints(in: line).isEmpty {
                found.append("\(file.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(found, [], "Use a DMMetrics token (m.space.md, m.pt(_:)) instead of a fixed point")
    }

    func testTheScanCatchesAFixedPointAndLetsTokensAndHairlinesThrough() {
        XCTAssertEqual(Self.fixedPoints(in: ".frame(height: 22)"), ["22"])
        XCTAssertEqual(Self.fixedPoints(in: ".padding(.horizontal, 12)"), ["12"])
        XCTAssertEqual(Self.fixedPoints(in: ".padding(8)"), ["8"])
        XCTAssertEqual(Self.fixedPoints(in: "VStack(alignment: .leading, spacing: 6) {"), ["6"])
        XCTAssertEqual(Self.fixedPoints(in: "Spacer(minLength: 12)"), ["12"])
        XCTAssertEqual(Self.fixedPoints(in: "RoundedRectangle(cornerRadius: 3)"), ["3"])
        XCTAssertEqual(Self.fixedPoints(in: ".frame(width: 1, height: 1)"), [])
        XCTAssertEqual(Self.fixedPoints(in: "HStack(spacing: 0) {"), [])
        XCTAssertEqual(Self.fixedPoints(in: ".padding(m.pt(10))"), [])
        XCTAssertEqual(Self.fixedPoints(in: ".frame(height: m.space.md)"), [])
        XCTAssertEqual(Self.fixedPoints(in: "// .frame(height: 22)"), [])
    }

    /// The number literals other than 0 and 1 that a layout call on `line`
    /// takes as points. `m.pt(_:)` and `m.rem(_:)` scale theirs, so they pass.
    static func fixedPoints(in line: String) -> [String] {
        let code = line.trimmingCharacters(in: .whitespaces)
        guard !code.hasPrefix("//") else { return [] }
        let scaled = code.replacingOccurrences(
            of: #"m\.(pt|rem)\([^()]*\)"#, with: "_", options: .regularExpression)
        let layoutArguments = #"\.(padding|frame)\([^)]*\)|(spacing|minLength|cornerRadius): *[0-9.]+"#
        let numbers = #"(?<![\w.])[0-9]+(\.[0-9]+)?(?![\w.])"#
        var found: [String] = []
        for call in matches(of: layoutArguments, in: scaled) {
            for number in matches(of: numbers, in: call) where number != "0" && number != "1" {
                found.append(number)
            }
        }
        return found
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
}
