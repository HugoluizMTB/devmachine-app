import Foundation
import SwiftUI
import DevmachineCore

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
}

protocol ExecutableLocating: Sendable {
    func executable(named name: String) -> URL?
}

struct SystemExecutableLocator: ExecutableLocating {
    private let path: String
    private let knownDirectories: [URL]

    init(
        path: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        knownDirectories: [URL] = SystemExecutableLocator.defaultKnownDirectories
    ) {
        self.path = path
        self.knownDirectories = knownDirectories
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
            let candidate = directory.appendingPathComponent(name).resolvingSymlinksInPath()
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  FileManager.default.isExecutableFile(atPath: candidate.path),
                  let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }
            return candidate
        }
        return nil
    }

    private static var defaultKnownDirectories: [URL] {
        [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin"),
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
}
