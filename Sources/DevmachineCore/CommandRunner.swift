import Foundation

public protocol CommandRunner: Sendable {
    func run(executable: String, args: [String], environment: [String: String]?) throws -> String
    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32)
}

public extension CommandRunner {
    // Default for conformers that don't need stderr/exit-code detail (e.g.
    // test fakes): treat it as an always-successful capture of `run`'s output.
    func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        let stdout = try run(executable: executable, args: args, environment: environment)
        return (stdout, "", 0)
    }
}

public struct ProcessRunner: CommandRunner {
    public init() {}

    // Returns stdout regardless of exit code — callers that only care about
    // output (SessionStore/ContextStore/RemoteService) treat a nonzero exit
    // with usable stdout as a normal result (e.g. `tmux list-sessions`
    // exiting 1 with no server running, which SessionStore reads as "no
    // sessions", not "workspace offline"). Only a launch failure throws.
    public func run(executable: String, args: [String], environment: [String: String]?) throws -> String {
        try runCapturing(executable: executable, args: args, environment: environment).stdout
    }

    public func runCapturing(executable: String, args: [String], environment: [String: String]?) throws
        -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()
        // Read BEFORE waiting: if the pipe buffer fills, waiting first
        // deadlocks the child (blocked writing) against us (blocked waiting).
        // Drain both pipes concurrently: reading one to EOF before the other
        // would deadlock if the child fills the second pipe's buffer while
        // blocked, since its EOF never comes until it exits.
        let errBox = DataBox()
        let errHandle = err.fileHandleForReading
        let drain = DispatchGroup()
        drain.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = errHandle.readDataToEndOfFile()
            drain.leave()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        drain.wait()
        process.waitUntilExit()

        return (
            String(data: data, encoding: .utf8) ?? "",
            String(data: errBox.data, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
