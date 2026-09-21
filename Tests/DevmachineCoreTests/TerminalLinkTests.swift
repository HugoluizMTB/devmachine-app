import XCTest
@testable import DevmachineCore

final class TerminalLinkTests: XCTestCase {
    private func target(_ raw: String, folder: String? = nil, files: [String] = []) -> TerminalLink.Target? {
        TerminalLink.target(for: raw, folder: folder, exists: { files.contains($0) })
    }

    func testAWebAddressOpensInTheBrowser() {
        XCTAssertEqual(
            target("https://example.com/pr/42"),
            .web(URL(string: "https://example.com/pr/42")!))
        XCTAssertEqual(
            target("http://localhost:3000"), .web(URL(string: "http://localhost:3000")!))
        XCTAssertEqual(
            target("mailto:alice@example.com"),
            .web(URL(string: "mailto:alice@example.com")!))
    }

    func testAnySchemeOutsideTheListIsRefused() {
        XCTAssertNil(target("javascript:alert(1)"))
        XCTAssertNil(target("x-devil:run"))
        XCTAssertNil(target(""))
    }

    func testAPathIsResolvedInTheSessionFolder() {
        XCTAssertEqual(
            target("Sources/App.swift", folder: "/Users/alice/dev/acme",
                   files: ["/Users/alice/dev/acme/Sources/App.swift"]),
            .file("/Users/alice/dev/acme/Sources/App.swift"))
    }

    func testAFileLocationDropsTheLineAndColumn() {
        XCTAssertEqual(
            target("Sources/App.swift:12:4", folder: "/Users/alice/dev/acme",
                   files: ["/Users/alice/dev/acme/Sources/App.swift"]),
            .file("/Users/alice/dev/acme/Sources/App.swift"))
    }

    func testAFileWhoseNameEndsInNumbersIsOpenedWhole() {
        XCTAssertEqual(
            target("notes:12", folder: "/Users/alice",
                   files: ["/Users/alice/notes:12"]),
            .file("/Users/alice/notes:12"))
    }

    func testASessionOnAnotherMachineOffersNoFolderSoPathsAreRefused() {
        XCTAssertNil(target("Sources/App.swift", folder: nil, files: ["/Sources/App.swift"]))
    }

    func testAPathThatIsNotOnThisMacIsRefused() {
        XCTAssertNil(target("Sources/App.swift", folder: "/Users/alice/dev/acme", files: []))
    }

    func testAFileUrlOpensTheFileItNames() {
        XCTAssertEqual(
            target("file:///Users/alice/dev/acme/README.md",
                   files: ["/Users/alice/dev/acme/README.md"]),
            .file("/Users/alice/dev/acme/README.md"))
    }

    func testTheCopiedTextIsTheLinkItself() {
        XCTAssertEqual(TerminalLink.Target.web(URL(string: "https://example.com")!).text,
                       "https://example.com")
        XCTAssertEqual(TerminalLink.Target.file("/Users/alice/x.txt").text, "/Users/alice/x.txt")
    }
}
