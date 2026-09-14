import AppKit
import SwiftTerm
import DevmachineCore

/// One live terminal (and one mosh/tmux client) per session for the whole app.
/// SwiftUI containers come and go — single pane, stack grid — and re-attach
/// the same view, so switching layouts never reconnects.
@MainActor
final class TerminalRegistry: NSObject {
    static let shared = TerminalRegistry()
    /// How many detached terminals (and their mosh/tmux clients) to keep around.
    static let detachedLimit = 6

    private var terminals: [TerminalKind: LocalProcessTerminalView] = [:]
    private var detachedAt: [TerminalKind: Date] = [:]

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { TerminalRegistry.shared.closeAll() }
        }
    }

    func terminal(for kind: TerminalKind) -> LocalProcessTerminalView {
        detachedAt[kind] = nil
        if let live = terminals[kind] { return live }
        let term = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        term.processDelegate = self
        start(kind, in: term)
        terminals[kind] = term
        return term
    }

    /// No SwiftUI pane shows this terminal any more. It keeps running, and the
    /// longest-detached ones are closed once too many pile up — tmux holds the
    /// session server-side, so opening it again reconnects.
    func detach(_ kind: TerminalKind) {
        guard terminals[kind] != nil else { return }
        detachedAt[kind] = Date()
        for stale in LRUEviction.keysToEvict(detachedAt: detachedAt, cap: Self.detachedLimit) {
            close(stale)
        }
    }

    func close(_ kind: TerminalKind) {
        detachedAt[kind] = nil
        guard let term = terminals.removeValue(forKey: kind) else { return }
        term.terminate()
        term.removeFromSuperview()
    }

    func close(alias: String, session: String) {
        close(.remote(alias: alias, session: session))
    }

    func closeAll() {
        for kind in Array(terminals.keys) { close(kind) }
    }

    private func start(_ kind: TerminalKind, in term: LocalProcessTerminalView) {
        switch kind {
        case let .remote(alias, session):
            // Interactive: mosh (survives roaming/drops). Tailscale only
            // (UDP on tailscale0). Falls back to ssh if mosh isn't on the Mac.
            let mosh = "/opt/homebrew/bin/mosh"
            if FileManager.default.isExecutableFile(atPath: mosh) {
                term.startProcess(
                    executable: mosh,
                    args: [alias, "--", "tmux", "new-session", "-A", "-s", session],
                    environment: RemoteCommands.terminalEnvironment()
                )
            } else {
                term.startProcess(
                    executable: "/usr/bin/ssh",
                    args: [alias, "-t", RemoteCommands.newSession(name: session)],
                    environment: RemoteCommands.terminalEnvironment()
                )
            }
        case .operador:
            let repo = SettingsStore.shared.settings?.opsRepoPath ?? NSHomeDirectory()
            term.startProcess(
                executable: "/bin/zsh",
                args: ["-i", "-l"],
                environment: RemoteCommands.terminalEnvironment(),
                execName: "-zsh",
                currentDirectory: repo
            )
        }
    }
}

extension TerminalRegistry: @preconcurrency LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    // A dead process must not be handed out again: the next mount starts a
    // fresh one.
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        if let kind = terminals.first(where: { $0.value === source })?.key {
            terminals[kind] = nil
            detachedAt[kind] = nil
        }
    }
}
