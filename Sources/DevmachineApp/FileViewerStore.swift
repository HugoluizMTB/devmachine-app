import Foundation
import Combine
import DevmachineCore

/// Reads one file for the viewer window, from whichever side the session runs
/// on. Reading only: nothing here writes a file.
@MainActor
final class FileViewerStore: ObservableObject {
    @Published private(set) var preview: FilePreview?
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    /// Markdown starts rendered; the switch shows the source instead.
    @Published var showsSource = false

    private let host: HostRunner
    private var current: (target: CommandTarget, path: String)?

    init(host: HostRunner = HostRunner()) {
        self.host = host
    }

    var path: String? { current?.path }

    func open(_ target: CommandTarget, path: String) {
        current = (target, path)
        preview = nil
        errorText = nil
        showsSource = false
        load()
    }

    func reload() {
        guard current != nil else { return }
        load()
    }

    private func load() {
        guard let (target, path) = current else { return }
        isLoading = true
        let host = self.host
        let command = FilePreviewReader.command(path: path)
        Task.detached {
            let result = try? host.runCapturingAnywhere(target, command)
            let parsed = result.flatMap { FilePreviewReader.parse($0.stdout, path: path) }
            let message = parsed == nil ? Self.failure(result) : nil
            await MainActor.run {
                guard let cur = self.current, cur.target == target, cur.path == path else { return }
                self.isLoading = false
                self.preview = parsed
                self.errorText = message
            }
        }
    }

    nonisolated private static func failure(
        _ result: (stdout: String, stderr: String, exitCode: Int32)?
    ) -> String {
        guard let result else { return "Could not read the file" }
        let line = result.stderr
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line ?? "Could not read the file"
    }
}
