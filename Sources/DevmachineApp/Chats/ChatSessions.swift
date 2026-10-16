import AppKit
import Foundation
import DevmachineCore

/// A long-lived `chat session` or `chat ask --serve`: lines come out of it,
/// and each message goes in on its stdin.
protocol ChatSessionChannel: AnyObject, Sendable {
    func write(_ line: String)
    /// Closes stdin; the CLI answers with `closed` and exits.
    func close()
}

struct ChatSessionsUnavailable: Error {}

/// Runs one session process. Its output is read on one thread, in order,
/// like `ChatProcess`; `exited` comes after the last line.
final class ChatSessionProcess: ChatSessionChannel, @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let lock = NSLock()
    private var closed = false

    init(
        executable: String, arguments: [String], environment: [String: String],
        line: @escaping @Sendable (String) -> Void, exited: @escaping @Sendable (Int32) -> Void
    ) throws {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = input
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        // A write after the CLI exited must fail quietly, not end the app with SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try process.run()
        let handle = output.fileHandleForReading
        let process = self.process
        DispatchQueue.global(qos: .userInitiated).async {
            var buffer = Data()
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                buffer.append(data)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let text = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if !text.isEmpty { line(text) }
                }
            }
            if !buffer.isEmpty { line(String(decoding: buffer, as: UTF8.self)) }
            process.waitUntilExit()
            exited(process.terminationStatus)
        }
    }

    func write(_ line: String) {
        lock.withLock {
            guard !closed else { return }
            try? input.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
        }
    }

    func close() {
        lock.withLock {
            guard !closed else { return }
            closed = true
            try? input.fileHandleForWriting.close()
        }
    }
}

/// The sessions the store keeps: one warm for the next new chat, one per
/// open chat, one per visible Ask section.
@MainActor
final class ChatSessionPool {
    final class Live {
        let channel: any ChatSessionChannel
        let spec: ChatSessionSpec?
        let mcp: Bool
        /// The conversation it answers for; nil while it waits for a new chat.
        var key: String?
        var turn: UUID?
        /// What the turn would have run without sessions, for an older CLI.
        var fallback: [String]?
        /// Stopped turns whose `done` or `error` is still to come; their
        /// lines are dropped so they cannot end the next turn.
        var draining = 0
        var isReady = false
        /// The CLI's latest status while the session starts, before `ready`.
        var status: String?
        var hasEnded = false
        var output: [String] = []

        init(channel: any ChatSessionChannel, spec: ChatSessionSpec?, mcp: Bool) {
            self.channel = channel
            self.spec = spec
            self.mcp = mcp
        }
    }

    var warm: Live?
    var chats: [String: Live] = [:]
    var asks: [AskSessionKey: Live] = [:]
    /// Set once the CLI refused a session: it is older than sessions.
    var isUnsupported = false

    func remove(_ live: Live) {
        live.hasEnded = true
        if warm === live { warm = nil }
        chats = chats.filter { $0.value !== live }
        asks = asks.filter { $0.value !== live }
    }

    func closeAll() {
        for live in [warm].compactMap({ $0 }) + Array(chats.values) + Array(asks.values) {
            live.channel.close()
        }
    }
}

/// Lets a callback reach the session it belongs to, which exists only once
/// its process started.
final class ChatSessionRef: @unchecked Sendable {
    weak var live: ChatSessionPool.Live?
}
