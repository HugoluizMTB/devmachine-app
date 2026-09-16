import Foundation
import Combine
import DevmachineCore

/// The file list behind the search field. The listing is fetched once per root
/// and then filtered here, so typing costs nothing over the network.
@MainActor
final class FileSearchStore: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    @Published private(set) var hits: [FileSearch.Hit] = []
    @Published var query = "" {
        didSet { rank() }
    }

    private let host: HostRunner
    private var paths: [String] = []
    private var loaded: (key: String, root: String)?
    @Published private(set) var root = ""

    init(host: HostRunner = HostRunner()) {
        self.host = host
    }

    var fileCount: Int { paths.count }

    /// Resolves the session's repository and lists it. Called when the palette
    /// opens, so the field is ready before the first keystroke lands.
    func open(_ target: CommandTarget) {
        isLoading = true
        errorText = nil
        let host = self.host
        Task.detached {
            let resolved = (try? host.runCapturing(
                target, RemoteCommands.fileTreeRootBody).stdout)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                guard let resolved, !resolved.isEmpty else {
                    self.isLoading = false
                    self.errorText = "Could not find the session's directory"
                    return
                }
                self.root = resolved
                self.load(target, root: resolved)
            }
        }
    }

    /// Loads the list unless this root is already the one in memory. Reopening
    /// the field on the same session is then instant.
    func load(_ target: CommandTarget, root: String, force: Bool = false) {
        if !force, let loaded, loaded.key == target.key, loaded.root == root {
            isLoading = false
            return
        }
        isLoading = true
        errorText = nil
        let command = RemoteCommands.listFiles(root: root)
        let host = self.host
        let key = target.key
        Task.detached {
            let output = try? host.runCapturingAnywhere(target, command).stdout
            await MainActor.run {
                self.isLoading = false
                guard let output else {
                    self.errorText = "Could not list files"
                    return
                }
                self.paths = output.split(separator: "\n").map(String.init)
                self.loaded = (key, root)
                self.rank()
            }
        }
    }

    func clear() {
        query = ""
        hits = []
    }

    /// Fills the list the way a finished load would, for tests that must not
    /// reach a host.
    func acceptForTesting(_ paths: [String]) {
        self.paths = paths
        rank()
    }

    private func rank() {
        hits = FileSearch.rank(paths, query: query, limit: 40)
    }
}
