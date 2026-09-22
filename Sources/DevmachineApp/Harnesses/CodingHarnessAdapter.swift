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

    init(path: String = ProcessInfo.processInfo.environment["PATH"] ?? "") {
        self.path = path
    }

    func executable(named name: String) -> URL? {
        guard !name.isEmpty, !name.contains("/") else { return nil }

        for directory in path.split(separator: ":", omittingEmptySubsequences: false) {
            let url = URL(fileURLWithPath: directory.isEmpty ? "." : String(directory))
                .appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
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
