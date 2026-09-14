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
    private var optionKeyMonitor: Any?
    private var detachedAt: [TerminalKind: Date] = [:]
    private(set) var pendingFocusKind: TerminalKind?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { TerminalRegistry.shared.closeAll() }
        }
        installOptionKeyMonitor()
    }

    /// Option composes accents on this Mac (U.S. layout: ⌥c is ç, ⌥e a is á), so
    /// the terminals run with `optionAsMetaKey = false`. Arrows and other function
    /// keys still need Meta, or the shell loses word jumps — flip the flag for the
    /// length of those events only.
    private func installOptionKeyMonitor() {
        optionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            let handled = MainActor.assumeIsolated { () -> Bool in
                let registry = TerminalRegistry.shared
                // SwiftTerm's `keyDown` is not open, so Shift+Enter is answered
                // here: the focused terminal gets the newline byte and the event
                // stops, or the legacy encoding would send a plain Return.
                if TerminalKeyboard.sendsNewline(keyCode: keyCode, flags: flags),
                   let focused = registry.focusedTerminal() {
                    focused.send(TerminalKeyboard.newlineBytes)
                    return true
                }
                guard TerminalKeyboard.optionActsAsMeta(for: flags) else { return false }
                for term in registry.terminals.values where term.window?.firstResponder === term {
                    term.optionAsMetaKey = true
                    DispatchQueue.main.async { term.optionAsMetaKey = false }
                }
                return false
            }
            return handled ? nil : event
        }
    }

    /// The terminal that currently owns the keyboard, if any.
    private func focusedTerminal() -> LocalProcessTerminalView? {
        terminals.values.first { $0.window?.firstResponder === $0 }
    }

    func terminal(for kind: TerminalKind) -> LocalProcessTerminalView {
        detachedAt[kind] = nil
        if let live = terminals[kind] { return live }
        let term = LegacyKeyboardTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        term.processDelegate = self
        term.optionAsMetaKey = false
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

    /// Give the keyboard to this session as soon as its view is on screen. The
    /// request comes from an explicit user action (opening a session); mounting
    /// alone must never grab focus, or SwiftUI loses the sidebar's clicks.
    func requestFocus(_ kind: TerminalKind) {
        pendingFocusKind = kind
        applyPendingFocus()
    }

    /// A pane just put the shared view back in a window.
    func viewDidAttach(_ kind: TerminalKind) {
        guard pendingFocusKind == kind else { return }
        // Next runloop: SwiftUI is still mid-layout, and taking first responder
        // inside it is what used to make the sidebar unclickable.
        DispatchQueue.main.async { [weak self] in self?.applyPendingFocus() }
    }

    private func applyPendingFocus() {
        guard let kind = pendingFocusKind,
              let term = terminals[kind],
              let window = term.window
        else { return }
        pendingFocusKind = nil
        // A sheet (rename, new session, setup) owns the keyboard while it is up.
        guard window.isKeyWindow else { return }
        window.makeFirstResponder(term)
    }

    func close(_ kind: TerminalKind) {
        detachedAt[kind] = nil
        if pendingFocusKind == kind { pendingFocusKind = nil }
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
                    environment: RemoteCommands.terminalEnvironment(term: RemoteCommands.remoteTerm)
                )
            } else {
                term.startProcess(
                    executable: "/usr/bin/ssh",
                    args: [alias, "-t", RemoteCommands.newSession(name: session)],
                    environment: RemoteCommands.terminalEnvironment(term: RemoteCommands.remoteTerm)
                )
            }
        case .opsShell:
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

// Claude Code 2.1.269+ turns on the kitty keyboard protocol wherever it can,
// and tmux forwards it to any client whose XTVERSION reply says "XTerm(...)".
// SwiftTerm's kitty encoding still breaks Enter and dead keys, so the view
// drops both replies: programs keep the legacy encoding this app always ran.
final class LegacyKeyboardTerminalView: LocalProcessTerminalView {
    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let filtered = TerminalReplyFilter.strip(Array(data))
        guard !filtered.isEmpty else { return }
        super.send(source: source, data: filtered[...])
    }
}

enum TerminalKeyboard {
    /// Option means Meta only together with a function key (arrows, F-keys); on
    /// its own it is the accent composer of the Mac's keyboard layout.
    static func optionActsAsMeta(for flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.option) && flags.contains(.function)
    }

    static let returnKeyCode: UInt16 = 36

    /// Ctrl+J, which Claude Code reads as "insert a newline" in every terminal.
    static let newlineBytes: [UInt8] = [0x0A]

    /// The legacy key encoding this app keeps on purpose cannot tell Shift+Enter
    /// from Enter, so the terminal sends the newline byte itself. Enter alone
    /// still submits, and Command+Shift+Return stays an app shortcut.
    static func sendsNewline(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let mods = flags.intersection(.deviceIndependentFlagsMask)
        return keyCode == returnKeyCode
            && mods.contains(.shift)
            && !mods.contains(.command)
            && !mods.contains(.control)
            && !mods.contains(.option)
    }
}
