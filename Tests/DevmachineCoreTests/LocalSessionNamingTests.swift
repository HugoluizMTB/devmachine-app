import XCTest
@testable import DevmachineCore

final class LocalSessionNamingTests: XCTestCase {
    func testUsesTheFolderName() {
        XCTAssertEqual(
            LocalSessionNaming.name(for: "/Users/alice/dev/acme", existing: []), "acme")
    }

    func testNumbersARepeatedFolderName() {
        XCTAssertEqual(
            LocalSessionNaming.name(for: "/Users/alice/dev/acme", existing: ["acme"]), "acme 2")
        XCTAssertEqual(
            LocalSessionNaming.name(for: "/Users/alice/dev/acme", existing: ["acme", "acme 2"]),
            "acme 3")
    }

    func testFallsBackWhenThePathHasNoName() {
        XCTAssertEqual(LocalSessionNaming.name(for: "/", existing: []), "shell")
    }
}
