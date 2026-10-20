import Foundation

/// The app's log file: one line per event, written on a queue of its own so
/// the caller never waits, redacted before it is written, rotated at
/// `maxBytes` keeping `app.log.1` to `.3`. A write that fails is dropped:
/// a full disk or a missing folder never reaches the app.
public final class AppLogger: @unchecked Sendable {
    public enum Level: Int, Comparable, Sendable {
        case debug, info, warning, error

        var label: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO "
            case .warning: return "WARN "
            case .error: return "ERROR"
            }
        }

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public static let fileName = "app.log"
    public static let defaultMaxBytes = 5 * 1024 * 1024
    public static let keptFiles = 3

    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    private let maxBytes: Int
    private let queue = DispatchQueue(label: "devmachine.app-log", qos: .utility)
    private let lock = NSLock()
    private var minimumLevel: Level = .info
    private var recentLines: [String: Date] = [:]
    /// A line already written this recently is left out: a widget or a poll
    /// that fails the same way every few seconds says it once.
    private let repeatWindow: TimeInterval
    private var failingReads: [String: String] = [:]

    public init(directory: URL, maxBytes: Int = AppLogger.defaultMaxBytes, repeatWindow: TimeInterval = 300) {
        self.directory = directory
        self.maxBytes = maxBytes
        self.repeatWindow = repeatWindow
    }

    /// `.debug` while Settings → Debug logging is on: every poll is written.
    public var level: Level {
        get { lock.withLock { minimumLevel } }
        set { lock.withLock { minimumLevel = newValue } }
    }

    public func debug(_ category: String, _ message: @autoclosure () -> String) { log(.debug, category, message()) }
    public func info(_ category: String, _ message: @autoclosure () -> String) { log(.info, category, message()) }
    public func warning(_ category: String, _ message: @autoclosure () -> String) { log(.warning, category, message()) }
    public func error(_ category: String, _ message: @autoclosure () -> String) { log(.error, category, message()) }

    public func log(_ level: Level, _ category: String, _ message: @autoclosure () -> String) {
        guard level >= self.level else { return }
        let text = LogRedactor.redact(message())
        let now = Date()
        let key = category + "\u{0}" + text
        let repeated = lock.withLock {
            if let seen = recentLines[key], now.timeIntervalSince(seen) < repeatWindow { return true }
            if recentLines.count > 500 { recentLines = recentLines.filter { now.timeIntervalSince($0.value) < repeatWindow } }
            recentLines[key] = now
            return false
        }
        guard !repeated else { return }
        let line = Self.line(date: now, level: level, category: category, message: text)
        queue.async { [self] in append(line) }
    }

    /// Waits for every line handed over so far to be written.
    public func flush() {
        queue.sync {}
    }

    /// One CLI run. A read the app repeats on a timer is written only when it
    /// starts failing, fails differently, or works again; every run of it
    /// only in debug.
    public func cliCall(_ call: CLICall) {
        guard call.isPolledRead else {
            log(call.succeeded ? .info : .error, "cli", call.message)
            return
        }
        let key = call.commandLine
        let failure = call.succeeded ? nil : call.failureSummary
        let previous = lock.withLock {
            defer { failingReads[key] = failure }
            return failingReads[key]
        }
        if let failure, failure != previous {
            log(.error, "cli", call.message)
        } else if failure == nil, previous != nil {
            log(.info, "cli", call.message + " (works again)")
        } else {
            log(.debug, "cli", call.message)
        }
    }

    public static func line(date: Date, level: Level, category: String, message: String) -> String {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false)
        let first = lines.first.map(String.init) ?? ""
        let rest = lines.dropFirst().map { "    | " + $0 }
        return ([timestamp(date) + " " + level.label + " [" + category + "] " + first] + rest)
            .joined(separator: "\n") + "\n"
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func append(_ line: String) {
        let data = Data(line.utf8)
        let manager = FileManager.default
        do {
            try manager.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let path = fileURL.path
            let size = (try? manager.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            if size > 0, size + data.count > maxBytes { rotate() }
            guard let handle = FileHandle(forWritingAtPath: path) else {
                manager.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600])
                return
            }
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private func rotate() {
        let manager = FileManager.default
        func url(_ index: Int) -> URL {
            index == 0 ? fileURL : directory.appendingPathComponent("\(Self.fileName).\(index)")
        }
        try? manager.removeItem(at: url(Self.keptFiles))
        for index in stride(from: Self.keptFiles - 1, through: 0, by: -1) {
            try? manager.moveItem(at: url(index), to: url(index + 1))
        }
    }
}

/// One finished `devmachine` run, as the log writes it.
public struct CLICall: Equatable, Sendable {
    public static let stderrTailLines = 20

    public var arguments: [String]
    public var exitCode: Int32?
    public var duration: TimeInterval
    public var stderr: String
    public var launchError: String?
    public var hadInput: Bool

    public init(
        arguments: [String], exitCode: Int32?, duration: TimeInterval, stderr: String,
        launchError: String? = nil, hadInput: Bool = false
    ) {
        self.arguments = arguments
        self.exitCode = exitCode
        self.duration = duration
        self.stderr = stderr
        self.launchError = launchError
        self.hadInput = hadInput
    }

    public var succeeded: Bool { launchError == nil && exitCode == 0 }
    public var isPolledRead: Bool { Self.isPolledRead(arguments) }

    var commandLine: String {
        (["devmachine"] + LogRedactor.redact(arguments: arguments)).joined(separator: " ")
            + (hadInput ? " (stdin)" : "")
    }

    var failureSummary: String {
        if let launchError { return "did not start: " + launchError }
        return "exit \(exitCode.map(String.init) ?? "?")"
    }

    var message: String {
        let seconds = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), duration)
        if let launchError { return "\(commandLine): did not start: \(launchError)" }
        let head = "\(commandLine): exit \(exitCode.map(String.init) ?? "?") in \(seconds)s"
        guard !succeeded else { return head }
        let tail = stderr.split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(Self.stderrTailLines).map(String.init)
        return ([head] + tail).joined(separator: "\n")
    }

    private static let globalFlagsWithValue: Set<String> = ["--format", "--machine", "--workspace", "--config"]
    private static let polledVerbs: Set<String> = ["sessions", "version", "aliases", "context", "observed", "run", "doctor"]
    private static let polledSubcommands: [String: Set<String>] = [
        "config": ["show", "path"],
        "workspaces": ["list"],
        "machines": ["list", "observed", "addresses", "credentials"],
        "machine": ["doctor", "observed"],
        "packages": ["list", "outdated"],
        "widgets": ["list"],
        "expose": ["list"],
        "dns": ["list", "providers"],
        "scheduled": ["list", "runs", "log", "show"],
        "chat": ["list", "show"],
        "hostkey": ["check"],
        "share": ["list"],
        "logs": ["path"],
    ]

    /// The commands the app repeats on a timer or on every screen it opens:
    /// read-only, so their success says nothing new.
    public static func isPolledRead(_ arguments: [String]) -> Bool {
        var words: [String] = []
        var skipNext = false
        for argument in arguments {
            if skipNext { skipNext = false; continue }
            if globalFlagsWithValue.contains(argument) { skipNext = true; continue }
            if argument.hasPrefix("-") { continue }
            words.append(argument)
            if words.count == 2 { break }
        }
        guard let verb = words.first else { return false }
        if polledVerbs.contains(verb) { return true }
        guard words.count > 1 else { return false }
        return polledSubcommands[verb]?.contains(words[1]) == true
    }
}
