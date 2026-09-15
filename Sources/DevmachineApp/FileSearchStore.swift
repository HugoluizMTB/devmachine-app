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

    private let remote: RemoteService
    private var paths: [String] = []
    private var loaded: (alias: String, root: String)?
    @Published private(set) var root = ""

    init(remote: RemoteService = RemoteService()) {
        self.remote = remote
    }

    var fileCount: Int { paths.count }

    /// Resolves the session's repository and lists it. Called when the palette
    /// opens, so the field is ready before the first keystroke lands.
    func open(alias: String, session: String) {
        isLoading = true
        errorText = nil
        let remote = self.remote
        Task.detached {
            let resolved = (try? remote.run(
                alias: alias, args: [RemoteCommands.fileTreeRoot(session: session)]))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                guard let resolved, !resolved.isEmpty else {
                    self.isLoading = false
                    self.errorText = "Could not find the session's directory"
                    return
                }
                self.root = resolved
                self.load(alias: alias, root: resolved)
            }
        }
    }

    /// Loads the list unless this root is already the one in memory. Reopening
    /// the field on the same session is then instant.
    func load(alias: String, root: String, force: Bool = false) {
        if !force, let loaded, loaded.alias == alias, loaded.root == root {
            isLoading = false
            return
        }
        isLoading = true
        errorText = nil
        let command = RemoteCommands.listFiles(root: root)
        let remote = self.remote
        Task.detached {
            let output = try? remote.run(alias: alias, args: [command])
            await MainActor.run {
                self.isLoading = false
                guard let output else {
                    self.errorText = "Could not list files"
                    return
                }
                self.paths = output.split(separator: "\n").map(String.init)
                self.loaded = (alias, root)
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
