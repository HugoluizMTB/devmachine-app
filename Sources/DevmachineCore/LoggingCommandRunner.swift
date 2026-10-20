import Foundation

/// Runs every command through `inner` and writes each run to `logger`
/// (`CLICall`). What goes to stdin is never logged, only that there was some.
public struct LoggingCommandRunner: CommandRunner {
    public let inner: any CommandRunner
    public let logger: AppLogger

    public init(wrapping inner: any CommandRunner, logger: AppLogger) {
        self.inner = inner
        self.logger = logger
    }

    public func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        var stdout = ""
        _ = try logged(args, hadInput: false) {
            stdout = try inner.run(executable: executable, args: args, environment: environment)
            return (stdout, "", 0)
        }
        return stdout
    }

    public func run(
        executable: String, args: [String], environment: [String: String]?, input: Data,
        onBytesWritten: (@Sendable (Int) -> Void)?
    ) throws -> String {
        var stdout = ""
        _ = try logged(args, hadInput: true, hiding: Self.secrets(in: input)) {
            stdout = try inner.run(
                executable: executable, args: args, environment: environment, input: input,
                onBytesWritten: onBytesWritten)
            return (stdout, "", 0)
        }
        return stdout
    }

    public func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        try logged(args, hadInput: false) {
            try inner.runCapturing(executable: executable, args: args, environment: environment)
        }
    }

    public func runCapturing(
        executable: String, args: [String], environment: [String: String]?, input: Data?,
        onBytesWritten: (@Sendable (Int) -> Void)?
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try logged(args, hadInput: input != nil, hiding: input.map(Self.secrets(in:)) ?? []) {
            try inner.runCapturing(
                executable: executable, args: args, environment: environment, input: input,
                onBytesWritten: onBytesWritten)
        }
    }

    public func runCapturing(
        executable: String, args: [String], environment: [String: String]?,
        onStderrLine: @escaping @Sendable (String) -> Void
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try logged(args, hadInput: false) {
            try inner.runCapturing(
                executable: executable, args: args, environment: environment, onStderrLine: onStderrLine)
        }
    }

    /// A password or a secret sent on stdin, in case the command prints it
    /// back. A big input is a file being written, not a secret.
    static func secrets(in input: Data) -> [String] {
        guard input.count <= 4096 else { return [] }
        return String(decoding: input, as: UTF8.self).split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func logged(
        _ args: [String], hadInput: Bool, hiding secrets: [String] = [],
        _ body: () throws -> (stdout: String, stderr: String, exitCode: Int32)
    ) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let start = Date()
        do {
            let result = try body()
            logger.cliCall(CLICall(
                arguments: args, exitCode: result.exitCode, duration: Date().timeIntervalSince(start),
                stderr: secrets.reduce(result.stderr) { $0.replacingOccurrences(of: $1, with: LogRedactor.mask) },
                hadInput: hadInput))
            return result
        } catch {
            logger.cliCall(CLICall(
                arguments: args, exitCode: nil, duration: Date().timeIntervalSince(start), stderr: "",
                launchError: error.localizedDescription, hadInput: hadInput))
            throw error
        }
    }
}
