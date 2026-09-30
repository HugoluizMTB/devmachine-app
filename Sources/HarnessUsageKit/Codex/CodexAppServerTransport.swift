import Foundation
import Darwin

public protocol CodexRPCTransport: Sendable {
    func accountSnapshot() throws -> CodexAccountSnapshot
}

public enum CodexTransportError: Error, Equatable, LocalizedError {
    case executableUnavailable
    case processFailed(status: Int32, stderr: String)
    case timedOut
    case malformedResponse
    case rpcError(code: Int, message: String)
    case missingResponse(id: Int)

    public var errorDescription: String? {
        switch self {
        case .executableUnavailable: "Codex CLI is unavailable"
        case let .processFailed(_, stderr): stderr.isEmpty ? "Codex app-server failed" : stderr
        case .timedOut: "Codex account usage timed out"
        case .malformedResponse: "Codex returned malformed account usage"
        case let .rpcError(_, message): message
        case let .missingResponse(id): "Codex omitted response \(id)"
        }
    }
}

protocol CodexRPCSession: AnyObject {
    func send(_ line: String) throws
    func readLine(until deadline: Date) throws -> String?
    func finish(until deadline: Date) throws
    func cancel()
}

public struct CodexAppServerTransport: CodexRPCTransport, @unchecked Sendable {
    typealias SessionFactory = () throws -> any CodexRPCSession

    private let timeout: TimeInterval
    private let makeSession: SessionFactory

    public init(executableURL: URL, timeout: TimeInterval = 15) {
        self.init(resolveExecutable: { executableURL }, timeout: timeout)
    }

    /// Looks the CLI up on every read, so a Codex installed, moved or
    /// removed after launch is picked up without restarting the app.
    public init(resolveExecutable: @escaping @Sendable () -> URL?, timeout: TimeInterval = 15) {
        self.timeout = timeout
        makeSession = {
            guard let executableURL = resolveExecutable() else {
                throw CodexTransportError.executableUnavailable
            }
            return try ProcessRPCSession(executableURL: executableURL)
        }
    }

    init(timeout: TimeInterval, sessionFactory: @escaping SessionFactory) {
        self.timeout = timeout
        makeSession = sessionFactory
    }

    public func accountSnapshot() throws -> CodexAccountSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        let session = try makeSession()
        do {
            try session.send(Self.request(
                id: 1, method: "initialize",
                params: [
                    "clientInfo": ["name": "devmachine-app", "version": "1"],
                    "capabilities": ["experimentalApi": true]
                ]))
            let _: InitializeResponse = try Self.readResponse(id: 1, from: session, until: deadline)

            try session.send(Self.notification(method: "initialized", params: [:]))
            try session.send(Self.request(id: 2, method: "account/rateLimits/read", params: NSNull()))
            try session.send(Self.request(id: 3, method: "account/usage/read", params: NSNull()))

            var rateLimits: CodexRateLimitsResponse?
            var usage: CodexUsageResponse?
            while rateLimits == nil || usage == nil {
                guard let line = try session.readLine(until: deadline) else {
                    throw CodexTransportError.missingResponse(id: rateLimits == nil ? 2 : 3)
                }
                guard let envelope = try Self.envelope(line) else { continue }
                switch envelope.id {
                case 2: rateLimits = try Self.decode(envelope)
                case 3: usage = try Self.decode(envelope)
                default: continue
                }
            }
            try session.finish(until: deadline)
            return CodexAccountSnapshot(rateLimits: rateLimits!, usage: usage!)
        } catch {
            session.cancel()
            throw error
        }
    }

    private struct InitializeResponse: Decodable {}
    private struct Envelope { let id: Int; let object: [String: Any] }

    private static func request(id: Int, method: String, params: Any) throws -> String {
        try json(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
    }

    private static func notification(method: String, params: Any) throws -> String {
        try json(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private static func json(_ value: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let string = String(data: try JSONSerialization.data(
                withJSONObject: value, options: [.sortedKeys]), encoding: .utf8) else {
            throw CodexTransportError.malformedResponse
        }
        return string
    }

    private static func envelope(_ line: String) throws -> Envelope? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexTransportError.malformedResponse
        }
        guard let id = (object["id"] as? NSNumber)?.intValue else { return nil }
        return Envelope(id: id, object: object)
    }

    private static func readResponse<T: Decodable>(
        id: Int, from session: any CodexRPCSession, until deadline: Date
    ) throws -> T {
        while let line = try session.readLine(until: deadline) {
            guard let value = try envelope(line), value.id == id else { continue }
            return try decode(value)
        }
        throw CodexTransportError.missingResponse(id: id)
    }

    private static func decode<T: Decodable>(_ envelope: Envelope) throws -> T {
        if let error = envelope.object["error"] as? [String: Any] {
            throw CodexTransportError.rpcError(
                code: (error["code"] as? NSNumber)?.intValue ?? -1,
                message: error["message"] as? String ?? "Codex RPC error")
        }
        guard let result = envelope.object["result"], JSONSerialization.isValidJSONObject(result),
              let value = try? JSONDecoder().decode(
                T.self, from: JSONSerialization.data(withJSONObject: result)) else {
            throw CodexTransportError.malformedResponse
        }
        return value
    }
}

