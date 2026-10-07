import Combine
import Foundation

@MainActor
public protocol BoardWriteTimer: AnyObject {
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor @Sendable () -> Void)
    func cancel()
}

@MainActor
public final class DispatchBoardWriteTimer: BoardWriteTimer {
    private var item: DispatchWorkItem?

    public init() {}

    public func schedule(after delay: TimeInterval, _ work: @escaping @MainActor @Sendable () -> Void) {
        item?.cancel()
        let next = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        item = next
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: next)
    }

    public func cancel() {
        item?.cancel()
        item = nil
    }
}

/// A board file's content: Home's canvas or a sidebar's stack, each
/// read and written by its own codec.
public protocol BoardFileDocument: Equatable, Sendable {
    var surface: String { get }
    static func decodeFile(_ text: String) throws -> Self
    func encodeFile() -> String
}

extension Board: BoardFileDocument {
    public static func decodeFile(_ text: String) throws -> Board { try BoardCodec.decode(text) }
    public func encodeFile() -> String { BoardCodec.encode(self) }
}

extension StackBoard: BoardFileDocument {
    public static func decodeFile(_ text: String) throws -> StackBoard { try BoardCodec.decodeStack(text) }
    public func encodeFile() -> String { BoardCodec.encodeStack(self) }
}

/// Lives outside the generic store so every surface shares one type.
public enum BoardStoreStatus: Equatable, Sendable {
    case loading
    case ready
    case invalid(BoardProblem)
}

/// Each surface keeps its own file under `<config>/boards/`.
public enum BoardFiles {
    public static func url(configDirectory: String, surface: String) -> URL {
        URL(fileURLWithPath: configDirectory).appendingPathComponent("boards").appendingPathComponent("\(surface).yml")
    }
}

public typealias BoardStore = BoardFileStore<Board>
public typealias StackBoardStore = BoardFileStore<StackBoard>

extension BoardFileStore where Document == Board {
    public static var fileName: String { "home.yml" }

    public static func homeFileURL(configDirectory: String) -> URL {
        BoardFiles.url(configDirectory: configDirectory, surface: DefaultBoard.surface)
    }
}

/// One board file. What is on disk always wins: a change made elsewhere
/// replaces a write still waiting here, and an invalid file is never
/// written over, so a person fixing it by hand loses nothing.
@MainActor
public final class BoardFileStore<Document: BoardFileDocument>: ObservableObject {
    public typealias Status = BoardStoreStatus

    public static var writeDelay: TimeInterval { 0.3 }

    @Published public private(set) var board: Document?
    @Published public private(set) var status: Status = .loading
    @Published public private(set) var writeError: String?

    public let fileURL: URL
    public let surface: String
    private let makeDefault: @MainActor () -> Document
    private let timer: any BoardWriteTimer
    private var diskData: Data?
    private var savedBoard: Document?
    private var pending = false

    public init(
        fileURL: URL, surface: String = DefaultBoard.surface, timer: (any BoardWriteTimer)? = nil,
        makeDefault: @escaping @MainActor () -> Document
    ) {
        self.fileURL = fileURL
        self.surface = surface
        self.timer = timer ?? DispatchBoardWriteTimer()
        self.makeDefault = makeDefault
    }

    public var backupURL: URL { fileURL.appendingPathExtension("bak") }
    public var canEdit: Bool { status == .ready && board != nil }
    private var configDirectory: URL { fileURL.deletingLastPathComponent().deletingLastPathComponent() }

    public func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            if status == .loading || diskData != nil {
                useDefault()
            } else if pending {
                flush()
            }
            return
        }
        if status != .loading, data == diskData { return }
        diskData = data
        timer.cancel()
        pending = false
        do {
            let decoded = try Document.decodeFile(String(decoding: data, as: UTF8.self))
            guard decoded.surface == surface else {
                throw BoardProblem(
                    line: nil, message: "this file is for the \(surface) area but says surface: \(decoded.surface)")
            }
            if board != decoded { board = decoded }
            savedBoard = decoded
            status = .ready
        } catch let problem as BoardProblem {
            markInvalid(problem)
        } catch {
            markInvalid(BoardProblem(line: nil, message: error.localizedDescription))
        }
    }

    private func markInvalid(_ problem: BoardProblem) {
        if let savedBoard, board != savedBoard { board = savedBoard }
        status = .invalid(problem)
    }

    public func update(_ change: (inout Document) -> Void) {
        guard canEdit, var next = board else { return }
        change(&next)
        guard next != board else { return }
        board = next
        pending = true
        timer.schedule(after: Self.writeDelay) { [weak self] in self?.flush() }
    }

    public func flush() {
        timer.cancel()
        guard pending, status == .ready, let board else { return }
        let current = try? Data(contentsOf: fileURL)
        guard current == diskData else {
            pending = false
            load()
            return
        }
        guard FileManager.default.fileExists(atPath: configDirectory.path) else { return }
        let data = Data(board.encodeFile().utf8)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            diskData = data
            savedBoard = board
            pending = false
            writeError = nil
        } catch {
            writeError = error.localizedDescription
        }
    }

    /// False when the config folder is missing: the app never creates it.
    @discardableResult
    public func reset() throws -> Bool {
        guard FileManager.default.fileExists(atPath: configDirectory.path) else { return false }
        timer.cancel()
        if let existing = try? Data(contentsOf: fileURL) {
            try existing.write(to: backupURL, options: .atomic)
        }
        let fresh = makeDefault()
        let data = Data(fresh.encodeFile().utf8)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        diskData = data
        savedBoard = fresh
        pending = false
        writeError = nil
        board = fresh
        status = .ready
        return true
    }

    private func useDefault() {
        diskData = nil
        board = makeDefault()
        savedBoard = board
        status = .ready
        pending = true
        flush()
    }
}
