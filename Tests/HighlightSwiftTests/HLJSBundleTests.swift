import XCTest
@testable import HighlightSwift

final class HLJSBundleTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HLJSBundleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testNoCandidateDirectoryThrowsFileNotFound() {
        XCTAssertThrowsError(try HLJSBundle.scriptPath(in: [])) { error in
            XCTAssertEqual(error as? HLJSError, .fileNotFound)
        }
    }

    func testADirectoryWithoutTheBundleThrowsFileNotFound() {
        XCTAssertThrowsError(try HLJSBundle.scriptPath(in: [root])) { error in
            XCTAssertEqual(error as? HLJSError, .fileNotFound)
        }
    }

    func testFindsTheScriptInsideAnAppsResources() throws {
        let app = root.appendingPathComponent("Example.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let bundle = resources.appendingPathComponent(HLJSBundle.name, isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let script = bundle.appendingPathComponent("highlight.min.js")
        try Data("var hljs = {};".utf8).write(to: script)

        let path = try HLJSBundle.scriptPath(in: [app, resources])

        XCTAssertEqual(URL(fileURLWithPath: path).resolvingSymlinksInPath(), script.resolvingSymlinksInPath())
    }

    func testTheBuiltBundleIsFoundUnderSwiftTest() throws {
        XCTAssertNoThrow(try HLJSBundle.scriptPath())
    }

    func testHighlightsASwiftSnippet() async throws {
        let result = try await HLJS().highlight("let answer = 42", mode: .language(.swift))

        XCTAssertEqual(result.language, "swift")
        XCTAssertTrue(result.value.contains("hljs-keyword"), result.value)
    }
}
