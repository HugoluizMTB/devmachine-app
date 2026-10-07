import XCTest
@testable import DevmachineCore

@MainActor
final class BoardFileWatcherTests: XCTestCase {
    private var config: URL!

    override func setUp() async throws {
        config = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardFileWatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: config.appendingPathComponent("boards"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: config)
    }

    private func board(id: String) -> String {
        BoardCodec.encode(Board(surface: "home", widgets: [
            BoardWidget(id: id, type: "devmachine-app/clock", frame: BoardFrame(x: 24, y: 24, w: 320, h: 160), size: "medium", z: 1),
        ]))
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testARenamedFileReachesTheStore() async throws {
        let fileURL = BoardStore.homeFileURL(configDirectory: config.path)
        try Data(board(id: "before").utf8).write(to: fileURL, options: .atomic)
        let store = BoardStore(fileURL: fileURL, makeDefault: { DefaultBoard.make(usage: []) })
        store.load()
        let watcher = BoardFileWatcher(fileURL: fileURL) { store.load() }
        XCTAssertTrue(watcher.isWatching)
        try Data(board(id: "after").utf8).write(to: fileURL, options: .atomic)
        await waitUntil { store.board?.widgets.first?.id == "after" }
        XCTAssertEqual(store.board?.widgets.first?.id, "after")
    }

    func testAnInPlaceEditIsSeenToo() async throws {
        let fileURL = BoardStore.homeFileURL(configDirectory: config.path)
        try Data(board(id: "before").utf8).write(to: fileURL, options: .atomic)
        let store = BoardStore(fileURL: fileURL, makeDefault: { DefaultBoard.make(usage: []) })
        store.load()
        let watcher = BoardFileWatcher(fileURL: fileURL) { store.load() }
        try board(id: "edited").write(to: fileURL, atomically: false, encoding: .utf8)
        await waitUntil { store.board?.widgets.first?.id == "edited" }
        XCTAssertEqual(store.board?.widgets.first?.id, "edited")
        _ = watcher
    }

    func testEveryRenameIsSeenNotOnlyTheFirst() async throws {
        let fileURL = BoardStore.homeFileURL(configDirectory: config.path)
        try Data(board(id: "first").utf8).write(to: fileURL, options: .atomic)
        let store = BoardStore(fileURL: fileURL, makeDefault: { DefaultBoard.make(usage: []) })
        store.load()
        let watcher = BoardFileWatcher(fileURL: fileURL) { store.load() }
        for id in ["second", "third", "fourth"] {
            try Data(board(id: id).utf8).write(to: fileURL, options: .atomic)
            await waitUntil { store.board?.widgets.first?.id == id }
            XCTAssertEqual(store.board?.widgets.first?.id, id)
        }
        try board(id: "in-place").write(to: fileURL, atomically: false, encoding: .utf8)
        await waitUntil { store.board?.widgets.first?.id == "in-place" }
        XCTAssertEqual(store.board?.widgets.first?.id, "in-place")
        _ = watcher
    }

    func testAFileDeletedAndWrittenAgainIsSeen() async throws {
        let fileURL = BoardStore.homeFileURL(configDirectory: config.path)
        try Data(board(id: "before").utf8).write(to: fileURL, options: .atomic)
        var changes = 0
        let watcher = BoardFileWatcher(fileURL: fileURL) { changes += 1 }
        try FileManager.default.removeItem(at: fileURL)
        await waitUntil { changes >= 1 }
        XCTAssertGreaterThanOrEqual(changes, 1)
        let seen = changes
        try board(id: "after").write(to: fileURL, atomically: false, encoding: .utf8)
        await waitUntil { changes > seen }
        XCTAssertGreaterThan(changes, seen)
        _ = watcher
    }

    func testAMissingFolderIsNotWatched() {
        let fileURL = BoardStore.homeFileURL(configDirectory: config.appendingPathComponent("absent").path)
        let watcher = BoardFileWatcher(fileURL: fileURL) {}
        XCTAssertFalse(watcher.isWatching)
    }
}
