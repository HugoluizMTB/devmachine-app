import Foundation

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

public struct CodexAppServerTransport: CodexRPCTransport, @unchecked Sendable {
    typealias Exchange = ([String], TimeInterval) throws -> [String]

    private let timeout: TimeInterval
    private let exchange: Exchange

    public init(executableURL: URL, timeout: TimeInterval = 15) {
        self.timeout = timeout
        exchange = { requests, timeout in
            try Self.run(executableURL: executableURL, requests: requests, timeout: timeout)
        }
    }

    init(timeout: TimeInterval, exchange: @escaping Exchange) {
        self.timeout = timeout
        self.exchange = exchange
    }

    public func accountSnapshot() throws -> CodexAccountSnapshot {
        let requests = try Self.requests()
        let lines = try exchange(requests, timeout)
        let rateLimits: CodexRateLimitsResponse = try Self.response(id: 2, lines: lines)
        let usage: CodexUsageResponse = try Self.response(id: 3, lines: lines)
        return CodexAccountSnapshot(rateLimits: rateLimits, usage: usage)
    }

    private static func requests() throws -> [String] {
        let values: [[String: Any]] = [
            [
                "jsonrpc": "2.0", "id": 1, "method": "initialize",
                "params": [
                    "clientInfo": ["name": "devmachine-app", "version": "1"],
                    "capabilities": ["experimentalApi": true]
                ]
            ],
            ["jsonrpc": "2.0", "method": "initialized", "params": [:]],
            ["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read", "params": NSNull()],
            ["jsonrpc": "2.0", "id": 3, "method": "account/usage/read", "params": NSNull()]
        ]
        return try values.map {
            let data = try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys])
            guard let value = String(data: data, encoding: .utf8) else {
                throw CodexTransportError.malformedResponse
            }
            return value
        }
    }

    private static func response<T: Decodable>(id: Int, lines: [String]) throws -> T {
        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CodexTransportError.malformedResponse
            }
            guard (object["id"] as? NSNumber)?.intValue == id else { continue }
            if let error = object["error"] as? [String: Any] {
                throw CodexTransportError.rpcError(
                    code: (error["code"] as? NSNumber)?.intValue ?? -1,
                    message: error["message"] as? String ?? "Codex RPC error")
            }
            guard let result = object["result"],
                  JSONSerialization.isValidJSONObject(result),
                  let decoded = try? JSONDecoder().decode(
                    T.self, from: JSONSerialization.data(withJSONObject: result)) else {
                throw CodexTransportError.malformedResponse
            }
            return decoded
        }
        throw CodexTransportError.missingResponse(id: id)
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: (Data, Data, Int32)?
        func set(_ value: (Data, Data, Int32)) { lock.withLock { self.value = value } }
        func get() -> (Data, Data, Int32)? { lock.withLock { value } }
    }

    private static func run(
        executableURL: URL, requests: [String], timeout: TimeInterval
    ) throws -> [String] {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CodexTransportError.executableUnavailable
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()

        let payload = requests.joined(separator: "\n") + "\n"
        input.fileHandleForWriting.write(Data(payload.utf8))
        try? input.fileHandleForWriting.close()

        let box = ResultBox()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            let stdout = output.fileHandleForReading.readDataToEndOfFile()
            let stderr = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            box.set((stdout, stderr, process.terminationStatus))
            finished.signal()
        }

        guard finished.wait(timeout: .now() + timeout) == .success else {
            if process.isRunning { process.terminate() }
            _ = finished.wait(timeout: .now() + 1)
            throw CodexTransportError.timedOut
        }
        guard let (stdout, stderr, status) = box.get() else {
            throw CodexTransportError.malformedResponse
        }
        guard status == 0 || !stdout.isEmpty else {
            throw CodexTransportError.processFailed(
                status: status,
                stderr: String(data: stderr, encoding: .utf8) ?? "")
        }
        return String(data: stdout, encoding: .utf8)?
            .split(whereSeparator: \.isNewline).map(String.init) ?? []
    }
}
