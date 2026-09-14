import Foundation
import AppKit
import DevmachineCore

@MainActor
final class FilesStore: ObservableObject {
    @Published var alias: String?
    @Published var path: String = "."
    @Published var entries: [FileEntry] = []
    @Published var isLoading = false
    @Published var errorText: String?

    private let service: FileService
    private let runner: CommandRunner
    private nonisolated(unsafe) var refreshTask: Task<Void, Never>?

    init(service: FileService = FileService(), runner: CommandRunner = ProcessRunner()) {
        self.service = service
        self.runner = runner
    }

    deinit {
        refreshTask?.cancel()
    }

    func open(alias: String) {
        self.alias = alias
        path = "."
        entries = []
        errorText = nil
        refresh()
    }

    func refresh() {
        guard let alias else { return }
        let path = self.path
        refreshTask?.cancel()
        isLoading = true
        errorText = nil
        let service = self.service

        refreshTask = Task {
            do {
                let result = try await Task.detached { try service.list(alias: alias, path: path) }.value
                guard !Task.isCancelled else { return }
                self.entries = result
                self.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func cd(_ entry: FileEntry) {
        guard entry.isDir else { return }
        if path == "." {
            path = entry.name
        } else {
            path = path.hasSuffix("/") ? path + entry.name : path + "/" + entry.name
        }
        refresh()
    }

    func up() {
        guard path != "." else { return }
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        if let slash = trimmed.lastIndex(of: "/") {
            path = String(trimmed[trimmed.startIndex..<slash])
        } else {
            path = "."
        }
        refresh()
    }

    func download(_ entry: FileEntry) {
        guard let alias else { return }
        guard !entry.isDir else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = entry.name
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let remotePath = joinedPath(entry.name)
        let args = service.downloadArgs(alias: alias, remotePath: remotePath, localPath: url.path)
        runSCP(args: args)
    }

    func uploadFiles() {
        guard let alias else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard !urls.isEmpty else { return }

        let currentPath = path
        let service = self.service
        let runner = self.runner

        Task {
            var failedNames: [String] = []
            for url in urls {
                let remotePath = self.joinedPath(url.lastPathComponent, base: currentPath)
                let args = service.uploadArgs(alias: alias, localPath: url.path, remotePath: remotePath)
                do {
                    _ = try await Task.detached { try runner.run(executable: "/usr/bin/scp", args: args, environment: nil) }.value
                } catch {
                    failedNames.append(url.lastPathComponent)
                }
            }
            self.refresh()
            // refresh() clears errorText synchronously, so the upload failure
            // message must be applied after its async list fetch completes.
            await self.refreshTask?.value
            if !failedNames.isEmpty {
                self.errorText = "Failed to upload: \(failedNames.joined(separator: ", "))"
            }
        }
    }

    private func runSCP(args: [String]) {
        let runner = self.runner
        Task {
            do {
                _ = try await Task.detached { try runner.run(executable: "/usr/bin/scp", args: args, environment: nil) }.value
            } catch {
                self.errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func joinedPath(_ name: String, base: String? = nil) -> String {
        let base = base ?? path
        if base == "." {
            return name
        }
        return base.hasSuffix("/") ? base + name : base + "/" + name
    }
}
