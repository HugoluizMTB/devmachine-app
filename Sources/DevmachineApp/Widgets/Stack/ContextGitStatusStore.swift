import DevmachineCore
import Foundation

/// Reads `repo` and `branch` for the context sidebar, once per session and
/// folder, only while a widget on the board reads them.
@MainActor
final class ContextGitStatusStore: ObservableObject {
    @Published private(set) var status: ContextGitStatus?
    private let run: @Sendable (CommandTarget, String) throws -> String
    private var currentKey: String?

    init(run: @escaping @Sendable (CommandTarget, String) throws -> String = { target, body in
        try HostRunner().runCapturingWithFolderArgument(target, body).stdout
    }) {
        self.run = run
    }

    func refresh(_ target: CommandTarget?, cwd: String?) {
        guard let target else {
            currentKey = nil
            if status != nil { status = nil }
            return
        }
        let key = target.key + "|" + (cwd ?? "")
        guard key != currentKey else { return }
        currentKey = key
        if status != nil { status = nil }
        let run = self.run
        Task.detached {
            let parsed = ContextGitProbe.parse((try? run(target, ContextGitProbe.body)) ?? "")
            await MainActor.run {
                guard self.currentKey == key else { return }
                if self.status != parsed { self.status = parsed }
            }
        }
    }
}
