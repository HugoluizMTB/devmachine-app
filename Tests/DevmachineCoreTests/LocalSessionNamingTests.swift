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

    func testTheHandleDefaultsToTheName() {
        let session = LocalSession(name: "acme", path: "/tmp/acme")
        XCTAssertEqual(session.handle, "acme")
        XCTAssertEqual(session.id, "acme")
    }

    func testAStoredSessionWithoutAHandleKeepsItsNameAsOne() throws {
        let json = #"{"name":"acme","path":"/tmp/acme"}"#.data(using: .utf8)!
        let session = try JSONDecoder().decode(LocalSession.self, from: json)
        XCTAssertEqual(session.handle, "acme")
        XCTAssertEqual(session.name, "acme")
    }

    func testARenamedSessionKeepsItsHandle() throws {
        let stored = LocalSession(handle: "acme", name: "Client work", path: "/tmp/acme")
        let round = try JSONDecoder().decode(
            LocalSession.self, from: JSONEncoder().encode(stored))
        XCTAssertEqual(round.handle, "acme")
        XCTAssertEqual(round.name, "Client work")
        XCTAssertEqual(round.id, "acme")
    }
}
