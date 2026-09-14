import Foundation
import DevmachineCore

enum GHError: LocalizedError {
    case notFound
    case notAuthenticated
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notFound: return "GitHub CLI not found. Install it with `brew install gh`."
        case .notAuthenticated: return "Not logged in. Run `gh auth login` in a terminal."
        case .failed(let m): return m
        }
    }
}

struct GHClient: Sendable {
    static let knownPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

    private let runner: CommandRunner
    private let resolvedPath: LockedBox<String?> = LockedBox(nil)

    init(runner: CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    func resolvePath() -> String? {
        if let cached = resolvedPath.value { return cached }
        if let known = Self.knownPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            resolvedPath.value = known
            return known
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let output = try? runner.run(executable: shell, args: ["-lic", "command -v gh"], environment: nil) else {
            return nil
        }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        resolvedPath.value = path
        return path
    }

    private func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin"
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        return env
    }

    private func run(_ args: [String]) throws -> String {
        guard let ghPath = resolvePath() else { throw GHError.notFound }
        let result: (stdout: String, stderr: String, exitCode: Int32)
        do {
            result = try runner.runCapturing(executable: ghPath, args: args, environment: environment())
        } catch {
            throw GHError.notFound
        }
        guard result.exitCode == 0 else {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = msg.lowercased()
            if lowered.contains("auth") || lowered.contains("logged in") || lowered.contains("gh auth login") {
                throw GHError.notAuthenticated
            }
            throw GHError.failed(msg.isEmpty ? "gh exited with code \(result.exitCode)" : String(msg.prefix(200)))
        }
        return result.stdout
    }

    func search(owner: String?) throws -> [SearchPR] {
        var args = ["search", "prs", "--author=@me", "--state=open", "--limit", "100",
                    "--json", "number,repository,title,isDraft"]
        if let owner, owner != allOwnersSentinel {
            args.append("--owner=\(owner)")
        }
        let output = try run(args)
        return try decodeSearchPRs(Data(output.utf8))
    }

    func detail(number: Int, repo: String) throws -> PRDetail {
        let output = try run(["pr", "view", "\(number)", "--repo", repo,
                              "--json", "number,title,state,url,isDraft,reviewDecision,headRefName,baseRefName,statusCheckRollup"])
        return try decodePRDetail(Data(output.utf8))
    }

    func login() throws -> String? {
        let output = try run(["api", "user", "--jq", ".login"])
        let login = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return login.isEmpty ? nil : login
    }

    func orgs() throws -> [String] {
        let output = try run(["api", "user/orgs", "--jq", ".[].login"])
        return output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}
