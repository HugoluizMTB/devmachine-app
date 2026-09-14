import XCTest
import DevmachineCore
@testable import DevmachineApp

private final class ListingRunner: CommandRunner, @unchecked Sendable {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String { "" }
}

@MainActor
final class FilesStoreTests: XCTestCase {
    private func makeStore() -> FilesStore {
        let runner = ListingRunner()
        return FilesStore(service: FileService(remote: RemoteService(runner: runner)), runner: runner)
    }

    func testOpeningWithAnAbsolutePathStartsThere() {
        let store = makeStore()

        store.open(alias: "acme-devmachine", path: "/home/alice/dev/dash/Sources")

        XCTAssertEqual(store.alias, "acme-devmachine")
        XCTAssertEqual(store.path, "/home/alice/dev/dash/Sources")
    }

    func testOpeningWithoutAPathStaysAtTheHomeDirectory() {
        let store = makeStore()

        store.open(alias: "acme-devmachine")

        XCTAssertEqual(store.path, ".")
        XCTAssertFalse(store.canGoUp)
    }

    func testGoingUpFromAnAbsolutePathStopsAtTheFilesystemRoot() {
        let store = makeStore()
        store.open(alias: "acme-devmachine", path: "/home/alice")

        store.up()
        XCTAssertEqual(store.path, "/home")

        store.up()
        XCTAssertEqual(store.path, "/")

        XCTAssertFalse(store.canGoUp)
        store.up()
        XCTAssertEqual(store.path, "/")
    }
}
