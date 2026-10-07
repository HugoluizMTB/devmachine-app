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

/// One board file. What is on disk always wins: a change made elsewhere
/// replaces a write still waiting here, and an invalid file is never
/// written over, so a person fixing it by hand loses nothing.
@MainActor
public final class BoardStore: ObservableObject {
    public enum Status: Equatable, Sendable {
        case loading
        case ready
        case invalid(BoardProblem)
    }

    public static let writeDelay: TimeInterval = 0.3
    public static let fileName = "home.yml"

    @Published public private(set) var board: Board?
    @Published public private(set) var status: Status = .loading
    @Published public private(set) var writeError: String?

    public let fileURL: URL
    public let surface: String
    private let makeDefault: @MainActor () -> Board
    private let timer: any BoardWriteTimer
    private var diskData: Data?
    private var pending = false

    public init(
        fileURL: URL, surface: String = DefaultBoard.surface, timer: (any BoardWriteTimer)? = nil,
        makeDefault: @escaping @MainActor () -> Board
    ) {
        self.fileURL = fileURL
        self.surface = surface
        self.timer = timer ?? DispatchBoardWriteTimer()
        self.makeDefault = makeDefault
    }

    public static func homeFileURL(configDirectory: String) -> URL {
        URL(fileURLWithPath: configDirectory).appendingPathComponent("boards").appendingPathComponent(fileName)
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
            let decoded = try BoardCodec.decode(String(decoding: data, as: UTF8.self))
            guard decoded.surface == surface else {
                throw BoardProblem(
                    line: nil, message: "this file is for the \(surface) area but says surface: \(decoded.surface)")
            }
            if board != decoded { board = decoded }
            status = .ready
        } catch let problem as BoardProblem {
            status = .invalid(problem)
        } catch {
            status = .invalid(BoardProblem(line: nil, message: error.localizedDescription))
        }
    }

    public func update(_ change: (inout Board) -> Void) {
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
        let data = Data(BoardCodec.encode(board).utf8)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            diskData = data
            pending = false
            writeError = nil
        } catch {
            writeError = error.localizedDescription
        }
    }

    public func reset() throws {
        timer.cancel()
        if let existing = try? Data(contentsOf: fileURL) {
            try existing.write(to: backupURL, options: .atomic)
        }
        let fresh = makeDefault()
        let data = Data(BoardCodec.encode(fresh).utf8)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        diskData = data
        pending = false
        writeError = nil
        board = fresh
        status = .ready
    }

    private func useDefault() {
        diskData = nil
        board = makeDefault()
        status = .ready
        pending = true
        flush()
    }
}