final class ProcessRPCSession: CodexRPCSession, @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let condition = NSCondition()
    private var lines: [String] = []
    private var stdoutBuffer = Data()
    private var stderrData = Data()
    private var stdoutEnded = false
    private var terminated = false

    init(executableURL: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CodexTransportError.executableUnavailable
        }
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executableURL
        process.environment = Self.environment(
            for: executableURL, inherited: ProcessInfo.processInfo.environment)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { [weak self] _ in self?.markTerminated() }
        try process.run()
        drain(output.fileHandleForReading, isError: false)
        drain(errors.fileHandleForReading, isError: true)
    }

    /// An app opened from Finder gets launchd's short PATH, and an npm
    /// install of Codex is a `#!/usr/bin/env node` script whose `node` sits
    /// next to it, so the CLI's own directory goes first.
    static func environment(for executableURL: URL, inherited: [String: String]) -> [String: String] {
        var environment = inherited
        let directory = executableURL.deletingLastPathComponent().path
        let path = inherited["PATH"].flatMap { $0.isEmpty ? nil : $0 }
        environment["PATH"] = path.map { "\(directory):\($0)" } ?? directory
        return environment
    }

    func send(_ line: String) throws {
        try input.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
    }

    func readLine(until deadline: Date) throws -> String? {
        condition.lock()
        defer { condition.unlock() }
        while lines.isEmpty && !stdoutEnded && !terminated {
            guard condition.wait(until: deadline) else { throw CodexTransportError.timedOut }
        }
        return lines.isEmpty ? nil : lines.removeFirst()
    }

    func finish(until deadline: Date) throws {
        try? input.fileHandleForWriting.close()
        if waitForTermination(until: deadline) { return try validateExit() }
        terminateAndReap()
        throw CodexTransportError.timedOut
    }

    func cancel() {
        try? input.fileHandleForWriting.close()
        terminateAndReap()
    }

    private func drain(_ handle: FileHandle, isError: Bool) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                self.consume(data, isError: isError)
            }
            if !isError {
                self.condition.withLock {
                    self.stdoutEnded = true
                    self.condition.broadcast()
                }
            }
        }
    }

    private func consume(_ data: Data, isError: Bool) {
        condition.withLock {
            if isError {
                if stderrData.count < 65_536 {
                    stderrData.append(data.prefix(65_536 - stderrData.count))
                }
            } else {
                stdoutBuffer.append(data)
                while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
                    lines.append(String(decoding: stdoutBuffer[..<newline], as: UTF8.self))
                    stdoutBuffer.removeSubrange(...newline)
                }
                condition.broadcast()
            }
        }
    }

    private func markTerminated() {
        condition.withLock {
            terminated = true
            condition.broadcast()
        }
    }

    private func waitForTermination(until deadline: Date) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        while !terminated {
            guard condition.wait(until: deadline) else { return false }
        }
        return true
    }

    private func terminateAndReap() {
        guard process.isRunning else { return }
        process.terminate()
        if waitForTermination(until: Date().addingTimeInterval(0.5)) { return }
        Darwin.kill(process.processIdentifier, SIGKILL)
        _ = waitForTermination(until: Date().addingTimeInterval(1))
    }

    private func validateExit() throws {
        guard process.terminationStatus == 0 else {
            let stderr = condition.withLock { String(decoding: stderrData, as: UTF8.self) }
            throw CodexTransportError.processFailed(status: process.terminationStatus, stderr: stderr)
        }
    }
}
