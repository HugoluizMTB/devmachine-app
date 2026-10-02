import Foundation
import SwiftUI
import DevmachineCore
import HarnessUsageKit

struct HarnessDescriptor: Identifiable, Sendable {
    let id: HarnessID
    let title: String
    let shortTitle: String
    let systemImage: String
    let color: Color
    let helpText: String
}

protocol CodingHarnessAdapter: Sendable {
    var id: HarnessID { get }
    var descriptor: HarnessDescriptor { get }
    var executableName: String { get }
    var processNames: Set<String> { get }
    var startupCommand: String { get }
    var uploadStoragePolicy: UploadStoragePolicy { get }
    func usageProvider(locator: any ExecutableLocating) -> (any HarnessUsageProvider)?
}

extension CodingHarnessAdapter {
    func usageProvider(locator: any ExecutableLocating) -> (any HarnessUsageProvider)? { nil }
}

protocol ExecutableLocating: Sendable {
    func executable(named name: String) -> URL?
}

struct SystemExecutableLocator: ExecutableLocating {
    typealias LoginShellLookup = @Sendable (String) -> String?

    private let path: String
    private let knownDirectories: [URL]
    private let loginShellLookup: LoginShellLookup?

    init(
        path: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        knownDirectories: [URL] = SystemExecutableLocator.defaultKnownDirectories,
        loginShellLookup: LoginShellLookup? = SystemExecutableLocator.loginShellCommandPath
    ) {
        self.path = path
        self.knownDirectories = knownDirectories
        self.loginShellLookup = loginShellLookup
    }

    var searchDirectories: [URL] {
        let inheritedDirectories = path.split(separator: ":", omittingEmptySubsequences: false).map {
            URL(fileURLWithPath: $0.isEmpty ? "." : String($0))
        }
        var seen = Set<String>()
        return (inheritedDirectories + knownDirectories).filter { directory in
            seen.insert(directory.standardizedFileURL.path).inserted
        }
    }

    func executable(named name: String) -> URL? {
        guard !name.isEmpty, !name.contains("/") else { return nil }

        for directory in searchDirectories {
            if let resolved = Self.runnableTarget(of: directory.appendingPathComponent(name)) {
                return resolved
            }
        }
        return fromLoginShell(named: name)
    }

    /// An app opened from Finder does not see the PATH a version manager
    /// such as mise, asdf or nvm sets up in the login shell. The shell's own
    /// path is kept unresolved: its directory also holds the runtime (`node`)
    /// an npm-installed CLI needs.
    private func fromLoginShell(named name: String) -> URL? {
        guard let loginShellLookup,
              let path = loginShellLookup(name).flatMap(Self.commandPath(fromShellOutput:)) else { return nil }
        let candidate = URL(fileURLWithPath: path)
        return Self.runnableTarget(of: candidate) == nil ? nil : candidate
    }

    static func commandPath(fromShellOutput output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") && !$0.contains(" ") }
    }

    static let loginShellCommandPath: LoginShellLookup = { name in
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        return try? ProcessRunner().run(
            executable: shell, args: ["-lic", "command -v \(name)"], environment: nil)
    }

    private static func runnableTarget(of candidate: URL) -> URL? {
        let resolved = candidate.resolvingSymlinksInPath()
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: resolved.path),
              let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true else {
            return nil
        }
        return resolved
    }

    private static var defaultKnownDirectories: [URL] {
        [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".opencode/bin"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".kimi-code/bin"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin")
        ]
    }
}

struct ClaudeHarnessAdapter: CodingHarnessAdapter {
    let id = HarnessID.claude
    let descriptor = HarnessDescriptor(
        id: .claude,
        title: "Claude Code",
        shortTitle: "Claude",
        systemImage: "circle.fill",
        color: .orange,
        helpText: "Claude Code is running in this session"
    )
    let executableName = "claude"
    let processNames: Set<String> = ["claude"]
    let startupCommand = "claude"
    let uploadStoragePolicy = UploadStoragePolicy(directory: ".claude/image-cache/devmachine-app")

    func usageProvider(locator: any ExecutableLocating) -> (any HarnessUsageProvider)? {
        let config = ClaudeUsageConfig(claudePathOverride: locator.executable(named: executableName)?.path)
        return ClaudeUsageProvider(
            provider: DefaultUsageProvider(config: config),
            statsPollSeconds: config.statsPollSeconds)
    }
}

struct CodexHarnessAdapter: CodingHarnessAdapter {
    let id = HarnessID.codex
    let descriptor = HarnessDescriptor(
        id: .codex,
        title: "OpenAI Codex",
        shortTitle: "Codex",
        systemImage: "circle.fill",
        color: .green,
        helpText: "OpenAI Codex is running in this session"
    )
    let executableName = "codex"
    let processNames: Set<String> = ["codex"]
    let startupCommand = "codex"
    let uploadStoragePolicy = UploadStoragePolicy.appManaged

    func usageProvider(locator: any ExecutableLocating) -> (any HarnessUsageProvider)? {
        let executableName = executableName
        return CodexUsageProvider(transport: CodexAppServerTransport(
            resolveExecutable: { locator.executable(named: executableName) }))
    }
}

/// A harness the app launches, recognizes and reads context for, with no
/// usage provider and no image folder of its own.
struct BasicHarnessAdapter: CodingHarnessAdapter {
    let descriptor: HarnessDescriptor
    let executableName: String
    let processNames: Set<String>
    let uploadStoragePolicy = UploadStoragePolicy.appManaged

    var id: HarnessID { descriptor.id }
    var startupCommand: String { executableName }

    init(id: HarnessID, title: String, shortTitle: String, color: Color, executableName: String, processNames: Set<String>) {
        descriptor = HarnessDescriptor(
            id: id, title: title, shortTitle: shortTitle, systemImage: "circle.fill", color: color,
            helpText: "\(title) is running in this session")
        self.executableName = executableName
        self.processNames = processNames
    }

    static let pi = BasicHarnessAdapter(
        id: .pi, title: "Pi", shortTitle: "Pi", color: .purple, executableName: "pi", processNames: ["pi"])
    static let antigravity = BasicHarnessAdapter(
        id: .antigravity, title: "Antigravity CLI", shortTitle: "Antigravity", color: .blue,
        executableName: "agy", processNames: ["agy"])
    /// The npm launcher is `node`; the program it starts is the native
    /// `opencode`, which is what the process list shows.
    static let opencode = BasicHarnessAdapter(
        id: .opencode, title: "opencode", shortTitle: "opencode", color: .mint,
        executableName: "opencode", processNames: ["opencode"])
    /// Kimi Code renames its process to `kimi-code`; a native build may
    /// still show the binary's own name.
    static let kimi = BasicHarnessAdapter(
        id: .kimi, title: "Kimi Code", shortTitle: "Kimi", color: .indigo,
        executableName: "kimi", processNames: ["kimi", "kimi-code"])
    /// The npm `cline` is a `node` script that starts the native binary,
    /// hard-linked as `.cline`; only that child names the harness.
    static let cline = BasicHarnessAdapter(
        id: .cline, title: "Cline", shortTitle: "Cline", color: .teal,
        executableName: "cline", processNames: ["cline", ".cline"])
}
