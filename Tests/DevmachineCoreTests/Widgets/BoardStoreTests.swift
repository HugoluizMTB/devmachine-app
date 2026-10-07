import XCTest
@testable import DevmachineCore

@MainActor
private final class ManualWriteTimer: BoardWriteTimer {
    private(set) var delay: TimeInterval?
    private var work: (@MainActor @Sendable () -> Void)?

    var isPending: Bool { work != nil }

    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor @Sendable () -> Void) {
        self.delay = delay
        self.work = work
    }

    func cancel() { work = nil }

    func fire() {
        let pending = work
        work = nil
        pending?()
    }
}

@MainActor
final class BoardStoreTests: XCTestCase {
    private var config: URL!
    private var timer: ManualWriteTimer!

    override func setUp() async throws {
        config = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        timer = ManualWriteTimer()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: config)
    }

    private var fileURL: URL { BoardStore.homeFileURL(configDirectory: config.path) }

    private func makeStore() -> BoardStore {
        BoardStore(fileURL: fileURL, timer: timer, makeDefault: { DefaultBoard.make(usage: []) })
    }

    private func writeFile(_ text: String) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: fileURL, options: .atomic)
    }

    private func readFile() throws -> String { try String(contentsOf: fileURL, encoding: .utf8) }

    private let oneWidget = """
        format: 1
        surface: home
        widgets:
          - id: clock
            type: devmachine-app/clock
            frame: {x: 24, y: 24, w: 320, h: 160}
            size: medium
            minimized: false
            z: 1
        """

    func testAMissingFileBecomesTheDefaultBoardOnDisk() throws {
        let store = makeStore()
        store.load()
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(store.board, DefaultBoard.make(usage: []))
        XCTAssertEqual(try readFile(), BoardCodec.encode(DefaultBoard.make(usage: [])))
    }

    func testWithoutAConfigurationFolderTheDefaultWaitsInMemory() throws {
        try FileManager.default.removeItem(at: config)
        let store = makeStore()
        store.load()
        XCTAssertEqual(store.board, DefaultBoard.make(usage: []))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        store.load()
        XCTAssertEqual(try readFile(), BoardCodec.encode(DefaultBoard.make(usage: [])))
    }

    func testAnInvalidFirstReadShowsTheProblemAndNoBoard() throws {
        try writeFile("format: 1\nsurface: home\nwidgets: [oops\n")
        let store = makeStore()
        store.load()
        guard case let .invalid(problem) = store.status else { return XCTFail("not invalid") }
        XCTAssertNotNil(problem.line)
        XCTAssertNil(store.board)
        XCTAssertFalse(store.canEdit)
    }

    func testAnInvalidEditKeepsTheLastGoodBoardAndIsNeverOverwritten() throws {
        try writeFile(oneWidget)
        let store = makeStore()
        store.load()
        let good = store.board
        let broken = oneWidget.replacingOccurrences(of: "id: clock", with: "id: Clock!")
        try writeFile(broken)
        store.load()
        XCTAssertEqual(store.board, good)
        XCTAssertEqual(store.status, .invalid(BoardProblem(
            line: 4, message: "id \"Clock!\" may use only a-z, 0-9 and -, and starts with a letter or digit")))
        store.update { $0.widgets[0].frame.x = 400 }
        store.flush()
        XCTAssertEqual(try readFile(), broken)
        XCTAssertFalse(timer.isPending)
    }

    func testAFixedFileIsReadAgain() throws {
        try writeFile("format: 1\nsurface: home\nwidgets: [oops\n")
        let store = makeStore()
        store.load()
        try writeFile(oneWidget)
        store.load()
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(store.board?.widgets.map(\.id), ["clock"])
    }

    func testChangesAreWrittenOnceAfterTheDelay() throws {
        try writeFile(oneWidget)
        let store = makeStore()
        store.load()
        store.update { $0.widgets[0].frame.x = 104 }
        store.update { $0.widgets[0].frame.y = 56 }
        XCTAssertEqual(timer.delay, BoardStore.writeDelay)
        XCTAssertEqual(BoardStore.writeDelay, 0.3)
        XCTAssertEqual(try readFile(), oneWidget)
        timer.fire()
        let written = try BoardCodec.decode(readFile())
        XCTAssertEqual(written.widgets.first?.frame, BoardFrame(x: 104, y: 56, w: 320, h: 160))
    }

    func testAPendingWriteGivesWayToAFileChangedOnDisk() throws {
        try writeFile(oneWidget)
        let store = makeStore()
        store.load()
        store.update { $0.widgets[0].frame.x = 104 }
        let fromCLI = oneWidget.replacingOccurrences(of: "x: 24", with: "x: 600")
        try writeFile(fromCLI)
        timer.fire()
        XCTAssertEqual(try readFile(), fromCLI)
        XCTAssertEqual(store.board?.widgets.first?.frame.x, 600)
    }

    func testItsOwnWriteIsNotReadAsAChange() throws {
        try writeFile(oneWidget)
        let store = makeStore()
        store.load()
        store.update { $0.widgets[0].z = 5 }
        timer.fire()
        let after = store.board
        store.load()
        XCTAssertEqual(store.board, after)
        XCTAssertEqual(store.status, .ready)
    }

    func testResetKeepsABackupEvenOfABrokenFile() throws {
        let broken = "format: 1\nsurface: home\nwidgets: [oops\n"
        try writeFile(broken)
        let store = makeStore()
        store.load()
        try store.reset()
        XCTAssertEqual(try String(contentsOf: store.backupURL, encoding: .utf8), broken)
        XCTAssertEqual(store.backupURL.lastPathComponent, "home.yml.bak")
        XCTAssertEqual(try readFile(), BoardCodec.encode(DefaultBoard.make(usage: [])))
        XCTAssertEqual(store.status, .ready)
    }

    func testResetWithoutAConfigurationFolderWritesNothing() throws {
        try FileManager.default.removeItem(at: config)
        let store = makeStore()
        store.load()
        XCTAssertFalse(try store.reset())
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
    }

    func testResetSaysItReset() throws {
        let store = makeStore()
        store.load()
        XCTAssertTrue(try store.reset())
    }

    func testAPendingWriteNeverOverwritesAFileThatTurnedInvalid() throws {
        try writeFile(oneWidget)
        let store = makeStore()
        store.load()
        let good = store.board
        store.update { $0.widgets[0].frame.x = 104 }
        let broken = "format: 1\nsurface: home\nwidgets: [oops\n"
        try writeFile(broken)
        timer.fire()
        XCTAssertEqual(try readFile(), broken)
        guard case .invalid = store.status else { return XCTFail("not invalid") }
        XCTAssertEqual(store.board, good)
    }

    func testADeletedFileIsRecreatedWithTheDefaultBoard() throws {
        try writeFile(oneWidget)
        let store = makeStore()
        store.load()
        try FileManager.default.removeItem(at: fileURL)
        store.load()
        XCTAssertEqual(store.board, DefaultBoard.make(usage: []))
        XCTAssertEqual(try readFile(), BoardCodec.encode(DefaultBoard.make(usage: [])))
    }

    func testAFileForAnotherSurfaceIsInvalidHere() throws {
        try writeFile("format: 1\nsurface: sidebar\nwidgets: []\n")
        let store = makeStore()
        store.load()
        XCTAssertEqual(store.status, .invalid(BoardProblem(
            line: nil, message: "this file is for the home area but says surface: sidebar")))
    }

    private var sidebarURL: URL { BoardFiles.url(configDirectory: config.path, surface: "sidebar") }

    private func makeStackStore(surface: String = "sidebar") -> StackBoardStore {
        StackBoardStore(
            fileURL: BoardFiles.url(configDirectory: config.path, surface: surface), surface: surface, timer: timer,
            makeDefault: { DefaultStackBoard.make(surface: surface) })
    }

    func testEachSurfaceHasItsOwnFile() {
        XCTAssertEqual(BoardFiles.url(configDirectory: "/c", surface: "context-sidebar").path, "/c/boards/context-sidebar.yml")
        XCTAssertEqual(BoardStore.homeFileURL(configDirectory: "/c").path, "/c/boards/home.yml")
        XCTAssertEqual(BoardStore.writeDelay, 0.3)
        XCTAssertEqual(StackBoardStore.writeDelay, 0.3)
    }

    func testAMissingStackFileGetsTheDefaultStack() throws {
        let store = makeStackStore()
        store.load()
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(store.board, DefaultStackBoard.make(surface: "sidebar"))
        XCTAssertEqual(
            try String(contentsOf: sidebarURL, encoding: .utf8),
            "format: 1\nsurface: sidebar\nwidgets:\n  - id: workspaces\n    type: devmachine-app/workspaces\n    size: auto\n")
    }

    func testAStackFileForAnotherSurfaceIsInvalid() throws {
        try FileManager.default.createDirectory(at: sidebarURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("format: 1\nsurface: context-sidebar\nwidgets: []\n".utf8).write(to: sidebarURL)
        let store = makeStackStore()
        store.load()
        XCTAssertEqual(store.status, .invalid(BoardProblem(
            line: nil, message: "this file is for the sidebar area but says surface: context-sidebar")))
        XCTAssertNil(store.board)
    }

    func testAStackEditWaitsThenWritesAndDiskWins() throws {
        let store = makeStackStore(surface: "context-sidebar")
        store.load()
        store.update { $0.moveUp("links") }
        XCTAssertEqual(timer.delay, 0.3)
        timer.fire()
        let written = try BoardCodec.decodeStack(
            String(contentsOf: BoardFiles.url(configDirectory: config.path, surface: "context-sidebar"), encoding: .utf8))
        XCTAssertEqual(written.entries.suffix(2).map(\.id), ["links", "pull-requests"])

        store.update { $0.remove("todo") }
        try Data("format: 1\nsurface: context-sidebar\nwidgets: []\n".utf8)
            .write(to: BoardFiles.url(configDirectory: config.path, surface: "context-sidebar"), options: .atomic)
        timer.fire()
        XCTAssertEqual(store.board?.entries, [])
    }

    func testAStackResetKeepsABackup() throws {
        let store = makeStackStore()
        store.load()
        store.update { $0.remove("workspaces") }
        timer.fire()
        XCTAssertTrue(try store.reset())
        XCTAssertEqual(store.board, DefaultStackBoard.make(surface: "sidebar"))
        XCTAssertEqual(
            try String(contentsOf: store.backupURL, encoding: .utf8), "format: 1\nsurface: sidebar\nwidgets: []\n")
    }
}
