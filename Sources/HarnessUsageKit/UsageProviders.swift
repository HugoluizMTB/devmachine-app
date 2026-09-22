import Foundation

private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

public struct ClaudeUsageConfig: Sendable {
    public var logsRoot: URL
    public var claudeJSONPath: URL
    public var claudePathOverride: String?
    public var usagePollSeconds: TimeInterval
    public var statsPollSeconds: TimeInterval

    public init(
        logsRoot: URL = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/projects"),
        claudeJSONPath: URL = URL(fileURLWithPath: NSHomeDirectory() + "/.claude.json"),
        claudePathOverride: String? = nil,
        usagePollSeconds: TimeInterval = 60,
        statsPollSeconds: TimeInterval = 300
    ) {
        self.logsRoot = logsRoot
        self.claudeJSONPath = claudeJSONPath
        self.claudePathOverride = claudePathOverride
        self.usagePollSeconds = usagePollSeconds
        self.statsPollSeconds = statsPollSeconds
    }
}

public protocol UsageProvider: Sendable {
    func fetchUsageText() throws -> String
    func readClaudeJSON() -> String?
    func computeStats() -> UsageStats
}

public enum UsageProviderError: Error, Equatable {
    case executableNotFound(String)
    case processFailed(status: Int32, stderr: String)
    case timedOut
    case decodeFailed
}

private struct UsageEnvelope: Decodable {
    let result: String
}

public struct DefaultUsageProvider: UsageProvider {
    private let config: ClaudeUsageConfig

    public init(config: ClaudeUsageConfig = .init()) {
        self.config = config
    }

    private func resolveClaudePath() -> String? {
        if let override = config.claudePathOverride {
            return override
        }
        let candidates = [
            NSHomeDirectory() + "/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        return "claude"
    }

    public func fetchUsageText() throws -> String {
        guard let claudePath = resolveClaudePath() else {
            throw UsageProviderError.executableNotFound("claude")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--safe-mode", "-p", "/usage", "--output-format", "json"]
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let didTimeOut = TimeoutFlag()
        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                didTimeOut.set()
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeoutWorkItem)

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()
        timeoutWorkItem.cancel()

        if didTimeOut.get() {
            throw UsageProviderError.timedOut
        }

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            throw UsageProviderError.processFailed(status: process.terminationStatus, stderr: stderrText)
        }

        guard let envelope = try? JSONDecoder().decode(UsageEnvelope.self, from: stdoutData) else {
            throw UsageProviderError.decodeFailed
        }

        return envelope.result
    }

    public func readClaudeJSON() -> String? {
        try? String(contentsOf: config.claudeJSONPath, encoding: .utf8)
    }

    public func computeStats() -> UsageStats {
        UsageStatsEngine.compute(logsRoot: config.logsRoot, now: Date())
    }
}
